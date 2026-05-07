local cartesi = require"cartesi"

local config = require"config.nothing-to-do"
local runtime = { console = { output_destination = "to_buffer", output_flush_mode = "every_line" } }
local machine = cartesi.machine(config, runtime)

local line = 0
while machine:run() == cartesi.BREAK_REASON_CONSOLE_OUTPUT do
    machine:read_console_output()
    line = line + 1
    if line == 8 then
        io.stderr:write(machine:read_reg("mcycle") - 1)
        break
    end
end
