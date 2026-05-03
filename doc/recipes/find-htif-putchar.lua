local cartesi = require"cartesi"

local config = require"config.nothing-to-do"
local machine = cartesi.machine(config)

local mcycle = machine:read_reg("mcycle")
local tohost = machine:read_reg("htif_tohost")
local line = 0
while machine:read_reg("iflags_H") == 0 and machine:read_reg("iflags_Y") == 0 do
    machine:run(mcycle+1)
    local newtohost = machine:read_reg("htif_tohost")
    if tohost ~= newtohost then
        tohost = newtohost
        if tohost & 0xff == 0x0a then
            line = line+1
            if line == 8 then
                io.stderr:write(mcycle)
                break
            end
        end
    end
    mcycle = machine:read_reg("mcycle")
    if mcycle % 10^5  == 0 then
        collectgarbage("collect")
    end
end
