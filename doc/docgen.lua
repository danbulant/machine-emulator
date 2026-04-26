-- Pandoc Lua filter: substitute generated content into code blocks/spans.
-- Four attributes are supported:
--   output=KEY              -> body is replaced with the contents of
--                              $CACHE_DIR/KEY.out (the output captured by
--                              recipes/cache.KEY.sh).
--   pipe=sh                 -> body is executed as a bash script and replaced
--                              with stdout
--   script=KEY [name=N]     -> body is replaced with the # docs:begin[/end]
--                              region named N (or the unnamed region when
--                              name= is omitted) from $RECIPES_DIR/cache.KEY.sh,
--                              with the trailing "> "$out" 2>&1" redirect
--                              stripped automatically.
--   subst=VAR1->KEY1,...    -> companion to script=. After region extraction,
--                              each $VAR occurrence is replaced with the
--                              contents of $CACHE_DIR/KEY.out (surrounding
--                              context, including quotes, is preserved).
-- One trailing newline is stripped from the substituted text.
-- For inline Span [content]{output=KEY}, the bracket content is treated as a
-- literal suffix appended to the output value, and the whole thing is rendered
-- as monospace Code (so e.g. [...]{output=hash} -> `value...`).
-- For inline Code `body`{pipe=sh|output=KEY}, the Code wrapper is preserved.
-- After substitution the matching attribute is removed; other attributes are
-- kept. Any non-zero exit (pipe=sh) aborts the build with a visible error.
--
-- Deps mode: when DEPS_FILE is set, the filter instead discovers which cache
-- files and recipe scripts the template references and writes a makefile fragment:
--   all: /abs/path/foo.out /abs/path/bar.sh ...
-- In deps mode no cache files are read and no pipe=sh commands are executed.

local DEPS_FILE    = os.getenv("DEPS_FILE")
local RECIPES_DIR  = os.getenv("RECIPES_DIR")
local needed         = {}   -- cache file basenames -> true
local needed_scripts = {}   -- absolute script paths -> true

local function record(filename)
    needed[filename] = true
end

local function assertf(cond, fmt, ...)
    if not cond then
        error(string.format(fmt, ...))
    end
end

local function strip_ansi(txt)
    return (txt:gsub("\27%[[%d;]*[mGK]", ""):gsub("\r", ""))
end

local function read_output(key)
    local filename = key .. ".out"
    record(filename)
    if DEPS_FILE then return "" end
    local cache_dir = os.getenv("CACHE_DIR") or error("CACHE_DIR not set")
    local path = cache_dir .. "/" .. filename
    local f = assert(io.open(path, "r"), "output=" .. key .. ": cannot open " .. path)
    local txt = f:read("a")
    f:close()
    return (strip_ansi(txt):gsub("\n$", ""))
end

local function read_script(key, name, subst)
    local recipes_dir = RECIPES_DIR or error("RECIPES_DIR not set")
    local path = recipes_dir .. "/cache." .. key .. ".sh"
    needed_scripts[path] = true
    -- record subst dependencies (also in deps mode)
    local subst_pairs = {}
    if subst then
        for var, skey in subst:gmatch("([%w_]+)%->([%w._%-]+)") do
            subst_pairs[#subst_pairs + 1] = {var = var, value = read_output(skey)}
        end
    end
    if DEPS_FILE then return "" end
    local f = assert(io.open(path, "r"), "script=" .. key .. ": cannot open " .. path)
    local src = f:read("a")
    f:close()

    -- single pass: collect {s=pos_of_#, kw="begin"|"end", name=str, e=pos_of_\n}
    local markers = {}
    src:gsub("()# docs:(%a+)[ \t]*(.-)[ \t]*()\n", function(s, kw, rname, e)
        markers[#markers + 1] = {s = s, kw = kw, name = rname, e = e}
    end)

    -- collect per-region {first, last} positions in the source string
    local regions = {}
    for _, m in ipairs(markers) do
        regions[m.name] = regions[m.name] or {}
        local r = regions[m.name]
        if m.kw == "begin" then
            assertf(not r.first, "script=%s: duplicate docs:begin '%s'", key, m.name)
            r.first = m.e + 1
        elseif m.kw == "end" then
            assertf(not r.last, "script=%s: duplicate docs:end '%s'", key, m.name)
            r.last = m.s - 1
        end
    end

    -- validate and extract requested region
    local target = name or ""
    local r = regions[target]
    assertf(r,                 "script=%s: no region '%s' found",                   key, target)
    assertf(r.first,           "script=%s: region '%s' has no docs:begin",          key, target)
    assertf(r.last,            "script=%s: region '%s' has no docs:end",            key, target)
    assertf(r.first <= r.last, "script=%s: region '%s' docs:end before docs:begin", key, target)

    local text = src:sub(r.first, r.last):gsub("\n$", "")
    text = text:gsub('%s*\\?%s*>%s*"%$out[%w_]*".*$', '')
    for _, p in ipairs(subst_pairs) do
        text = text:gsub('%$' .. p.var .. '%f[%W]', function() return p.value end)
    end
    return text
end

local function run_sh(cmd)
    for filename in cmd:gmatch("%$CACHE_DIR/([%w._%-]+%.out)") do
        record(filename)
    end
    if DEPS_FILE then return "" end
    local script = os.tmpname()
    local out    = os.tmpname()
    local f = assert(io.open(script, "w"))
    f:write(cmd)
    f:close()
    local ok, _, code = os.execute("bash " .. script .. " >" .. out .. " 2>&1")
    os.remove(script)
    local g = assert(io.open(out, "r"))
    local txt = g:read("a")
    g:close()
    os.remove(out)
    if not ok or (code or 0) ~= 0 then
        error("pipe=sh command failed:\n$ " .. cmd .. "\n" .. txt)
    end
    return (txt:gsub("\n$", ""))
end

-- Pandoc gfm writer renders an unattributed CodeBlock as 4-space-indented.
-- Force fenced output by giving classless substitutions a synthetic class.
local function force_fenced(el)
    local has_attrs = false
    for _ in pairs(el.attr.attributes) do has_attrs = true; break end
    if #el.classes == 0 and not has_attrs and el.identifier == "" then
        el.classes = {"text"}
    end
end

function CodeBlock(el)
    local output = el.attr.attributes.output
    if output then
        el.attr.attributes.output = nil
        el.text = read_output(output)
        force_fenced(el)
        return el
    end
    if el.attr.attributes.pipe == "sh" then
        el.attr.attributes.pipe = nil
        el.text = run_sh(el.text)
        force_fenced(el)
        return el
    end
    local script = el.attr.attributes.script
    if script then
        local name = el.attr.attributes.name
        local subst = el.attr.attributes.subst
        el.attr.attributes.script = nil
        el.attr.attributes.name = nil
        el.attr.attributes.subst = nil
        el.text = read_script(script, name, subst)
        force_fenced(el)
        return el
    end
end

function Code(el)
    local output = el.attr.attributes.output
    if output then
        el.text = read_output(output)
        el.attr.attributes.output = nil
        return el
    end
    if el.attr.attributes.pipe == "sh" then
        el.text = run_sh(el.text)
        el.attr.attributes.pipe = nil
        return el
    end
end

function Span(el)
    local output = el.attr.attributes.output
    if output then
        local suffix = pandoc.utils.stringify(el.content)
        return pandoc.Code(read_output(output) .. suffix)
    end
end

function Pandoc(doc)
    if DEPS_FILE then
        local cache_dir = os.getenv("CACHE_DIR") or error("CACHE_DIR not set")
        local files = {}
        for name in pairs(needed) do
            files[#files + 1] = cache_dir .. "/" .. name
        end
        for path in pairs(needed_scripts) do
            files[#files + 1] = path
        end
        table.sort(files)
        local f = assert(io.open(DEPS_FILE, "w"))
        f:write("all:")
        for _, p in ipairs(files) do
            f:write(" " .. p)
        end
        f:write("\n")
        f:close()
    end
    return doc
end
