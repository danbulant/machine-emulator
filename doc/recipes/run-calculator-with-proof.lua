-- Load the Cartesi module
local cartesi = require("cartesi")
local util = require("cartesi.util")
local hash_tree = require("hash-tree")

-- Instantiate machine from configuration
local config = require("config-calculator")
local machine = cartesi.machine(config)

-- Write expression to input NVRAM
local input_nvram = assert(util.find_drive(config, "nvram", "input"))
machine:write_memory(input_nvram.start, table.concat(arg, " ") .. "\n")

-- Run machine until it halts or yields manual
repeat
    local break_reason = machine:run(math.maxinteger)
until break_reason == cartesi.BREAK_REASON_HALTED or break_reason == cartesi.BREAK_REASON_YIELDED_MANUALLY

-- Obtain value proof for output NVRAM
local output_state_hash = machine:get_root_hash()
local output_nvram = assert(util.find_drive(config, "nvram", "output"))
local output_proof = machine:get_proof(output_nvram.start, output_nvram.log2_size)

-- Verify proof
hash_tree.verify_slice(output_proof)
print("\nOutput NVRAM proof accepted!\n")

print((string.unpack("z", machine:read_memory(output_nvram.start, output_nvram.length))))
