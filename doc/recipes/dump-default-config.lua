-- Load the Cartesi module and utilities
local cartesi = require"cartesi"
local util = require"cartesi.util"

-- Obtain default config
local default_config = cartesi.machine:get_default_config()

-- Pretty-print it
io.write("return ")
util.dump_table(default_config, io.stdout)
