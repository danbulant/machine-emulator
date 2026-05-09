-- Load the Cartesi module
local cartesi = require("cartesi")

-- Instantiate machine from configuration
local calculator_config = require("config-calculator")
local machine = cartesi.machine(calculator_config)

-- Write expression to input NVRAM
local input_nvram = calculator_config.nvram[1]
machine:write_memory(input_nvram.start, table.concat(arg, " ") .. "\n")

-- Run machine until it halts or yields manual
repeat
    local break_reason = machine:run(math.maxinteger)
until break_reason == cartesi.BREAK_REASON_HALTED or break_reason == cartesi.BREAK_REASON_YIELDED_MANUALLY

-- Read result from output NVRAM
local output_nvram = calculator_config.nvram[2]
print((string.unpack("z", machine:read_memory(output_nvram.start, output_nvram.length))))
