-- Pandoc Lua filter: substitute generated content into code blocks/spans.
-- Two attributes are supported:
--   cache=FILE  -> body is replaced with the contents of $CACHE_DIR/FILE
--   pipe=sh     -> body is executed as a bash script and replaced with stdout
-- One trailing newline is stripped from the substituted text.
-- For inline Span [content]{cache=FILE}, the bracket content is treated as a
-- literal suffix appended to the cache value, and the whole thing is rendered
-- as monospace Code (so e.g. [...]{cache=hash.out} -> `value...`).
-- For inline Code `body`{pipe=sh|cache=FILE}, the Code wrapper is preserved.
-- After substitution the matching attribute is removed; other attributes are
-- kept. Any non-zero exit (pipe=sh) aborts the build with a visible error.

local function read_cache(filename)
    local cache_dir = os.getenv("CACHE_DIR") or error("CACHE_DIR not set")
    local path = cache_dir .. "/" .. filename
    local f = assert(io.open(path, "r"), "cache=" .. filename .. ": cannot open " .. path)
    local txt = f:read("a")
    f:close()
    return (txt:gsub("\n$", ""))
end

local function run_sh(cmd)
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
    if #el.classes == 0 and not next(el.attr.attributes) and el.identifier == "" then
        el.classes = {"text"}
    end
end

function CodeBlock(el)
    local cache = el.attr.attributes.cache
    if cache then
        el.attr.attributes.cache = nil
        el.text = read_cache(cache)
        force_fenced(el)
        return el
    end
    if el.attr.attributes.pipe == "sh" then
        el.attr.attributes.pipe = nil
        el.text = run_sh(el.text)
        force_fenced(el)
        return el
    end
end

function Code(el)
    local cache = el.attr.attributes.cache
    if cache then
        el.text = read_cache(cache)
        el.attr.attributes.cache = nil
        return el
    end
    if el.attr.attributes.pipe == "sh" then
        el.text = run_sh(el.text)
        el.attr.attributes.pipe = nil
        return el
    end
end

function Span(el)
    local cache = el.attr.attributes.cache
    if cache then
        local suffix = pandoc.utils.stringify(el.content)
        return pandoc.Code(read_cache(cache) .. suffix)
    end
end
