-- Load the Cartesi module
local cartesi = require("cartesi")

-- Writes formatted text to stderr
local function stderr(fmt, ...) io.stderr:write(string.format(fmt, ...)) end

-- Instantiate machine from configuration
local config = require(arg[1])
local machine = cartesi.machine(config)

local CHUNK = 1000000 -- 1 million cycles
local max_mcycle = CHUNK
-- Loop until machine halts or yields manual
repeat
    -- Execute up to max_mcycle
    local break_reason = machine:run(max_mcycle)
    -- Check if machine yielded automatic with a progress report
    if
        break_reason == cartesi.BREAK_REASON_YIELDED_AUTOMATICALLY
        and machine:read_reg("htif_tohost_reason") == cartesi.HTIF_YIELD_AUTOMATIC_REASON_PROGRESS
    then
        local permil = machine:read_reg("htif_tohost_data")
        -- Show progress feedback
        stderr("Progress: %6.2f\r", permil / 10)
    end
    -- Refill the time slice for the next iteration
    if break_reason == cartesi.BREAK_REASON_REACHED_TARGET_MCYCLE then
        max_mcycle = max_mcycle + CHUNK
        -- Potentially perform other tasks
    end
until break_reason == cartesi.BREAK_REASON_HALTED or break_reason == cartesi.BREAK_REASON_YIELDED_MANUALLY
-- Machine is now halted or yielded manual
stderr("\nCycles: %u\n", machine:read_reg("mcycle"))
