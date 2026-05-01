-- Pandoc Lua filter for the inline-script docs build system.
--
-- PURPOSE
--
-- Turns README.md.template into README.md. Code blocks annotated with key=
-- are hashed, compiled into runners, and executed by `make`. A second filter
-- pass reads the cached outputs and splices them into the rendered document.
-- The driving Makefile lives in recipes/Makefile; it calls this filter twice
-- with `make` in between.
--
-- LIFECYCLE (three invocations)
--
--   1. Dry-run: pass -M write-user-dependencies=<path> to pandoc. The filter
--      walks the template, hashes every key= block, writes each body to
--      cache/<hash>/body.<ext>, and emits a self-contained makefile fragment
--      to <path>. Pandoc's rendered output is discarded -- the .d file is the
--      deliverable. Cached outputs are not read; replace=K/both and similar
--      substitutions return "".
--
--   2. The outer Makefile includes the .d file. Its `all:` target lists every
--      cache file referenced by the document; each rule says "to produce
--      cache/<hash>/stdout, depend on the runner, cache/<hash>/body.<ext>, and
--      each dep's cache/<hash_D>/<sub>, then exec the runner". Running `make`
--      executes every needed body in topological order, populating the cache.
--
--   3. Real run: same filter, same template, -M write-user-dependencies absent.
--      Every cache/<hash>/<sub> the document needs now exists on disk. The
--      filter reads those files and splices their contents in place of the
--      annotated blocks. Pandoc's output is the final rendered document.
--
-- TWO-PASS WALK (each invocation)
--
--   Pass 1 (collect): pandoc.walk_block records every key= block body into
--   `pending` without resolving anything. Detects duplicate keys.
--
--   Pass 2 (render): walk in document order. When a replace=K/... is seen,
--   ensure_defined(K) lazily hashes K -- recursing depth-first through K's
--   depends= chain -- before reading its hash or output. This is what makes
--   replace= and depends= order-independent within the document.
--
-- REQUIRED ENVIRONMENT
--
--   CACHE_DIR  Absolute path to the cache directory (errors if unset).
--   FILTER_DIR Derived from debug.getinfo; runners must live alongside this
--              filter file. No extra env var needed for their location.
--
-- CACHE LAYOUT
--
--   cache/<hash>/body.<ext>   Source written at dry-run time.
--   cache/<hash>/stdout       Captured standard output (runner-produced).
--   cache/<hash>/stderr       Captured standard error (runner-produced).
--   cache/<hash>/both         stdout and stderr interleaved (runner-produced).
--   cache/<hash>/<artifact>   Any declared outputs= artifact. The runner cd's
--                             into cache/<hash>/ before running the body, so
--                             artifacts written to cwd land there automatically.
--
-- HASHING MODEL (cache invalidation)
--
--   hash = sha1(runner_content || resolved_body)
--
--   resolved_body is derived from the raw block body by:
--     - Substituting each $D (D from depends=) with the literal absolute path
--       CACHE_DIR/<hash_D>. Longest base-key match wins; safe in any language
--       because the path is absolute and needs no shell expansion.
--     - Substituting $_REPLACE_KEY with the key name K.
--
--   Because runner_content is mixed into the hash, editing a runner file
--   (run-bash.sh, run-lua.sh) invalidates every cache entry that uses it.
--
-- LANGUAGES
--
--   LANG_INFO maps a Pandoc class name to {ext, runner-path}:
--     .bash  ->  body.sh,  run-bash.sh   (default)
--     .lua   ->  body.lua, run-lua.sh
--   lang_from_classes picks the first recognized class; classless or
--   unrecognized blocks fall back to DEFAULT_LANG (bash).
--   To add a language: add an entry to LANG_INFO and place run-<lang>.sh
--   alongside this filter.
--
-- ATTRIBUTES (CodeBlock / Code / Span)
--
--   key=K               Defines block K. Body is its source.
--                       K must match [a-zA-Z_][a-zA-Z0-9_]*; duplicates error.
--                       $D (D in depends=) is replaced with CACHE_DIR/<hash_D>
--                       before hashing. $_REPLACE_KEY is replaced with K.
--                       Longest-base match wins for $D substitution.
--
--   depends=A,B/sub,..  Only on key= blocks. Bare A means A/stdout.
--                       sub must be stdout|stderr|both or a name in A's outputs=.
--                       Adds a make prereq and licenses $A in the body.
--
--   outputs=a,b,c       Only on key= blocks. Declares artifact filenames the body
--                       writes to its cwd (= cache/<hash>/). Reserved names
--                       (stdout, stderr, both, source, null) are rejected.
--                       The runner verifies each artifact exists after the body
--                       exits and fails if it does not.
--
--   replace=<value>     Required on every annotated block. See taxonomy below.
--
--   subst=VAR->K[/thing],...
--                       Only meaningful when the rendered content is a source
--                       (own block or cross-block). Substitutes $VAR in the
--                       rendered source after region extraction. thing defaults
--                       to both. Render-time only; not folded into the hash.
--
-- REPLACE= TAXONOMY
--
--   null                Drop the block from output. Body still runs when key=
--                       is present. Idiom: hidden setup block.
--
--   source              Render this key's body. Requires key=.
--   source/<region>     Render only the named docs:begin/end region. Requires key=.
--                       "null" is reserved and cannot be used as a region name.
--
--   stdout|stderr|both  Render this key's captured stream. Requires key=.
--
--   <artifact>          Render this key's declared artifact. Requires key=;
--                       artifact name must appear in outputs=.
--
--   K                   Cross-block: render K's "both" output (default thing).
--   K/<thing>           Cross-block: render K's thing.
--                       thing is stdout|stderr|both|source[/<region>]|<artifact>.
--                       Forces lazy definition of K via ensure_defined.
--
--   Inline Code:        Only cross-block forms (K or K/<thing>) are allowed.
--   Inline Span:        Only cross-block forms. The Span's inline content is
--                       appended as a literal suffix to the rendered output
--                       (idiom: insert punctuation after a substituted value).
--
-- DOCS:BEGIN/END SEMANTICS
--
--   Marker syntax:  <comment-leader> docs:begin <name>
--                   <comment-leader> docs:end   <name>
--   Comment leaders: #, --, // (with optional surrounding whitespace).
--   <name> may be empty (unnamed default region).
--
--   Special name "null":
--     docs:begin null / docs:end null lines and everything between them are
--     stripped from the rendered source but still execute. Use this to hide
--     imports or setup boilerplate. Multiple non-overlapping null regions are
--     allowed; nesting is not permitted.
--
--   Named region:
--     replace=source/<name> renders only the content between the matching
--     docs:begin <name> / docs:end <name> pair. Markers are stripped.
--
-- OUTPUT POST-PROCESSING
--
--   read_output strips ANSI escape sequences and the trailing newline before
--   substitution. Bodies relying on exact byte-level capture should not use
--   replace= to consume their output.
--
-- MAKE-FRAGMENT SHAPE (dry-run)
--
--   Primary target:  cache/<hash>/stdout  (depends on runner + body.<ext> + dep stdouts)
--   Sibling targets: cache/<hash>/stderr, cache/<hash>/both, each declared artifact.
--   Siblings depend on the primary with an empty recipe (portable to GNU Make 3.81,
--   which predates `&:` grouped-target syntax).
--
-- PANDOC RENDERING QUIRK
--
--   force_fenced upgrades classless CodeBlocks to class "text" so Pandoc
--   emits a fenced (not 4-space-indented) GFM code block.
--
-- INVARIANTS / GOTCHAS
--
--   - Duplicate key= definitions error during pass 1.
--   - Dependency cycles error during ensure_defined.
--   - outputs= artifacts not written by the body cause the runner to fail.
--   - subst= is render-time only; changing a subst source does not re-run scripts.
--   - $D substitution requires a non-word boundary after D so $foo does not
--     consume the start of $foobar; longest base wins for disambiguation.

local deps_file
local CACHE_DIR = os.getenv("CACHE_DIR") or error("CACHE_DIR not set")

-- Locate the directory containing this filter file; runners live alongside it.
local FILTER_DIR = (debug.getinfo(1, "S").source:match("^@(.+)$") or "replace.lua"):match("(.+)/[^/]+$") or "."

-- Map language class to {ext, runner-path}. The runner's content is read once
-- and mixed into the per-block hash so runner edits invalidate old cache entries.
local LANG_INFO = {
    bash = { ext = "sh",  runner = FILTER_DIR .. "/run-bash.sh" },
    lua  = { ext = "lua", runner = FILTER_DIR .. "/run-lua.sh"  },
}
local DEFAULT_LANG = "bash"

local runner_content_cache = {}
local function get_runner_content(lang)
    if runner_content_cache[lang] then return runner_content_cache[lang] end
    local info = LANG_INFO[lang] or LANG_INFO[DEFAULT_LANG]
    local f = assert(io.open(info.runner, "r"), "runner not found: " .. info.runner)
    local c = f:read("a"); f:close()
    runner_content_cache[lang] = c
    return c
end

local RESERVED = { stdout = true, stderr = true, both = true, source = true, null = true }

-- State accumulated as the document is walked.
local pending   = {}  -- key -> { attr, body, lang }  (pass 1: raw collection)
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
-- Emits the literal absolute path CACHE_DIR/hash so non-bash bodies can use
-- it directly without shell expansion. Bash bodies are unaffected (absolute
-- paths expand to themselves in any shell context).
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
                        out[#out + 1] = CACHE_DIR .. "/" .. keys[base]
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

-- Strip docs:begin null / docs:end null ranges (inclusive) from body.
-- Lines inside those markers still execute; they are just hidden from rendered
-- source. Multiple non-overlapping null regions are allowed. Nesting is not.
local function strip_null_regions(body, label)
    if not body:find("[#%-/]+%s*docs:begin%s+null") then return body end
    local scan = body:sub(-1) == "\n" and body or (body .. "\n")
    local out = {}
    local in_null = false
    for line in scan:gmatch("([^\n]*)\n") do
        if not in_null then
            if line:match("^%s*[#%-/]+%s*docs:begin%s+null%s*$") then
                in_null = true
            elseif line:match("^%s*[#%-/]+%s*docs:end%s+null%s*$") then
                error(string.format("%s: docs:end null without matching docs:begin null", label))
            else
                out[#out + 1] = line
            end
        else
            if line:match("^%s*[#%-/]+%s*docs:end%s+null%s*$") then
                in_null = false
            elseif line:match("^%s*[#%-/]+%s*docs:begin%s+null%s*$") then
                error(string.format("%s: nested docs:begin null", label))
            end
        end
    end
    assertf(not in_null, "%s: unterminated docs:begin null", label)
    local result = table.concat(out, "\n")
    if body:sub(-1) == "\n" then result = result .. "\n" end
    return result
end

-- Extract a "docs:begin NAME" / "docs:end NAME" region from body.
-- Comment leaders #, --, // (and variants) are stripped before the keyword.
-- NAME may be empty (the unnamed default region). Markers are stripped.
local function extract_region(body, name, label)
    local target = name or ""
    local markers = {}
    -- Ensure the last line is terminated so a final docs:end at EOF is matched.
    local scan = body:sub(-1) == "\n" and body or (body .. "\n")
    scan:gsub("()[%s]*[#%-/]+[%s]*docs:(%a+)[ \t]*(.-)[ \t]*()\n", function(s, kw, rname, e)
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
    if deps_file then return "" end
    local path = CACHE_DIR .. "/" .. hash .. "/" .. sub
    local f = assert(io.open(path, "r"), label .. ": cannot open " .. path)
    local txt = f:read("a")
    f:close()
    return (strip_ansi(txt):gsub("\n$", ""))
end

-- Derive language from a codeblock's class list. Returns the first recognized
-- language, or DEFAULT_LANG if none match.
local function lang_from_classes(classes)
    for _, cls in ipairs(classes or {}) do
        if LANG_INFO[cls] then return cls end
    end
    return DEFAULT_LANG
end

-- Ensure cache/<hash>/body.<ext> exists with the given content.
local function write_body(hash, ext, content)
    local dir = CACHE_DIR .. "/" .. hash
    local path = dir .. "/body." .. ext
    local f = io.open(path, "r")
    if f then f:close(); return end
    os.execute("mkdir -p '" .. dir .. "'")
    f = assert(io.open(path, "w"))
    f:write(content)
    f:close()
end

local function define_script(key, attr, body, classes)
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
    -- Substitute dep paths and $_REPLACE_KEY before hashing and writing.
    local resolved = substitute(body, deps)
    resolved = resolved:gsub("%$_REPLACE_KEY%f[%W]", function() return key end)
    local lang = lang_from_classes(classes)
    local info = LANG_INFO[lang]
    local runner_content = get_runner_content(lang)
    -- Hash includes both the resolved body and the runner so that runner
    -- changes invalidate all cache entries that depend on it.
    local hash = pandoc.utils.sha1(runner_content .. resolved)
    keys[key] = hash
    outputs_t[key] = {}
    for _, n in ipairs(out_list) do outputs_t[key][n] = true end
    sources[key] = resolved
    write_body(hash, info.ext, resolved)
    if deps_file then emit_rule(key, hash, info, out_list, deps) end
    return resolved
end

-- Emit a make rule. stdout is the primary target; stderr, both, and any
-- declared artifacts are sibling targets that depend on the primary.
-- (GNU Make 3.81 predates `&:` grouped-target syntax.)
function emit_rule(key, hash, info, out_list, deps)
    local runner_path = info.runner
    local body_path = "$(CACHE_DIR)/" .. hash .. "/body." .. info.ext
    local prereqs = {runner_path, body_path}
    for _, d in ipairs(deps) do
        prereqs[#prereqs + 1] = "$(CACHE_DIR)/" .. keys[d.base] .. "/" .. d.sub
    end
    local primary = "$(CACHE_DIR)/" .. hash .. "/stdout"
    local siblings = {"stderr", "both"}
    for _, n in ipairs(out_list) do siblings[#siblings + 1] = n end
    local cmd = string.format("\t@_REPLACE_KEY=%s bash %s %s", key, runner_path, body_path)
    rules[#rules + 1] = primary .. ": " .. table.concat(prereqs, " ") .. "\n" .. cmd
    for _, s in ipairs(siblings) do
        rules[#rules + 1] = "$(CACHE_DIR)/" .. hash .. "/" .. s .. ": " .. primary
    end
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
    define_script(key, p.attr, p.body, p.classes)
    defining[key] = nil
end

-- Pandoc gfm renders a classless CodeBlock as 4-space-indented; force fence.
local function force_fenced(el)
    local has_attrs = false
    for _ in pairs(el.attr.attributes) do has_attrs = true; break end
    if #el.classes == 0 and not has_attrs and el.identifier == "" then
        el.classes = {"text"}
    end
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
    if val:sub(1, 7) == "source/" then
        local region = val:sub(8)
        assertf(region ~= "null", "replace=source/null: 'null' is a reserved marker name, not a region")
        return "source", region
    end
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
    text = strip_null_regions(text, label)
    if region or text:find("[#%-/]+%s*docs:begin") then
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
    local f = assert(io.open(deps_file, "w"))
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
    pending[key] = { attr = b.attr.attributes, body = b.text, classes = b.classes }
end

local function collect(blocks)
    pandoc.walk_block(pandoc.Div(blocks), {CodeBlock = collect_codeblock})
end

function Pandoc(doc)
    local m = doc.meta["write-user-dependencies"]
    deps_file = m and pandoc.utils.stringify(m) or nil
    collect(doc.blocks)
    doc.blocks = walk_blocks(doc.blocks)
    if deps_file then emit_deps() end
    return doc
end

return {{Pandoc = Pandoc}}
