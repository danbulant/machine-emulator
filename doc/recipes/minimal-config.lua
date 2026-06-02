-- Reads a stored Lua machine config from the file given as argument, strips
-- every field equal to the corresponding default value (recursively), removes
-- subtables that become empty, and prints the result to stdout. Mirrors the
-- equality test cartesi-machine.lua uses to annotate "-- default" lines.
-- When the default has no entry for a field (typically a flash drive or NVRAM
-- entry added by the user), an empty string or `false` value on the given
-- config side is treated as default and dropped too.

local cartesi = require("cartesi")

local function prune(t, def)
    if type(t) ~= "table" then
        return t
    end
    for k, v in pairs(t) do
        local d = def and def[k]
        if type(v) == "table" then
            prune(v, type(d) == "table" and d or nil)
            if next(v) == nil then
                t[k] = nil
            end
        elseif v == d or (d == nil and (v == "" or v == false)) then
            t[k] = nil
        end
    end
    return t
end

local function dump(out, what, indent)
    if type(what) ~= "table" then
        if math.type(what) == "integer" then
            out:write(string.format("0x%x", what))
        else
            out:write(string.format("%q", what))
        end
        return
    end
    local keys = {}
    for k in pairs(what) do
        keys[#keys + 1] = k
    end
    if #keys == 0 then
        out:write("{}")
        return
    end
    table.sort(keys, function(a, b)
        if type(a) == type(b) then
            return a < b
        end
        return type(a) == "number"
    end)
    local next_indent = indent .. "  "
    out:write("{\n")
    for _, k in ipairs(keys) do
        out:write(next_indent)
        if type(k) == "string" then
            out:write(k, " = ")
        end
        dump(out, what[k], next_indent)
        out:write(",\n")
    end
    out:write(indent, "}")
end

local config_path = assert(arg[1], "usage: minimal-config.lua <config.lua>")
local config = assert(loadfile(config_path, "t"))()
local default = cartesi.machine:get_default_config()
prune(config, default)
io.write("return ")
dump(io.stdout, config, "")
io.write("\n")
