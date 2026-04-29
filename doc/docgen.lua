-- Pandoc Lua filter for the inline-script docs build system.
--
-- USAGE
--
-- The filter is run twice over the same template, with `make` in between:
--
--   1. Dry-run with DEPS_FILE set. The filter walks the template, computes
--      a content hash for every key= block, writes cache/<hash>/script.sh
--      for each, and emits a self-contained makefile fragment to
--      $DEPS_FILE. Pandoc's rendered output from this run is discarded --
--      the deliverable is the .d file. Cached outputs are not read in this
--      run; replace=K/both and similar substitutions return "".
--
--   2. The outer Makefile includes the .d file. Its `all:` target lists
--      every cache file referenced by the document, and each rule says
--      "to produce cache/<hash>/<sub>, depend on cache/<hash>/script.sh
--      and on each dep's cache file, then run the script". Running `make`
--      therefore executes every needed script in topological order,
--      populating the cache.
--
--   3. Real run: same filter, same template, but DEPS_FILE is unset and
--      every cache/<hash>/<sub> referenced by the document now exists on
--      disk. The filter walks the template again; replace=K/both reads
--      cache/<hash_K>/both, replace=source renders K's body, and so on.
--      Pandoc's output is the final rendered document.
--
-- Both filter runs use the same two-pass walk internally:
--
--   Pass 1 (collect): pandoc.walk_block records every key= block's body
--   into `pending` without resolving anything. Detects duplicate keys.
--
--   Pass 2 (render): walk in document order, processing each CodeBlock
--   and inline Code/Span. Each replace=K/... calls ensure_defined(K),
--   which lazily defines K -- recursing depth-first through K's depends=
--   -- before reading its hash or output. This makes replace= and
--   depends= order-independent within the document.
--
-- Cache layout: cache/<hash>/script.sh, plus outputs in cache/<hash>/.
-- The PREAMBLE redirects stdout -> cache/<hash>/stdout, stderr ->
-- cache/<hash>/stderr, and both streams -> cache/<hash>/both. Artifacts
-- declared in outputs= are written by the script to its cwd.
--
-- Attributes (CodeBlock / Code / Span):
--   key=K               Defines script K. The block body is its bash source.
--                       In the body, every $D occurrence (D from depends=)
--                       is replaced before hashing with $CACHE_DIR/<hash_D>.
--                       Longest-base-key match wins.
--   depends=A,B/sub,..  On key= blocks: list of dep refs. Bare A means
--                       A/stdout. Resolves to a make prereq and licences
--                       $A in the body.
--   outputs=a,b,c       On key= blocks: declares artifact filenames produced
--                       by the script (written to cwd = cache/<hash>/).
--                       Reserved names (stdout, stderr, both, source, null)
--                       are not allowed.
--   replace=<value>     What to render in place of this block. Values:
--     null              Drop the block.
--     source[/<region>] This key's body (optionally a docs:begin/end region).
--     stdout|stderr|both  This key's captured stream (requires key=).
--     <artifact>        This key's declared artifact (requires key=, name in
--                       outputs=).
--     K[/<thing>]       Cross-block: render K's thing (default: both).
--                       thing is stdout|stderr|both|<artifact>|source[/<region>].
--   subst=VAR->K[/thing],...  On replace=source only: substitute $VAR with
--                       K's thing after extracting the region. thing defaults
--                       to both. Render-time only; not folded into the hash.

local DEPS_FILE   = os.getenv("DEPS_FILE")
local CACHE_DIR   = os.getenv("CACHE_DIR")   or error("CACHE_DIR not set")
local RECIPES_DIR = os.getenv("RECIPES_DIR") or error("RECIPES_DIR not set")

-- PREAMBLE is split so the echo (progress line) runs before the exec redirect.
-- exec redirect captures everything into stdout/stderr/both; echo must precede it
-- so it reaches the terminal (not the captured files) -- matching old behavior.
local PREAMBLE_HEADER = [[#!/bin/bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
]]
-- Capture redirect feeds tees via process substitution; the trap closes FDs 1/2
-- before `wait` so the tees see EOF and exit. Without the close, `wait` deadlocks:
-- the trap fires while FD 1/2 still point at the tee pipes, so the tees never EOF.
local PREAMBLE_CAPTURE = [[exec > >(tee stdout >> both) 2> >(tee stderr >> both)
trap 'exec >&- 2>&-; wait' EXIT
export PATH="$RECIPES_DIR:$PATH"
export LUA_PATH="$RECIPES_DIR/?.lua;${LUA_PATH:-}"
]]

local RESERVED = { stdout = true, stderr = true, both = true, source = true, null = true }

-- State accumulated as the document is walked.
local pending   = {}  -- key -> { attr, body }  (pass 1: raw collection)
local defining  = {}  -- key -> true  (cycle detection during ensure_defined)
local keys      = {}  -- key -> hash
local outputs_t = {}  -- key -> { artifact_name -> true }
local sources   = {}  -- key -> resolved body (for replace=source)
local rules     = {}  -- list of make rule strings (dry-run only)
local consumed  = {}  -- "<hash>/<file>" -> true (referenced cache files)

local function assertf(cond, fmt, ...)
    if not cond then error(string.format(fmt, ...)) end
end

local function check_identifier(s, label)
    assertf(s:match("^[%a_][%w_]*$"),
        "%s: '%s' is not an identifier (must match [a-zA-Z_][a-zA-Z0-9_]*)", label, s)
end

local function strip_ansi(s)
    return (s:gsub("\27%[[%d;]*[mGK]", ""):gsub("\r", ""))
end

local function parse_list(s)
    local r = {}
    if not s then return r end
    for tok in s:gmatch("[^,%s]+") do r[#r + 1] = tok end
    return r
end

local function parse_depends(s)
    local r = {}
    for _, tok in ipairs(parse_list(s)) do
        local base, sub = tok:match("^([%w._%-]+)/([%w._%-]+)$")
        if not base then base, sub = tok, "stdout" end
        check_identifier(base, "depends=" .. tok)
        r[#r + 1] = {base = base, sub = sub, raw = tok}
    end
    return r
end

local function parse_subst(s)
    local r = {}
    if not s then return r end
    for var, ref in s:gmatch("([%w_]+)%->([%w._%-/]+)") do
        local base, sub = ref:match("^([%w._%-]+)/(.+)$")
        if not base then base, sub = ref, "both" end
        check_identifier(base, "subst=" .. var .. "->" .. ref)
        r[#r + 1] = {var = var, base = base, sub = sub, raw = ref}
    end
    return r
end

-- Substitute $K in body for K in deps' unique base keys, longest first.
-- A match must be followed by end-of-string or a non-key character so $foo
-- doesn't match the start of $foobar.
local function substitute(body, deps)
    local seen, bases = {}, {}
    for _, d in ipairs(deps) do
        if not seen[d.base] then
            seen[d.base] = true
            bases[#bases + 1] = d.base
        end
    end
    table.sort(bases, function(a, b) return #a > #b end)
    local out, i, n = {}, 1, #body
    while i <= n do
        local c = body:sub(i, i)
        if c == "$" then
            local matched = false
            for _, base in ipairs(bases) do
                local len = #base
                if body:sub(i + 1, i + len) == base then
                    local nextc = body:sub(i + 1 + len, i + 1 + len)
                    if nextc == "" or not nextc:match("[%w._%-]") then
                        out[#out + 1] = "$CACHE_DIR/" .. keys[base]
                        i = i + 1 + len
                        matched = true
                        break
                    end
                end
            end
            if not matched then
                out[#out + 1] = "$"
                i = i + 1
            end
        else
            out[#out + 1] = c
            i = i + 1
        end
    end
    return table.concat(out)
end

-- Extract a "# docs:begin NAME" / "# docs:end NAME" region from body.
-- NAME may be empty (the unnamed default region). Markers are stripped.
local function extract_region(body, name, label)
    local target = name or ""
    local markers = {}
    -- Ensure the last line is terminated so a final docs:end at EOF is matched.
    local scan = body:sub(-1) == "\n" and body or (body .. "\n")
    scan:gsub("()# docs:(%a+)[ \t]*(.-)[ \t]*()\n", function(s, kw, rname, e)
        markers[#markers + 1] = {s = s, kw = kw, name = rname, e = e}
    end)
    local regions = {}
    for _, m in ipairs(markers) do
        regions[m.name] = regions[m.name] or {}
        local r = regions[m.name]
        if m.kw == "begin" then
            assertf(not r.first, "%s: duplicate docs:begin '%s'", label, m.name)
            r.first = m.e + 1
        elseif m.kw == "end" then
            assertf(not r.last, "%s: duplicate docs:end '%s'", label, m.name)
            r.last = m.s - 1
        end
    end
    local r = regions[target]
    assertf(r,                 "%s: no region '%s' found",                   label, target)
    assertf(r.first,           "%s: region '%s' has no docs:begin",          label, target)
    assertf(r.last,            "%s: region '%s' has no docs:end",            label, target)
    assertf(r.first <= r.last, "%s: region '%s' docs:end before docs:begin", label, target)
    return (scan:sub(r.first, r.last):gsub("\n$", ""))
end

local function read_output(hash, sub, label)
    consumed[hash .. "/" .. sub] = true
    if DEPS_FILE then return "" end
    local path = CACHE_DIR .. "/" .. hash .. "/" .. sub
    local f = assert(io.open(path, "r"), label .. ": cannot open " .. path)
    local txt = f:read("a")
    f:close()
    return (strip_ansi(txt):gsub("\n$", ""))
end

-- Ensure cache/<hash>/script.sh exists with the given content.
local function write_script(hash, content)
    local dir = CACHE_DIR .. "/" .. hash
    local path = dir .. "/script.sh"
    local f = io.open(path, "r")
    if f then f:close(); return end
    os.execute("mkdir -p '" .. dir .. "'")
    f = assert(io.open(path, "w"))
    f:write(content)
    f:close()
end

local function build_script_content(key, resolved, out_list)
    local parts = {PREAMBLE_HEADER}
    parts[#parts + 1] = string.format('echo "%s"\n', key)
    parts[#parts + 1] = PREAMBLE_CAPTURE
    parts[#parts + 1] = resolved
    if not resolved:match("\n$") then parts[#parts + 1] = "\n" end
    for _, n in ipairs(out_list) do
        parts[#parts + 1] = string.format(
            '[ -e "%s" ] || { echo "key=%s: declared output %q was not created" >&2; exit 1; }\n',
            n, key, n)
    end
    return table.concat(parts)
end

-- Emit a make rule. stdout is the primary target; stderr, both, and any
-- declared artifacts are sibling targets that depend on the primary.
-- (GNU Make 3.81 predates `&:` grouped-target syntax.)
local function emit_rule(hash, out_list, deps)
    local prereqs = {"$(CACHE_DIR)/" .. hash .. "/script.sh"}
    for _, d in ipairs(deps) do
        prereqs[#prereqs + 1] = "$(CACHE_DIR)/" .. keys[d.base] .. "/" .. d.sub
    end
    local primary = "$(CACHE_DIR)/" .. hash .. "/stdout"
    local siblings = {"stderr", "both"}
    for _, n in ipairs(out_list) do siblings[#siblings + 1] = n end
    rules[#rules + 1] = primary .. ": " .. table.concat(prereqs, " ") .. "\n\t@bash $<"
    for _, s in ipairs(siblings) do
        rules[#rules + 1] = "$(CACHE_DIR)/" .. hash .. "/" .. s .. ": " .. primary
    end
end

-- Pandoc gfm renders a classless CodeBlock as 4-space-indented; force fence.
local function force_fenced(el)
    local has_attrs = false
    for _ in pairs(el.attr.attributes) do has_attrs = true; break end
    if #el.classes == 0 and not has_attrs and el.identifier == "" then
        el.classes = {"text"}
    end
end

local function define_script(key, attr, body)
    assertf(not keys[key], "key=%s: duplicate definition", key)
    local out_list = parse_list(attr.outputs)
    for _, n in ipairs(out_list) do
        assertf(not RESERVED[n], "key=%s: outputs= cannot contain reserved name '%s'", key, n)
    end
    local deps = parse_depends(attr.depends)
    for _, d in ipairs(deps) do
        assertf(keys[d.base], "key=%s: depends=%s: '%s' not yet defined", key, d.raw, d.base)
        local valid = (d.sub == "stdout" or d.sub == "stderr" or d.sub == "both")
            or (outputs_t[d.base] and outputs_t[d.base][d.sub])
        assertf(valid, "key=%s: depends=%s: '%s' has no output '%s'", key, d.raw, d.base, d.sub)
    end
    local resolved = substitute(body, deps)
    local content = build_script_content(key, resolved, out_list)
    local hash = pandoc.utils.sha1(content)
    keys[key] = hash
    outputs_t[key] = {}
    for _, n in ipairs(out_list) do outputs_t[key][n] = true end
    sources[key] = resolved
    write_script(hash, content)
    if DEPS_FILE then emit_rule(hash, out_list, deps) end
    return resolved
end

-- Lazily define key and all its transitive depends= in DFS order.
local function ensure_defined(key)
    if keys[key] then return end
    assertf(not defining[key], "key=%s: dependency cycle", key)
    local p = pending[key]
    assertf(p, "key=%s: not defined", key)
    defining[key] = true
    for _, d in ipairs(parse_depends(p.attr.depends)) do
        ensure_defined(d.base)
    end
    define_script(key, p.attr, p.body)
    defining[key] = nil
end

-- Parse the replace= value into (kind, a, b).
-- kind == "null"     -> drop the block
-- kind == "source"   -> a = region string or nil
-- kind == "stream"   -> a = "stdout"|"stderr"|"both" (own key only)
-- kind == "artifact" -> a = artifact name (own key only; must be in outputs=)
-- kind == "cross"    -> a = K, b = thing (stream/artifact/source[/region])
local function parse_replace_target(val, self_key)
    if val == "null" then return "null" end
    if val == "source" then return "source", nil end
    if val == "stdout" or val == "stderr" or val == "both" then return "stream", val end
    if val:sub(1, 7) == "source/" then return "source", val:sub(8) end
    if self_key and outputs_t[self_key] and outputs_t[self_key][val] then
        return "artifact", val
    end
    local k, rest = val:match("^([%w._%-]+)/(.+)$")
    if k then return "cross", k, rest end
    if val:match("^[%w._%-]+$") then return "cross", val, "both" end
    error("replace=" .. val .. ": unrecognized value")
end

local render_source  -- forward declaration (render_source <-> cross_read mutual ref)

local function cross_read(K, thing, subst_spec, label)
    ensure_defined(K)
    assertf(keys[K], "%s: key '%s' not defined", label, K)
    if thing == "source" then
        assertf(sources[K], "%s: replace=source: source not stored for '%s'", label, K)
        return render_source(sources[K], nil, subst_spec, label)
    end
    if thing:sub(1, 7) == "source/" then
        local region = thing:sub(8)
        assertf(sources[K], "%s: replace=source: source not stored for '%s'", label, K)
        return render_source(sources[K], region, subst_spec, label)
    end
    if thing == "stdout" or thing == "stderr" or thing == "both" then
        return read_output(keys[K], thing, label)
    end
    assertf(outputs_t[K] and outputs_t[K][thing],
        "%s: key '%s' has no artifact '%s'", label, K, thing)
    return read_output(keys[K], thing, label)
end

render_source = function(text, region, subst_spec, label)
    if region or text:find("# docs:begin", 1, true) then
        text = extract_region(text, region, label)
    end
    for _, p in ipairs(subst_spec or {}) do
        ensure_defined(p.base)
        local val
        if p.sub == "source" then
            val = render_source(sources[p.base], nil, nil, label .. ": subst=" .. p.var)
        elseif p.sub:sub(1, 7) == "source/" then
            local r = p.sub:sub(8)
            val = render_source(sources[p.base], r, nil, label .. ": subst=" .. p.var)
        else
            val = read_output(keys[p.base], p.sub, label .. ": subst=" .. p.var .. "->" .. p.raw)
        end
        text = text:gsub('%$' .. p.var .. '%f[%W]', function() return val end)
    end
    return text
end

-- The filter uses two passes. Pass 1 (collect) uses pandoc.walk_block to
-- record every key= block body without resolving anything. Pass 2
-- (walk_blocks) renders in document order, lazily defining each key on
-- demand via DFS through depends=. Both replace= and depends= are therefore
-- order-independent.

local function process_codeblock(el)
    local attr = el.attr.attributes
    local key, replace = attr.key, attr.replace
    if not key and not replace then return el end

    if key then ensure_defined(key) end
    assertf(replace, "%s: replace= attribute required", key and "key=" .. key or "CodeBlock")

    local subst_spec = parse_subst(attr.subst)
    attr.key = nil
    attr.ref = nil
    attr.depends = nil
    attr.outputs = nil
    attr.replace = nil
    attr.block = nil
    attr.subst = nil

    if replace == "null" then return {} end

    local label = key and "key=" .. key or "replace=" .. replace
    local kind, a, b = parse_replace_target(replace, key)

    if kind == "null" then return {} end
    if kind == "source" then
        assertf(key, "%s: replace=source requires key=", label)
        el.text = render_source(sources[key], a, subst_spec, label)
        force_fenced(el)
        return el
    end
    if kind == "stream" or kind == "artifact" then
        assertf(key, "%s: replace=%s requires key=", label, a)
        el.text = read_output(keys[key], a, label)
        force_fenced(el)
        return el
    end
    if kind == "cross" then
        el.text = cross_read(a, b, subst_spec, label)
        force_fenced(el)
        return el
    end
    error(label .. ": unknown replace= value")
end

local function process_code(el)
    local attr = el.attr.attributes
    local replace = attr.replace
    if not replace then return el end
    attr.replace = nil
    local label = "inline Code replace=" .. replace
    local kind, a, b = parse_replace_target(replace, nil)
    if kind == "cross" then
        el.text = cross_read(a, b, nil, label)
        return el
    end
    error(label .. ": only cross-block replace= (K or K/<thing>) supported on inline Code")
end

local function process_span(el)
    local attr = el.attr.attributes
    local replace = attr.replace
    if not replace then return el end
    attr.replace = nil
    local label = "inline Span replace=" .. replace
    local kind, a, b = parse_replace_target(replace, nil)
    if kind == "cross" then
        local suffix = pandoc.utils.stringify(el.content)
        return pandoc.Code(cross_read(a, b, nil, label) .. suffix)
    end
    error(label .. ": only cross-block replace= (K or K/<thing>) supported on inline Span")
end

local INLINE_FILTER = {Code = process_code, Span = process_span}

-- Walk a list of blocks in document order, processing CodeBlocks via
-- process_codeblock and recursing into block containers (Div, BlockQuote,
-- list items) so nested key=/replace= blocks are handled. Inline filters run
-- on every visited block.
local walk_blocks
local function walk_block(b)
    if b.tag == "CodeBlock" then return process_codeblock(b) end
    if b.content and (b.tag == "Div" or b.tag == "BlockQuote") then
        b.content = walk_blocks(b.content)
        return pandoc.walk_block(b, INLINE_FILTER)
    end
    if (b.tag == "BulletList" or b.tag == "OrderedList") and b.content then
        for i, item in ipairs(b.content) do b.content[i] = walk_blocks(item) end
        return pandoc.walk_block(b, INLINE_FILTER)
    end
    return pandoc.walk_block(b, INLINE_FILTER)
end

walk_blocks = function(blocks)
    local out = {}
    for _, b in ipairs(blocks) do
        local r = walk_block(b)
        if type(r) == "table" and not r.tag then
            for _, x in ipairs(r) do out[#out + 1] = x end
        elseif r then
            out[#out + 1] = r
        end
    end
    return out
end

local function sorted(t)
    local r = {}
    for k in pairs(t) do r[#r + 1] = k end
    table.sort(r)
    return r
end

local function emit_deps()
    local f = assert(io.open(DEPS_FILE, "w"))
    f:write("all:")
    for _, c in ipairs(sorted(consumed)) do
        f:write(" $(CACHE_DIR)/" .. c)
    end
    f:write("\n")
    for _, r in ipairs(rules) do
        f:write(r .. "\n")
    end
    f:close()
end

local function collect_codeblock(b)
    local key = b.attr.attributes.key
    if not key then return end
    check_identifier(key, "key=" .. key)
    assertf(not pending[key], "key=%s: duplicate definition", key)
    pending[key] = { attr = b.attr.attributes, body = b.text }
end

local function collect(blocks)
    pandoc.walk_block(pandoc.Div(blocks), {CodeBlock = collect_codeblock})
end

function Pandoc(doc)
    collect(doc.blocks)
    doc.blocks = walk_blocks(doc.blocks)
    if DEPS_FILE then emit_deps() end
    return doc
end

return {{Pandoc = Pandoc}}
