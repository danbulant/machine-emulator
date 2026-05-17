local cartesi = require("cartesi")

-- docs:begin roll_hash_up_tree
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
-- docs:end roll_hash_up_tree

-- docs:begin slice_assert
local function slice_assert(root_hash, address, log2_target_size, proof)
    assert(root_hash == proof.root_hash, "proof root_hash mismatch")
    assert(
        roll_hash_up_tree(address, log2_target_size, proof.sibling_hashes, proof.target_hash) == root_hash,
        "node not in tree"
    )
end
-- docs:end slice_assert

-- docs:begin splice_assert
local function splice_assert(root_hash, address, log2_target_size, proof, new_target_hash, new_root_hash)
    slice_assert(root_hash, address, log2_target_size, proof)
    assert(
        roll_hash_up_tree(address, log2_target_size, proof.sibling_hashes, new_target_hash) == new_root_hash,
        "new node not in tree"
    )
end
-- docs:end splice_assert

return {
    roll_hash_up_tree = roll_hash_up_tree,
    slice_assert = slice_assert,
    splice_assert = splice_assert,
}
