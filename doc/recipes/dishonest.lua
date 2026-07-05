-- A composite presents the machine interface backed by two machines and switches from the
-- first to the second at a given point (mcycle offset from a cheat input's feed, uarch_cycle),
-- reporting the first up to and including the point and the second after. run pins the step's
-- mcycle, since the uarch advances mcycle on its own and a live read mid-step would place the
-- switch wrong. Only the active machine advances between input boundaries, the second having
-- been positioned at the switch point ahead of time. Forking forks both. Only the switching
-- methods are defined below, the rest fall through to the active machine.
-- In verification-game.lua the machine takes no inputs, so the point is an absolute (mcycle,
-- uarch_cycle) pair, with offsets measured from mcycle 0 and the cheat machine positioned at
-- construction. In rolling-verification-game.lua inputs flow through the composite, which
-- recognizes the cheat input by its bytes, feeds the cheat machine a doctored input in its
-- place, and positions it right after. Recognizing the input by its bytes survives rollbacks,
-- since a rolled-back feed disappears with the fork that made it.
-- First access caches the result on the instance, so later accesses skip __index. A defined
-- method copies over as is. An undefined key naming a function on the active machine becomes a
-- forwarding method, built once and shared on composite_meta. Any other value passes through
-- uncached, since it may change.
local cartesi = require("cartesi")

local composite_meta = {}
composite_meta.__index = function(self, key)
    local method = composite_meta[key]
    if not method then
        local active_val = self.active[key]
        if type(active_val) == "function" then
            method = function(this, ...)
                return this.active[key](this.active, ...)
            end
            composite_meta[key] = method
        else
            return active_val
        end
    end
    self[key] = method
    return method
end

-- Runs the idle machine to the target, resuming through automatic yields and dropping their
-- outputs, which only the active machine reports.
local function run_idle(machine, target)
    local break_reason
    repeat
        break_reason = machine:run(target)
    until break_reason ~= cartesi.BREAK_REASON_YIELDED_AUTOMATICALLY
end

-- True for positions strictly after the cheat point (lexicographic on the pair). Positions
-- before the cheat input's feed are never past, and the offsets of positions after it only grow.
local function past_cheat(self, mcycle, uarch_cycle)
    if not self.cheated then
        return false
    end
    if mcycle - self.feed_mcycle ~= self.cheat_offset then
        return mcycle - self.feed_mcycle > self.cheat_offset
    end
    return uarch_cycle > self.cheat_uarch_cycle
end

-- The composite for verification-game.lua, cheating at an absolute (mcycle, uarch_cycle) point
-- of a machine that takes no inputs. The cheat machine is run to the switch mcycle once, here.
local function new_composite_machine(real_machine, cheat_mcycle, cheat_uarch_cycle, cheat_machine)
    cheat_machine:run(cheat_mcycle)
    return setmetatable({
        real_machine = real_machine,
        cheat_machine = cheat_machine,
        active = real_machine,
        mcycle = 0,
        cheated = true,
        feed_mcycle = 0,
        cheat_offset = cheat_mcycle,
        cheat_uarch_cycle = cheat_uarch_cycle,
    }, composite_meta)
end

-- The composite for rolling-verification-game.lua, cheating at an (mcycle offset, uarch_cycle)
-- point of the input whose bytes match cheat_input_data. Both machines start at the same input
-- boundary.
local function new_rolling_composite_machine(
    real_machine,
    cheat_input_data,
    cheat_offset,
    cheat_uarch_cycle,
    cheat_machine,
    cheat_data
)
    return setmetatable({
        real_machine = real_machine,
        cheat_machine = cheat_machine,
        active = real_machine,
        mcycle = 0,
        cheated = false,
        feed_mcycle = 0,
        cheat_offset = cheat_offset,
        cheat_uarch_cycle = cheat_uarch_cycle,
        cheat_input_data = cheat_input_data,
        cheat_data = cheat_data,
    }, composite_meta)
end

function composite_meta.fork_server(self)
    local fork = setmetatable({
        real_machine = assert(self.real_machine:fork_server()),
        cheat_machine = assert(self.cheat_machine:fork_server()),
        mcycle = self.mcycle,
        cheated = self.cheated,
        feed_mcycle = self.feed_mcycle,
        cheat_offset = self.cheat_offset,
        cheat_uarch_cycle = self.cheat_uarch_cycle,
        cheat_input_data = self.cheat_input_data,
        cheat_data = self.cheat_data,
    }, composite_meta)
    fork.active = fork.real_machine
    return fork
end

-- Both machines take every input, the idle one first catching up to its own input boundary.
-- Each records its own root hash, since their states diverge past the cheat input's feed. The
-- cheat machine takes the doctored input in place of the cheat input and is then run to the
-- switch point, where later rounds expect to find it.
function composite_meta.send_cmio_response(self, _, reason, data)
    for _, machine in ipairs({ self.real_machine, self.cheat_machine }) do
        run_idle(machine, math.maxinteger)
        local input = data == self.cheat_input_data and machine == self.cheat_machine and self.cheat_data or data
        machine:send_cmio_response(machine:get_root_hash(), reason, input)
    end
    if data == self.cheat_input_data then
        self.cheated, self.feed_mcycle = true, self.real_machine:read_reg("mcycle")
        run_idle(self.cheat_machine, self.feed_mcycle + self.cheat_offset)
    end
    -- The reported boundary is the active machine's, pinned at its own mcycle.
    self.active = past_cheat(self, self.real_machine:read_reg("mcycle"), 0) and self.cheat_machine or self.real_machine
    self.mcycle = self.active:read_reg("mcycle")
end

function composite_meta.run(self, m)
    self.mcycle = m
    self.active = past_cheat(self, m, 0) and self.cheat_machine or self.real_machine
    return self.active:run(m)
end

-- The uarch stays within the pinned mcycle, so the switch is judged against that, not the
-- live mcycle the uarch advances.
function composite_meta.run_uarch(self, u)
    self.active = past_cheat(self, self.mcycle, u) and self.cheat_machine or self.real_machine
    self.active:run_uarch(u)
end

function composite_meta.shutdown_server(self)
    self.real_machine:shutdown_server()
    self.cheat_machine:shutdown_server()
end

-- The log methods always report the second machine, rolled to the current position. self is
-- always an ephemeral fork here, so rolling it forward in place is fine.
function composite_meta.log_step_uarch(self, log_type)
    self.cheat_machine:run_uarch(self.active:read_reg("uarch_cycle"))
    return self.cheat_machine:log_step_uarch(log_type)
end
function composite_meta.log_reset_uarch(self, log_type)
    self.cheat_machine:run_uarch(self.active:read_reg("uarch_cycle"))
    return self.cheat_machine:log_reset_uarch(log_type)
end

return { new_composite_machine = new_composite_machine, new_rolling_composite_machine = new_rolling_composite_machine }
