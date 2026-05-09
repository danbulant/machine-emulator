-- Load the Cartesi module
local cartesi = require("cartesi")

-- Instantiate machine from configuration
local config = require(arg[1])
local machine = cartesi.machine(config)

local CHUNK = 1000000 -- 1 million cycles
-- Loop until machine halts or yields manual
repeat
    -- Execute at most CHUNK additional cycles, then potentially perform other tasks
    local break_reason = machine:run(machine:read_reg("mcycle") + CHUNK)
until break_reason == cartesi.BREAK_REASON_HALTED or break_reason == cartesi.BREAK_REASON_YIELDED_MANUALLY
