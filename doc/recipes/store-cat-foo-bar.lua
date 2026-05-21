-- Load the Cartesi module
local cartesi = require("cartesi")

-- Instantiate machine from configuration
local config = require("config-cat-foo-bar")
local machine = cartesi.machine(config)

-- Store persistent state to directory
machine:store("cat-foo-bar")
