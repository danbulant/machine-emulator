-- Load the Cartesi module
local cartesi = require("cartesi")

-- Instantiate machine from configuration
local machine = cartesi.machine((require("config.cat-foo-bar")))

-- Store persistent state to directory
machine:store("cat-foo-bar")
