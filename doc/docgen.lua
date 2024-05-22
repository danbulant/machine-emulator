-- Pandoc Lua filter: execute shell commands in {pipe=sh} code blocks and spans.
-- Block body or inline span text is replaced with the command's stdout.
-- Any non-zero exit aborts the build with a visible error message.
-- After substitution the pipe attribute is removed; other attributes are kept.

local function run_sh(cmd)
    -- Write command to a tempfile and invoke bash on it. Avoids all shell-quoting
    -- issues from passing cmd through the outer /bin/sh that os.execute uses.
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

function CodeBlock(el)
    if el.attr.attributes.pipe ~= "sh" then return nil end
    el.text = run_sh(el.text)
    el.attr.attributes.pipe = nil
    return el
end

function Code(el)
    if el.attr.attributes.pipe ~= "sh" then return nil end
    return pandoc.Str(run_sh(el.text))
end
