local M = {}

function M.apply(body, pairs)
    for _, p in ipairs(pairs) do
        body = body:gsub("%$" .. p.var .. "%f[%W]", function()
            return p.value
        end)
    end
    return body
end

function M.read_value(path)
    local f = assert(io.open(path, "r"), "vars: cannot open " .. path)
    local s = f:read("a")
    f:close()
    s = s:gsub("\27%[[%d;]*[mGK]", ""):gsub("\r", "")
    return (s:gsub("\n$", ""))
end

local function cli(body_in, body_out)
    local pairs_list = {}
    local sf = assert(io.open("spec", "r"), "vars CLI: ./spec not found")
    for line in sf:lines() do
        local var, path = line:match("^([%w_]+)=(.+)$")
        assert(var, "vars CLI: bad spec line: " .. line)
        pairs_list[#pairs_list + 1] = { var = var, value = M.read_value(path) }
    end
    sf:close()
    local bf = assert(io.open(body_in, "r"))
    local body = bf:read("a")
    bf:close()
    body = M.apply(body, pairs_list)
    local of = assert(io.open(body_out, "w"))
    of:write(body)
    of:close()
end

if arg and arg[0] and arg[0]:match("vars%.lua$") and arg[1] then
    cli(arg[1], arg[2])
end

return M
