local cartesi = require("cartesi")

-- Tree leaves are words, the smallest proof target.
local WORD_LOG2_SIZE = cartesi.HASH_TREE_LOG2_WORD_SIZE
local WORD_LENGTH = 1 << WORD_LOG2_SIZE

-- docs:begin roll_hash_up_tree
local function roll_hash_up_tree(proof, target_hash)
    local hash = target_hash
    for log2_size = proof.log2_target_size, cartesi.HASH_TREE_LOG2_ROOT_SIZE - 1 do
        local sibling = assert(proof.sibling_hashes[log2_size - proof.log2_target_size + 1], "too few siblings")
        local bit = (proof.target_address & (1 << log2_size)) ~= 0
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

-- docs:begin verify_slice
local function verify_slice(proof)
    assert(roll_hash_up_tree(proof, proof.target_hash) == proof.root_hash, "node not in tree")
end
-- docs:end verify_slice

-- docs:begin verify_splice
local function verify_splice(proof, new_target_hash, new_root_hash)
    verify_slice(proof)
    assert(roll_hash_up_tree(proof, new_target_hash) == new_root_hash, "new node not in tree")
end
-- docs:end verify_splice

-- Computes the Merkle tree root of a byte string laid at the base of a tree covering
-- 2^log2_root_size bytes. The data need not fill the tree or be a power of two long. Leaves
-- are word-size keccak256 hashes, a trailing partial word zero-padded, and inner nodes hash
-- their two children. Every node the data does not reach takes its level's pristine hash, the
-- root of an all-zero subtree, which doubles each level climbed. Overflow is rejected.
-- docs:begin get_root_hash
local function get_root_hash(data, log2_root_size)
	assert(#data <= (1 << log2_root_size), "data does not fit in the tree")
	-- Level zero is one hash per word, a trailing partial word zero-padded after the loop.
	local level = {}
	local full = #data - #data % WORD_LENGTH
	for i = 1, full, WORD_LENGTH do
		level[#level + 1] = cartesi.keccak256(data:sub(i, i + WORD_LENGTH - 1))
	end
	if full < #data then
		local word = data:sub(full + 1)
		level[#level + 1] = cartesi.keccak256(word .. string.rep("\0", WORD_LENGTH - #word))
	end
	-- Pair upward to the root, the pristine hash standing in for every node the data misses.
	local pristine = cartesi.keccak256(string.rep("\0", WORD_LENGTH))
	for _ = WORD_LOG2_SIZE, log2_root_size - 1 do
		local parents = {}
		for i = 1, #level, 2 do
			parents[#parents + 1] = cartesi.keccak256(level[i], level[i + 1] or pristine)
		end
		level, pristine = parents, cartesi.keccak256(pristine, pristine)
	end
	return level[1]
end
-- docs:end get_root_hash

return {
    roll_hash_up_tree = roll_hash_up_tree,
    verify_slice = verify_slice,
    verify_splice = verify_splice,
    get_root_hash = get_root_hash
}
