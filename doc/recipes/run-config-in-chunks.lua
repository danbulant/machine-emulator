-- Load the Cartesi module
local cartesi = require("cartesi")

-- Writes formatted text to stderr
local function stderr(fmt, ...)
    io.stderr:write(string.format(fmt, ...))
end

-- Instantiate machine from configuration
local config = require(arg[1])
local machine = cartesi.machine(config)

local CHUNK = 1000000 -- 1 million cycles
-- Loop until machine halts or yields manual
local chunks = 0
repeat
    -- Execute at most CHUNK additional cycles, then potentially perform other tasks
    local break_reason = machine:run(machine:read_reg("mcycle") + CHUNK)
    chunks = chunks + 1
until break_reason == cartesi.BREAK_REASON_HALTED or break_reason == cartesi.BREAK_REASON_YIELDED_MANUALLY

-- Print the number of chunks
stderr("%u chunks\n", chunks)
