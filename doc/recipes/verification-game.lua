-- A self-contained model of the Cartesi verification game.
--
-- A referee, standing in for the blockchain, mediates a dispute between two players, told
-- apart only by connection order. Each controls its own Cartesi machine and claims a final
-- state hash for the same computation. One is honest, the other cheats past a chosen point by
-- switching to a machine that ran a different expression.
--
-- All game logic lives in the referee, which never trusts a player. The players are thin and
-- identical, differing only in the machine they hold, the honest one bare and the dishonest
-- one a composite that reports a fake machine past the cheat point. Each runs Lua code the
-- referee sends against its machine and replies. The fork trick lets it answer bisection
-- queries without re-running from scratch.
--
-- Roles, selected by the first argument.
--   verification-game.lua referee   <address> <expr>
--   verification-game.lua honest    <address> <expr>
--   verification-game.lua dishonest <address> <expr> <cheat-mcycle> <cheat-uarch-cycle> <cheat-expr>

local cartesi = require("cartesi")
local cartesi_jsonrpc = require("cartesi.jsonrpc")
local util = require("cartesi.util")
local socket = require("socket")
local proof = require("proof")
local dishonest = require("dishonest")

local TEMPLATE = "calculator-template"

-- Finds a configured drive by its label, filling in its log2_size. Each role locates the input
-- and output NVRAMs in the config of the machine it holds, rather than hardcoding addresses.
local function find_drive(config, what, label)
	for _, drive in ipairs(config[what]) do
		if drive.label == label then
			drive.log2_size = util.ilog2(drive.length)
			return drive
		end
	end
end

-- Tree leaves are words, the smallest proof target.
local WORD_LOG2_SIZE = cartesi.HASH_TREE_LOG2_WORD_SIZE
local WORD_LENGTH = 1 << WORD_LOG2_SIZE

--------------------------------------------------------------------------------
-- Small utilities
--------------------------------------------------------------------------------

-- With VERIFICATION_GAME_TRACE set, every wire message is dumped to stderr, unbuffered so it
-- survives a redirect. The referee runs with it on, the players with it off, so an empty
-- player transcript also confirms a clean run.
io.stderr:setvbuf("no")
local tracing = os.getenv("VERIFICATION_GAME_TRACE") ~= nil
local function trace_wire(player, direction, line)
	if tracing then
		io.stderr:write(string.format("%s player %s: %s\n", direction, player.index or "?", line))
	end
end

-- Computes the Merkle tree root of a byte string laid at the base of a tree covering
-- 2^log2_root_size bytes. The data need not fill the tree or be a power of two long. Leaves
-- are word-size keccak256 hashes, a trailing partial word zero-padded, and inner nodes hash
-- their two children. Every node the data does not reach takes its level's pristine hash, the
-- root of an all-zero subtree, which doubles each level climbed. Overflow is rejected.
local function tree_hash(data, log2_root_size)
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

--------------------------------------------------------------------------------
-- Wire protocol
--
-- Each message is one line, the compact JSON of a Lua value by cartesi.tojson plus a newline.
-- Binary values do not survive plain JSON, so each reply carries a schema, named by the
-- referee, that tags its binary and compound fields. tojson then encodes hashes as Base64 and
-- embeds proofs and access logs as nested objects, and fromjson decodes them back. The schema
-- dictionary below, referencing the built-in Proof and AccessLog, is passed to both.
--------------------------------------------------------------------------------

local SCHEMA_DICT = {
	-- A value at a proof's target and the proof itself, used for the winner's output drive.
	StateValueProof = {
		target_value = "Base64",
		proof = "Proof",
	},
	-- The claimed final state hash a player posts at the start.
	FinalHashCommitment = "Base64",
	-- A single bisection round's reply, the root hash at the mid cycle.
	BisectionCommitment = "Base64",
	-- The disputed step's access log. Step or reset is decided by the cycle the referee names,
	-- not carried in the message.
	LogCommitment = "AccessLog",
}

local function send(player, value, schema)
	local line = cartesi.tojson(value, -1, schema, SCHEMA_DICT)
	trace_wire(player, "to", line)
	assert(player.connection:send(line .. "\n"))
end

-- Reads and decodes one full line from a player, blocking until it is in and resuming from any
-- partial parked on the player. Lines the player still owes as drops (replies to superseded
-- requests) are discarded. On the awaited reply the player's in-flight request is cleared.
local function receive(player, schema)
	local conn = player.connection
	conn:settimeout(nil)
	while true do
		local line = assert(conn:receive("*l", player.partial))
		trace_wire(player, "from", line)
		if player.stale_requests_pending > 0 then
			player.stale_requests_pending, player.partial = player.stale_requests_pending - 1, nil
		else
			player.last_request_code, player.last_request_schema, player.partial = nil, nil, nil
			return cartesi.fromjson(line, schema, SCHEMA_DICT)
		end
	end
end

-- Reads a line from whichever connection completes one first, without blocking on any single
-- one. The players table's connection-to-index map links each ready connection back to its
-- player. Bytes accumulate in each player's partial until a line completes. A line a player
-- still owes as a drop is discarded and reading continues, otherwise its in-flight request is
-- cleared and that player and its decoded reply returned.
local function receive_any(players, conns, schema)
	for _, conn in ipairs(conns) do
		conn:settimeout(0)
	end
	while true do
		for _, conn in ipairs(socket.select(conns, nil)) do
			local player = players[players.index_of[conn]]
			local line, status, partial = conn:receive("*l", player.partial)
			if line then
				trace_wire(player, "from", line)
				if player.stale_requests_pending > 0 then
					player.stale_requests_pending, player.partial = player.stale_requests_pending - 1, nil
				else
					player.last_request_code, player.last_request_schema, player.partial = nil, nil, nil
					return player, cartesi.fromjson(line, schema, SCHEMA_DICT)
				end
			else
				assert(status == "timeout", status)
				player.partial = partial
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Players
--
-- The two players run identical code, differing only in the machine they hold, the honest one
-- a bare machine and the dishonest one a composite that reports a fake machine past the cheat
-- point.
--------------------------------------------------------------------------------

-- Instantiates the calculator template on its own freshly spawned server, with `expr` written
-- into the input NVRAM.
local function new_remote_machine(expr)
	local server = assert(cartesi_jsonrpc.spawn_server("127.0.0.1:0"))
	server:set_cleanup_call(cartesi_jsonrpc.SHUTDOWN)
	local machine = server(TEMPLATE)
	local input = assert(find_drive(machine:get_initial_config(), "nvram", "input"), "missing input NVRAM")
	-- bc reads a line at a time, so the expression needs a trailing newline. The rest of the
	-- pristine NVRAM stays zero.
	machine:write_memory(input.start, expr .. "\n")
	return machine
end

--------------------------------------------------------------------------------
-- Fork trick
--
-- A player holds the agreed lower bound in `agreed_lo_machine` and, while bisecting, a
-- `tentative_mid_machine` forked from it and advanced to the mid cycle. It never runs backward,
-- since the referee never bisects below the agreed machine. Each round the referee names the
-- branch taken at the previous round, so the player promotes the tentative machine on "agree",
-- discards it on "disagree", and does nothing on "start".
--------------------------------------------------------------------------------

-- Applies the branch the referee reported for the previous round. "agree" promotes the tentative
-- machine to the agreed one, "disagree" discards it, "start" has none. A round past the halt is a
-- fixed point answered without forking, leaving no tentative machine, but that only happens above
-- the halt where rounds disagree, so "agree" never finds the slot empty. Either way it is cleared.
local function take_branch(player, branch)
	if branch == "agree" then
		player.agreed_lo_machine:shutdown_server()
		player.agreed_lo_machine = player.tentative_mid_machine
	elseif branch == "disagree" and player.tentative_mid_machine then
		player.tentative_mid_machine:shutdown_server()
	end
	player.tentative_mid_machine = nil
end

-- The operations the referee invokes on a player by name, each taking the player first so a
-- colon call like player:prove_output() supplies it. They return plain Lua values that the
-- referee's named schema turns into wire JSON and back. new_player below stores them as player
-- fields, and the referee's trusted snippets run with the player as their environment, reaching
-- these by name.

-- The claimed final state. Forks the agreed machine, runs it to halt, and reports its root
-- hash. At halt it also captures the output into player.output_result (the result string plus
-- the output drive's subtree proof) so prove_output() answers later without a rerun, and records
-- the final hash and halting mcycle so rounds past the halt are answered from this fixed point.
-- It runs at commitment time, when the agreed machine is still the clean mcycle-0 machine.
local function commit_final_hash(player)
	local machine = assert(player.agreed_lo_machine:fork_server())
	local output_nvram = assert(find_drive(machine:get_initial_config(), "nvram", "output"), "missing output NVRAM")
	machine:run(math.maxinteger)
	player.output_result = {
		target_value = (string.unpack("z", machine:read_memory(output_nvram.start, output_nvram.length))),
		proof = machine:get_proof(output_nvram.start, output_nvram.log2_size),
	}
	player.final_hash = machine:get_root_hash()
	player.halt_mcycle = machine:read_reg("mcycle")
	machine:shutdown_server()
	return player.final_hash
end

-- One bisection round. After taking the previous branch, the player forks the agreed machine,
-- advances the fork to the target (an mcycle or uarch_cycle per level), and returns its root
-- hash. An mcycle round at or past the halting mcycle is a fixed point answered with the cached
-- final hash, no fork at all.
local function commit_bisection(player, branch, level, target)
	take_branch(player, branch)
	if level == "mcycle" and target >= player.halt_mcycle then
		return player.final_hash
	end
	player.tentative_mid_machine = assert(player.agreed_lo_machine:fork_server())
	if level == "mcycle" then
		player.tentative_mid_machine:run(target)
	else
		player.tentative_mid_machine:run_uarch(target)
	end
	return player.tentative_mid_machine:get_root_hash()
end

-- The terminal round, once bisection has isolated the disputed step. The last branch leaves the
-- agreed machine at that step, so the player logs the transition out of it. The transition out of
-- UARCH_CYCLE_MAX-1 is the reset, every other an ordinary step, decided by the cycle the referee
-- names rather than the machine's own uarch_cycle, which at the reset boundary sits at the halt.
local function commit_log(player, branch, cycle)
	take_branch(player, branch)
	local agreed = player.agreed_lo_machine
	if cycle == cartesi.UARCH_CYCLE_MAX - 1 then
		return agreed:log_reset_uarch()
	end
	return agreed:log_step_uarch()
end

-- The output captured during commit_final_hash, the result bytes and the output drive's
-- subtree proof. Only those bytes travel, the referee pads the rest when it hashes.
local function prove_output(player)
	return player.output_result
end

-- Connects to the referee and serves its requests, loading each code snippet, running it in the
-- player's scope, and sending the value back, until the game ends. Then shuts down every machine
-- and fork it still holds.
local function run(player)
	local address = assert(arg[2], "missing referee address")
	local host, port = address:match("^(.-):(%d+)$")
	player.connection = assert(socket.connect(host, tonumber(port)))
	while true do
		local request = receive(player)
		if request.finish then
			break
		end
		-- The trusted referee's snippet runs with the player as its environment, reaching the
		-- player and its operations by name.
		local chunk = assert(load(request.code, "=referee", "t", player))
		-- The referee names the schema its reply should be encoded under.
		send(player, chunk(), request.schema)
	end
	player.connection:close()
	if player.tentative_mid_machine then
		player.tentative_mid_machine:shutdown_server()
	end
	player.agreed_lo_machine:shutdown_server()
end

-- A player bundles the agreed machine it was handed (bare or the composite), which anchors the
-- bisection at the lower bound, the tentative machine it forks while bisecting, and the operations
-- above as fields the referee invokes by name. It also carries a reference to itself under
-- `player`, since it is the environment the referee's snippets run in.
local function new_player(machine)
	local player = {
		agreed_lo_machine = machine,
		tentative_mid_machine = nil,
		stale_requests_pending = 0,
		commit_final_hash = commit_final_hash,
		commit_bisection = commit_bisection,
		commit_log = commit_log,
		prove_output = prove_output,
		run = run,
	}
	player.player = player
	return player
end

--------------------------------------------------------------------------------
-- Referee
--------------------------------------------------------------------------------

-- The one place the referee issues a request, used by every wait_for_*. Each player records the
-- request it is handling, cleared once the reply is read. If it is already handling this exact
-- request, its in-flight reply answers it and nothing is sent. If it is handling a superseded
-- one, the new request is sent and the stale reply counted to be dropped. A player handling
-- nothing is simply asked.
local function request(player, schema, code)
	if player.last_request_code == code and player.last_request_schema == schema then
		return
	end
	if player.last_request_code ~= nil then
		player.stale_requests_pending = player.stale_requests_pending + 1
	end
	send(player, { code = code, schema = schema })
	player.last_request_code, player.last_request_schema = code, schema
end

-- Asks a player to run a snippet (a string.format template plus its arguments) and waits for
-- the single reply, encoded and decoded under the named schema.
local function wait_for_one(player, schema, code, ...)
	request(player, schema, string.format(code, ...))
	return receive(player, schema)
end

-- Broadcasts the request to every player, then collects every reply in completion order through
-- receive_any, so the players compute in parallel and a slow one never holds up a ready one.
-- Returns the replies keyed by player index.
local function wait_for_all(players, schema, code, ...)
	code = string.format(code, ...)
	local conns, replies = {}, {}
	for _, player in ipairs(players) do
		request(player, schema, code)
		conns[#conns + 1] = player.connection
	end
	for _ = 1, #conns do
		local player, reply = receive_any(players, conns, schema)
		replies[player.index] = reply
	end
	return replies
end

-- Broadcasts the request and returns the first reply to arrive, leaving the rest. It shares the
-- request discipline above and does not judge the reply, the caller does.
local function wait_for_any(players, schema, code, ...)
	code = string.format(code, ...)
	local conns = {}
	for _, player in ipairs(players) do
		request(player, schema, code)
		conns[#conns + 1] = player.connection
	end
	local _, reply = receive_any(players, conns, schema)
	return reply
end

-- Asks both players for their opening commitment and returns the two, keyed by index.
local function wait_for_final_hash(players)
	return wait_for_all(players, "FinalHashCommitment", "return player:commit_final_hash()")
end

-- Broadcasts one bisection round at `target` on `level`, carrying the branch taken at the
-- previous round, and returns both players' root hashes there, keyed by player index.
local function wait_for_bisection(players, branch, level, target)
	return wait_for_all(players, "BisectionCommitment", "return player:commit_bisection(%q, %q, %d)", branch, level, target)
end

-- Sends a player the terminal round, naming the agreed uarch cycle so the player logs the
-- matching transition (a reset out of UARCH_CYCLE_MAX-1, a step otherwise), and waits for the
-- disputed step's access log.
local function wait_for_log(player, branch, cycle)
	return wait_for_one(player, "LogCommitment", "return player:commit_log(%q, %d)", branch, cycle)
end

-- Asks both players for the result and returns the first output proof to arrive.
local function wait_for_output(players)
	return wait_for_any(players, "StateValueProof", "return player:prove_output()")
end

-- Tells a player the game is over and to stop. No reply is expected, the player breaks its serve
-- loop on this message and closes its connection.
local function finish(player)
	send(player, { finish = true })
end

-- Checks an output submission against a verified final hash. The bytes must hash to the proof's
-- target, the target must sit at the output drive address, and the proof must roll up to the
-- final hash. Returns whether it holds.
local function verify_output(dapp_contract, final_hash, output)
	return output.proof.root_hash == final_hash
		and output.proof.target_address == dapp_contract.output.start
		and output.proof.log2_target_size == dapp_contract.output.log2_size
		and tree_hash(output.target_value, dapp_contract.output.log2_size) == output.proof.target_hash
		and pcall(proof.slice_assert, output.proof)
end

-- Bisects one level over [0, hi], updating `state` in place. Each round it sends the running
-- branch and writes back the agreed lower-end hash, player 1's after-hash, the branch, and the
-- converged lower bound `lo`. Bounds are compared and halved as unsigned 64-bit (math.ult and
-- >>), so the mcycle level can use the full MCYCLE_MAX ceiling (-1 as a signed Lua integer),
-- and the small uarch bounds reduce to ordinary arithmetic.
local function bisect_level(players, level, hi, state)
	local lo = 0
	while math.ult(1, hi - lo) do
		local mid = lo + ((hi - lo) >> 1)
		local hash = wait_for_bisection(players, state.branch, level, mid)
		if hash[1] == hash[2] then
			lo, state.last_agreed_hash, state.branch = mid, hash[1], "agree"
		else
			hi, state.hash_after, state.branch = mid, hash[1], "disagree"
		end
	end
	state.lo = lo
end

-- Drives the interactive dispute and returns the winner. It shrinks the interval of
-- disagreement, first an mcycle range to the disputed instruction, then a uarch_cycle range to
-- the disputed step, tracking the agreed lower-end hash and player 1's after-hash in `state`. At
-- the disputed step it verifies player 1's log standalone against the agreed before-hash and its
-- committed after-hash. If it proves, player 1 won, otherwise player 2 is the honest one.
local function adjudicate_dispute(players, initial_hash)
	local state = { last_agreed_hash = initial_hash, hash_after = players[1].final_hash, branch = "start" }

	-- Both levels bisect the emulator's full ceiling. Past its halt a machine is a fixed point,
	-- so a hash asked there just repeats its final hash, and the disagreement still lands on the
	-- diverging cycle wherever each halts.
	bisect_level(players, "mcycle", cartesi.MCYCLE_MAX, state)
	bisect_level(players, "uarch_cycle", cartesi.UARCH_CYCLE_MAX, state)

	-- The converged uarch cycle says whether the disputed transition is a step or the terminal
	-- reset, since the only transition out of UARCH_CYCLE_MAX-1 is the reset. The referee names it
	-- to player 1, which logs the matching transition. Player 2 is not asked, only player 1 is
	-- verified.
	local is_reset = state.lo == cartesi.UARCH_CYCLE_MAX - 1
	local log = wait_for_log(players[1], state.branch, state.lo)

	-- If player 1's log proves the before-hash advances to its committed after-hash, player 1
	-- won, otherwise player 2 is the honest one.
	local verify = is_reset and cartesi.machine.verify_reset_uarch or cartesi.machine.verify_step_uarch
	local won = pcall(verify, cartesi.machine, state.last_agreed_hash, log, state.hash_after)
	return won and players[1] or players[2]
end

-- Waits for both players to connect and collects their commitments. It binds the listen address,
-- accepts the two players in turn, numbering them by connection order, and asks both for their
-- final state hash at once so the run-to-halt commitments overlap. The hash needs no checking
-- here, since a wrong hash can win neither the dispute nor the output phase. The returned table
-- carries a __close metamethod that finishes every player on the way out.
local function wait_for_commitments()
	local address = assert(arg[2], "missing listen address")
	local host, port = address:match("^(.-):(%d+)$")
	local listener = assert(socket.bind(host, tonumber(port)))
	-- The connection-to-index map lets receive_any link each ready connection back to its player.
	local players = setmetatable({ index_of = {} }, {
		__close = function(self)
			for _, player in ipairs(self) do
				finish(player)
			end
		end,
	})
	for index = 1, 2 do
		local connection = assert(listener:accept())
		players[index] = { index = index, connection = connection, stale_requests_pending = 0 }
		players.index_of[connection] = index
	end
	local commitments = wait_for_final_hash(players)
	for index, player in ipairs(players) do
		player.final_hash = commitments[index]
	end
	return players
end

-- Models application deployment, returning the contract context the referee works against. Its
-- constant, expression-independent parts are fixed here before any dispute, as they would be on
-- chain at deploy time. It loads the calculator template once to read what the contract
-- publishes, the input and output NVRAM descriptors and a proof of the pristine input drive,
-- then discards it. The agreed initial hash is not here, since it depends on the expression.
local function deploy()
	local template = cartesi.machine(TEMPLATE)
	local config = template:get_initial_config()
	local dapp_contract = {
		input = assert(find_drive(config, "nvram", "input"), "missing input NVRAM"),
		output = assert(find_drive(config, "nvram", "output"), "missing output NVRAM"),
	}
	dapp_contract.input_proof = template:get_proof(dapp_contract.input.start, dapp_contract.input.log2_size)
	return dapp_contract
end

-- Runs the whole game, collecting the two commitments, settling any dispute to name the honest
-- winner, then extracting the verified result against that winner's hash.
local function run_referee(referee, dapp_contract)
	-- The players are finished automatically when this scope exits, by any path.
	local players <close> = wait_for_commitments()

	-- The dispute names the honest winner, whose final hash the output must match. With
	-- no dispute the two players agree, so either's final hash will do.
	local winner = players[1]
	if players[1].final_hash ~= players[2].final_hash then
		winner = adjudicate_dispute(players, referee.initial_hash)
	end

	-- The result comes from whichever player first returns an output proof that verifies against
	-- the winner's hash. Asking the loser is harmless, its output cannot match. A slow or bad
	-- reply cannot sink the game, the referee keeps asking until a valid proof arrives.
	while true do
		local output = wait_for_output(players)
		if verify_output(dapp_contract, winner.final_hash, output) then
			break
		end
	end
end

-- Builds a referee for a public expression against a deployed dapp contract. The agreed initial
-- hash depends on the expression, so it is computed here and kept on the referee. Rolling the
-- hash of the input NVRAM holding the expression up the pristine input proof gives the root hash
-- of the template instantiated with it, with tree_hash padding the rest to match the honest
-- player's NVRAM. Honest play starts from exactly this state, never a player-declared one.
local function new_referee(dapp_contract, expr)
	local initial_hash =
		proof.roll_hash_up_tree(dapp_contract.input_proof, tree_hash(expr .. "\n", dapp_contract.input.log2_size))
	return { initial_hash = initial_hash, run = run_referee }
end

--------------------------------------------------------------------------------
-- Role dispatch
--------------------------------------------------------------------------------

local role = assert(arg[1], "missing role (referee, honest, or dishonest)")

if role == "referee" then
	local dapp_contract = deploy()
	local referee = new_referee(dapp_contract, assert(arg[3], "missing public expression"))
	referee:run(dapp_contract)
elseif role == "honest" then
	local player = new_player(new_remote_machine(assert(arg[3], "missing expression")))
	player:run()
elseif role == "dishonest" then
	local player = new_player(
		dishonest.new_composite_machine(
			new_remote_machine(assert(arg[3], "missing expression")),
			assert(tonumber(arg[4]), "missing cheat mcycle"),
			assert(tonumber(arg[5]), "missing cheat uarch cycle"),
			new_remote_machine(assert(arg[6], "missing cheat expression"))
		)
	)
	player:run()
else
	error("unknown role: " .. role)
end
