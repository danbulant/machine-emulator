-- Load the Cartesi module
local cartesi = require"cartesi"

-- Instantiate machine from configuration
local config = require(arg[1])
local machine = cartesi.machine(config)

-- Run machine until it halts or yields
while not machine:read_iflags_H() and not machine:read_iflags_Y() do
    machine:run(math.maxinteger)
end
