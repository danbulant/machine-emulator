-- Load the Cartesi module
local cartesi = require("cartesi")

-- Roll a target hash up the Merkle tree using its sibling hashes
local function roll_hash_up_tree(address, log2_target_size, sibling_hashes, target_hash)
    local hash = target_hash
    for log2_size = log2_target_size, cartesi.HASH_TREE_LOG2_ROOT_SIZE - 1 do
        local sibling = sibling_hashes[log2_size - log2_target_size + 1]
        local bit = (address & (1 << log2_size)) ~= 0
        local first, second
        if bit then
            first, second = sibling, hash
        else
            first, second = hash, sibling
        end
        hash = cartesi.keccak256(first, second)
    end
    return hash
end

-- Verify a state value proof against a known root hash
local function slice_assert(root_hash, address, log2_target_size, proof)
    assert(root_hash == proof.root_hash, "proof root_hash mismatch")
    assert(
        roll_hash_up_tree(address, log2_target_size, proof.sibling_hashes, proof.target_hash) == root_hash,
        "node not in tree"
    )
end

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
local log2_target_size = 12 -- 4 KiB output NVRAM
local output_proof = machine:get_proof(output_nvram.start, log2_target_size)

-- Verify proof
slice_assert(output_state_hash, output_nvram.start, log2_target_size, output_proof)
print("\nOutput NVRAM proof accepted!\n")

print((string.unpack("z", machine:read_memory(output_nvram.start, output_nvram.length))))
