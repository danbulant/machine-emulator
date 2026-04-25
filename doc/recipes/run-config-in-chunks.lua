-- Load the Cartesi module
local cartesi = require"cartesi"

-- Instantiate machine from configuration
local config = require(arg[1])
local machine = cartesi.machine(config)

local CHUNK = 1000000 -- 1 million cycles
-- Loop until machine halts or yields
while not machine:read_iflags_H() and not machine:read_iflags_Y() do
    -- Execute at most CHUNK cycles
    machine:run(machine:read_mcycle() + CHUNK)
    -- Potentially perform other tasks
end
-- Machine is now halted or yielded
