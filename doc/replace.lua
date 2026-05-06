-- Pandoc Lua filter for the inline-script docs build system.
--
-- PURPOSE
--
-- Turns README.md.template into README.md. Code blocks annotated with key=
-- are written to cache/<key>/, executed by `make`, and their outputs spliced
-- back into the rendered document. The driving Makefile lives in
-- recipes/Makefile; it calls this filter twice with `make` in between.
--
-- LIFECYCLE (three invocations)
--
--   1. Dry-run: pass -M write-user-dependencies=<path> to pandoc. The filter
--      walks the template, writes each block body to cache/<key>/body.<ext>
--      (idempotently), writes cache/<key>/spec when contents-form subst=
--      entries exist, and emits a self-contained makefile fragment to <path>.
--      Pandoc's rendered output is discarded -- the .d file is the deliverable.
--      Cached outputs are not read; replace=K/both and similar return "".
--
--   2. The outer Makefile includes the .d file. Its `all:` target lists every
--      cache file referenced by the document; each rule says "to produce
--      cache/<key>/stdout, depend on the runner, cache/<key>/body.<ext>, and
--      each dep's output file, then exec the runner". Running `make` executes
--      every needed body in topological order, populating the cache.
--
--   3. Real run: same filter, same template, -M write-user-dependencies absent.
--      Every cache/<key>/<sub> the document needs now exists on disk. The
--      filter reads those files and splices their contents in place of the
--      annotated blocks. Pandoc's output is the final rendered document.
--
-- TWO-PASS WALK (each invocation)
--
--   Pass 1 (collect): pandoc.walk_block records every key= block body, parsed
--   deps, and parsed subst into `pending` without resolving anything.
--   Detects duplicate keys.
--
--   Pass 2 (render): walk in document order. When a replace=K/... is seen,
--   ensure_defined(K) lazily defines K -- recursing depth-first through K's
--   depends= and subst= chains -- before reading its output. This is what
--   makes replace= and depends= order-independent within the document.
--
-- REQUIRED ENVIRONMENT
--
--   REPLACE_CACHE_DIR  Absolute path to the cache directory (errors if unset).
--   REPLACE_DIR Derived from PANDOC_SCRIPT_FILE; runners and subst.lua
--              live alongside this filter file.
--
-- CACHE LAYOUT
--
--   cache/<key>/body.<ext>     Source written at dry-run time (idempotent).
--   cache/<key>/spec           VAR=path lines for contents-form subst= entries
--                              (written at dry-run time, idempotent).
--   cache/<key>/body.run.<ext> Body with contents-form $VAR expanded (runner-produced).
--   cache/<key>/stdout         Captured standard output (runner-produced).
--   cache/<key>/stderr         Captured standard error (runner-produced).
--   cache/<key>/both           stdout and stderr interleaved (runner-produced).
--   cache/<key>/<artifact>     Any declared outputs= artifact. The runner cd's
--                              into cache/<key>/ before running the body, so
--                              artifacts written to cwd land there automatically.
--
-- CACHE INVALIDATION
--
--   Make drives invalidation via mtimes. body.<ext> and spec are written
--   idempotently (skipped when content is unchanged) to avoid spurious rebuilds.
--   The runner (run-bash.sh / run-lua.sh) and subst.lua are listed as make
--   prereqs for every rule that uses them, so editing those files triggers
--   a rebuild of all affected blocks.
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
--                       $REPLACE_KEY is replaced with K before writing body.
--
--   depends=A,B,...     Only on key= blocks. Bare keys only (no K/sub).
--                       Each K adds a make prereq on cache/<K>/stdout.
--                       Reserved for ordering-only cases (e.g., two blocks that
--                       bind the same port). Use subst= when $K is in the body.
--
--   subst=VAR->REF,...  Path injection and contents substitution. REF forms:
--                         VAR->K          path-form: $VAR -> REPLACE_CACHE_DIR/K
--                         VAR->K/SUB      contents-form: $VAR -> bytes of cache/<K>/SUB
--                         VAR->K/SUB/path path-form: $VAR -> REPLACE_CACHE_DIR/K/SUB
--                       Path-form entries are substituted in body.<ext> at dry-run
--                       time. Contents-form entries are written to cache/<K>/spec
--                       and expanded by subst.lua at runner time (producing
--                       body.run.<ext>). Both forms also add make prereqs.
--
--   outputs=a,b,c       Only on key= blocks. Declares artifact filenames the body
--                       writes to its cwd (= cache/<key>/). Reserved names
--                       (stdout, stderr, both, source, null) are rejected.
--                       The runner verifies each artifact exists after the body
--                       exits and fails if it does not.
--
--   enabled=yes|no      Optional. Controls whether this block is active.
--                       When absent, the value of the -M default-replace=
--                       pandoc variable applies (true/yes/1 -> enabled;
--                       false/no/0 or missing -> disabled). When disabled,
--                       the block's entire body is rendered verbatim as a
--                       plain code block (no execution, no region trimming,
--                       no docs:begin/end processing). Cross-block
--                       replace= sites that reference a disabled key
--                       render as empty. ensure_defined errors if an
--                       enabled block depends on a disabled one.
--
--   replace=<value>     Required on every annotated block. See taxonomy below.
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
--   K/path              Cross-block: absolute path of cache/<K>/ directory.
--   K/<thing>           Cross-block: render K's thing.
--                       thing is stdout|stderr|both|source[/<region>]|<artifact>.
--   K/<thing>/path      Cross-block: absolute path of cache/<K>/<thing>.
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
-- DEFAULT-REPLACE METADATA
--
--   Pass -M default-replace=true (or false) on the pandoc command line.
--   replace.lua reads doc.meta["default-replace"] in Pandoc() and uses it
--   as the default for blocks without an explicit enabled= attribute.
--   true/yes/1 -> enabled; false/no/0 (or absent) -> disabled.
--
-- MAKE-FRAGMENT SHAPE (dry-run)
--
--   Primary target:  cache/<key>/stdout
--     prereqs: runner, body.<ext>, [subst.lua, spec] (iff contents-form subst=
--              exists), depends= stdouts, subst= file prereqs
--   Sibling targets: cache/<key>/stderr, cache/<key>/both, each declared artifact.
--   Siblings depend on the primary with an empty recipe (portable to GNU Make
--   3.81, which predates `&:` grouped-target syntax).
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
--   - subst= path-form rewrites happen at dry-run time (before execution).
--     Contents-form $VAR stays literal in body.<ext>; subst.lua expands it
--     at runner time. Editing subst.lua or the spec file triggers a rebuild.
--   - $VAR substitution requires a non-word boundary after VAR so $foo does
--     not consume the start of $foobar; longest var wins for disambiguation.

local deps_file
local default_enabled = true  -- overridden in Pandoc() from -M default-replace=
local REPLACE_CACHE_DIR = os.getenv("REPLACE_CACHE_DIR") or error("REPLACE_CACHE_DIR not set")

-- Locate the directory containing this filter file; runners live alongside it.
local REPLACE_DIR = PANDOC_SCRIPT_FILE:match("(.+)/[^/]+$") or "."
local subst = require "subst"

local LANG_INFO = {
    bash = { ext = "sh",  runner = REPLACE_DIR .. "/run-bash.sh" },
    lua  = { ext = "lua", runner = REPLACE_DIR .. "/run-lua.sh"  },
}
local DEFAULT_LANG = "bash"

local RESERVED = { stdout = true, stderr = true, both = true, source = true, null = true }

-- State accumulated as the document is walked.
local pending   = {}  -- key -> { attr, body, classes, deps, subst }  (pass 1: raw collection)
local defining  = {}  -- key -> true  (cycle detection during ensure_defined)
local defined   = {}  -- key -> true  (set after define_script completes)
local outputs_t = {}  -- key -> { artifact_name -> true }
local sources   = {}  -- key -> resolved body (for replace=source)
local rules     = {}  -- list of make rule strings (dry-run only)
local consumed  = {}  -- "<key>/<file>" -> true (referenced cache files)

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

local function is_enabled(attr)
    local v = attr.enabled
    if v == nil then return default_enabled end
    return v == "yes" or v == "true" or v == "1"
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
        assertf(not tok:find("/"),
            "depends=%s: depends= takes bare keys only; use subst=VAR->%s/<sub> for substitution", tok, tok)
        check_identifier(tok, "depends=" .. tok)
        r[#r + 1] = {base = tok}
    end
    return r
end

local function parse_subst(s)
    local r = {}
    if not s then return r end
    for var, ref in s:gmatch("([%w_]+)%->([%w._%-/]+)") do
        local base, sub, kind
        -- Try K/SUB/path
        base, sub = ref:match("^([%w_][%w_%-%.]*)/(.+)/path$")
        if base then
            assertf(not sub:match("^source/"),
                "subst=%s->%s: K/source/REGION/path is not allowed", var, ref)
            kind = "path"
        else
            -- Try K/SUB
            base, sub = ref:match("^([%w_][%w_%-%.]*)/(.+)$")
            if base then
                kind = "contents"
            else
                base, sub = ref, nil
                kind = "dirpath"
            end
        end
        check_identifier(base, "subst=" .. var .. "->" .. ref)
        r[#r + 1] = {var = var, base = base, sub = sub, kind = kind, raw = ref}
    end
    return r
end

-- Substitute $VAR in body with abs_path for each {var, abs_path} pair.
-- Longest var wins; match requires a non-word character (or end) after the var
-- so $foo does not consume the start of $foobar.
local function substitute(body, var_pairs)
    local sorted_pairs = {}
    for _, p in ipairs(var_pairs) do sorted_pairs[#sorted_pairs + 1] = p end
    table.sort(sorted_pairs, function(a, b) return #a.var > #b.var end)
    local out, i, n = {}, 1, #body
    while i <= n do
        local c = body:sub(i, i)
        if c == "$" then
            local matched = false
            for _, p in ipairs(sorted_pairs) do
                local len = #p.var
                if body:sub(i + 1, i + len) == p.var then
                    local nextc = body:sub(i + 1 + len, i + 1 + len)
                    if nextc == "" or not nextc:match("[%w._%-]") then
                        out[#out + 1] = p.abs_path
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

local function read_output(key, sub, label)
    consumed[key .. "/" .. sub] = true
    if deps_file then return "" end
    local path = REPLACE_CACHE_DIR .. "/" .. key .. "/" .. sub
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

local function write_idempotent(path, content)
    local f = io.open(path, "r")
    if f then
        local existing = f:read("a")
        f:close()
        if existing == content then return end
    end
    os.execute("mkdir -p '" .. path:match("(.*)/") .. "'")
    f = assert(io.open(path, "w"))
    f:write(content)
    f:close()
end

local function define_script(key, attr, body, classes, deps, subst)
    assertf(not defined[key], "key=%s: duplicate definition", key)
    local out_list = parse_list(attr.outputs)
    for _, n in ipairs(out_list) do
        assertf(not RESERVED[n], "key=%s: outputs= cannot contain reserved name '%s'", key, n)
    end
    for _, d in ipairs(deps) do
        assertf(defined[d.base], "key=%s: depends=%s: '%s' not yet defined", key, d.base, d.base)
    end
    -- Build path_pairs from path-form subst entries (kind == "dirpath" or "path").
    -- Contents-form entries stay literal in the body; the runner will expand them at run time.
    local path_pairs = {}
    for _, p in ipairs(subst) do
        if p.kind == "dirpath" then
            assertf(defined[p.base], "key=%s: subst=%s->%s: '%s' not yet defined", key, p.var, p.raw, p.base)
            path_pairs[#path_pairs + 1] = { var = p.var, abs_path = REPLACE_CACHE_DIR .. "/" .. p.base }
        elseif p.kind == "path" then
            assertf(defined[p.base], "key=%s: subst=%s->%s: '%s' not yet defined", key, p.var, p.raw, p.base)
            path_pairs[#path_pairs + 1] = { var = p.var, abs_path = REPLACE_CACHE_DIR .. "/" .. p.base .. "/" .. p.sub }
        end
    end
    local resolved = substitute(body, path_pairs)
    resolved = resolved:gsub("%$REPLACE_KEY%f[%W]", function() return key end)
    local lang = lang_from_classes(classes)
    local info = LANG_INFO[lang]
    defined[key] = true
    outputs_t[key] = {}
    for _, n in ipairs(out_list) do outputs_t[key][n] = true end
    sources[key] = resolved
    write_idempotent(REPLACE_CACHE_DIR .. "/" .. key .. "/body." .. info.ext, resolved)
    -- Write spec file for contents-form subst entries so the runner can expand them.
    local contents_entries = {}
    for _, p in ipairs(subst) do
        if p.kind == "contents" then
            contents_entries[#contents_entries + 1] = p
        end
    end
    if #contents_entries > 0 then
        table.sort(contents_entries, function(a, b) return a.var < b.var end)
        local lines = {}
        for _, p in ipairs(contents_entries) do
            lines[#lines + 1] = p.var .. "=" .. REPLACE_CACHE_DIR .. "/" .. p.base .. "/" .. p.sub
        end
        write_idempotent(REPLACE_CACHE_DIR .. "/" .. key .. "/spec", table.concat(lines, "\n") .. "\n")
    end
    if deps_file then emit_rule(key, info, out_list, deps, subst, #contents_entries > 0) end
    return resolved
end

-- Emit a make rule. stdout is the primary target; stderr, both, and any
-- declared artifacts are sibling targets that depend on the primary.
-- (GNU Make 3.81 predates `&:` grouped-target syntax.)
function emit_rule(key, info, out_list, deps, subst, has_contents)
    local runner_path = info.runner
    local body_path = "$(REPLACE_CACHE_DIR)/" .. key .. "/body." .. info.ext
    local prereqs = {runner_path, body_path}
    if has_contents then
        prereqs[#prereqs + 1] = REPLACE_DIR .. "/subst.lua"
        prereqs[#prereqs + 1] = "$(REPLACE_CACHE_DIR)/" .. key .. "/spec"
    end
    -- Collect prereqs from depends= and subst=, deduplicating by path.
    local seen_prereqs = {}
    local function add_prereq(path)
        if not seen_prereqs[path] then
            seen_prereqs[path] = true
            prereqs[#prereqs + 1] = path
        end
    end
    for _, d in ipairs(deps) do
        add_prereq("$(REPLACE_CACHE_DIR)/" .. d.base .. "/stdout")
    end
    for _, p in ipairs(subst) do
        if p.kind == "dirpath" then
            add_prereq("$(REPLACE_CACHE_DIR)/" .. p.base .. "/stdout")
        elseif p.kind == "path" or p.kind == "contents" then
            add_prereq("$(REPLACE_CACHE_DIR)/" .. p.base .. "/" .. p.sub)
        end
    end
    local primary = "$(REPLACE_CACHE_DIR)/" .. key .. "/stdout"
    local siblings = {"stderr", "both"}
    for _, n in ipairs(out_list) do siblings[#siblings + 1] = n end
    local cmd = string.format("\t@REPLACE_KEY=%s bash %s", key, runner_path)
    rules[#rules + 1] = primary .. ": " .. table.concat(prereqs, " ") .. "\n" .. cmd
    for _, s in ipairs(siblings) do
        rules[#rules + 1] = "$(REPLACE_CACHE_DIR)/" .. key .. "/" .. s .. ": " .. primary
    end
end

-- Lazily define key and all its transitive depends= in DFS order.
local function ensure_defined(key)
    if defined[key] then return end
    assertf(not defining[key], "key=%s: dependency cycle", key)
    local p = pending[key]
    assertf(p, "key=%s: not defined", key)
    defining[key] = true
    for _, d in ipairs(p.deps) do
        ensure_defined(d.base)
    end
    for _, s in ipairs(p.subst) do
        if s.kind ~= "contents" then
            ensure_defined(s.base)
        end
    end
    define_script(key, p.attr, p.body, p.classes, p.deps, p.subst)
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
    assertf(defined[K], "%s: key '%s' not defined", label, K)
    if thing == "path" then
        return REPLACE_CACHE_DIR .. "/" .. K
    end
    local sub_path = thing:match("^(.+)/path$")
    if sub_path then
        return REPLACE_CACHE_DIR .. "/" .. K .. "/" .. sub_path
    end
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
        return read_output(K, thing, label)
    end
    assertf(outputs_t[K] and outputs_t[K][thing],
        "%s: key '%s' has no artifact '%s'", label, K, thing)
    return read_output(K, thing, label)
end

render_source = function(text, region, subst_spec, label)
    text = strip_null_regions(text, label)
    if region or text:find("[#%-/]+%s*docs:begin") then
        text = extract_region(text, region, label)
    end
    local pairs_list = {}
    for _, p in ipairs(subst_spec or {}) do
        if p.kind == "contents" then
            ensure_defined(p.base)
            local val
            if p.sub == "source" then
                val = render_source(sources[p.base], nil, nil, label .. ": subst=" .. p.var)
            elseif p.sub:sub(1, 7) == "source/" then
                local r = p.sub:sub(8)
                val = render_source(sources[p.base], r, nil, label .. ": subst=" .. p.var)
            else
                val = read_output(p.base, p.sub, label .. ": subst=" .. p.var .. "->" .. p.raw)
            end
            pairs_list[#pairs_list + 1] = { var = p.var, value = val }
        end
    end
    return subst.apply(text, pairs_list)
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

    local enabled = is_enabled(attr)
    if enabled then
        if key then ensure_defined(key) end
        assertf(replace, "%s: replace= attribute required", key and "key=" .. key or "CodeBlock")
    end

    local subst_spec = parse_subst(attr.subst)
    attr.key = nil
    attr.ref = nil
    attr.depends = nil
    attr.outputs = nil
    attr.replace = nil
    attr.block = nil
    attr.subst = nil
    attr.enabled = nil

    if not enabled then
        force_fenced(el)
        return el
    end

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
        el.text = read_output(key, a, label)
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
    local enabled = is_enabled(attr)
    attr.replace = nil
    attr.enabled = nil
    if not enabled then return el end
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
    local enabled = is_enabled(attr)
    attr.replace = nil
    attr.enabled = nil
    if not enabled then return el end
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
        f:write(" $(REPLACE_CACHE_DIR)/" .. c)
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
    if not is_enabled(b.attr.attributes) then return end
    check_identifier(key, "key=" .. key)
    assertf(not pending[key], "key=%s: duplicate definition", key)
    pending[key] = {
        attr    = b.attr.attributes,
        body    = b.text,
        classes = b.classes,
        deps    = parse_depends(b.attr.attributes.depends),
        subst   = parse_subst(b.attr.attributes.subst),
    }
end

local function collect(blocks)
    pandoc.walk_block(pandoc.Div(blocks), {CodeBlock = collect_codeblock})
end

function Pandoc(doc)
    local m = doc.meta["write-user-dependencies"]
    deps_file = m and pandoc.utils.stringify(m) or nil
    local dr = doc.meta["default-replace"]
    if dr ~= nil then
        local v = pandoc.utils.stringify(dr)
        default_enabled = v == "true" or v == "yes" or v == "1"
    end
    collect(doc.blocks)
    doc.blocks = walk_blocks(doc.blocks)
    if deps_file then emit_deps() end
    return doc
end

return {{Pandoc = Pandoc}}
