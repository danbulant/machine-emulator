-- Load the Cartesi module
local cartesi = require("cartesi")
local util = require("cartesi.util")
local proof = require("proof")

-- Instantiate machine from configuration
local config = require("config-calculator")
local machine = cartesi.machine(config)

-- Write expression to input NVRAM
local input_nvram = config.nvram[1]
machine:write_memory(input_nvram.start, table.concat(arg, " ") .. "\n")

-- Run machine until it halts or yields manual
repeat
    local break_reason = machine:run(math.maxinteger)
until break_reason == cartesi.BREAK_REASON_HALTED or break_reason == cartesi.BREAK_REASON_YIELDED_MANUALLY

-- Obtain value proof for output NVRAM
local output_state_hash = machine:get_root_hash()
local output_nvram = config.nvram[2]
local log2_target_size = util.ilog2(output_nvram.length)
local output_proof = machine:get_proof(output_nvram.start, log2_target_size)

-- Verify proof
proof.slice_assert(output_proof)
print("\nOutput NVRAM proof accepted!\n")

print((string.unpack("z", machine:read_memory(output_nvram.start, output_nvram.length))))
