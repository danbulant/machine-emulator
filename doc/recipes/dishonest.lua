-- A composite presents the machine interface backed by two machines and switches from the
-- first to the second at a given point (mcycle, uarch_cycle), reporting the first up to and
-- including the point and the second after. run pins the step's mcycle, since the uarch
-- advances mcycle on its own and a live read mid-step would place the switch wrong. Only the
-- active machine advances, the second having been run to the switch mcycle once at
-- construction. Forking forks both. Only the switching methods are defined below, the rest
-- fall through to the active machine.
-- First access caches the result on the instance, so later accesses skip __index. A defined
-- method copies over as is. An undefined key naming a function on the active machine becomes a
-- forwarding method, built once and shared on composite_meta. Any other value passes through
-- uncached, since it may change.
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

-- True for positions strictly after the cheat point (lexicographic on the pair).
local function past_cheat(self, mcycle, uarch_cycle)
    if mcycle ~= self.cheat_mcycle then
        return mcycle > self.cheat_mcycle
    end
    return uarch_cycle > self.cheat_uarch_cycle
end

local function new_composite_machine(real_machine, cheat_mcycle, cheat_uarch_cycle, cheat_machine)
    cheat_machine:run(cheat_mcycle)
    return setmetatable({
        real_machine = real_machine,
        cheat_machine = cheat_machine,
        active = real_machine,
        mcycle = 0,
        cheat_mcycle = cheat_mcycle,
        cheat_uarch_cycle = cheat_uarch_cycle,
    }, composite_meta)
end

function composite_meta.fork_server(self)
    local fork = setmetatable({
        real_machine = assert(self.real_machine:fork_server()),
        cheat_machine = assert(self.cheat_machine:fork_server()),
        mcycle = self.mcycle,
        cheat_mcycle = self.cheat_mcycle,
        cheat_uarch_cycle = self.cheat_uarch_cycle,
    }, composite_meta)
    fork.active = fork.real_machine
    return fork
end

function composite_meta.run(self, m)
    self.mcycle = m
    self.active = past_cheat(self, m, 0) and self.cheat_machine or self.real_machine
    self.active:run(m)
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

return { new_composite_machine = new_composite_machine }
