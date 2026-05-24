-- Load the JSON-RPC submodule for remote Cartesi Machines
local cartesi_jsonrpc = require"cartesi.jsonrpc"

-- Writes formatted text to stderr
local function stderr(fmt, ...)
    io.stderr:write(string.format(fmt, ...))
end

-- Connect to remote Cartesi Machine server (shut it down automatically on exit)
local remote_address = assert(arg[1], "missing remote address")
stderr("Connecting to remote cartesi machine at '%s'\n", remote_address)
local cartesi_jsonrpc_machine <close> = assert(cartesi_jsonrpc.connect_server(remote_address)):
    set_cleanup_call(cartesi_jsonrpc.SHUTDOWN)

-- Print server version (and test connection)
local v = assert(cartesi_jsonrpc_machine:get_server_version())
stderr("Connected: remote version is %d.%d.%d\n", v.major, v.minor, v.patch)

-- Instantiate remote machine from configuration
local machine = cartesi_jsonrpc_machine((require(arg[2])))

-- Run machine until it halts or yields
while machine:read_reg("iflags_H") == 0 and machine:read_reg("iflags_Y") == 0 do
    machine:run(math.maxinteger)
end

-- Print machine status
if machine:read_reg("iflags_H") ~= 0 then
    stderr("\nHalted\n")
else
    stderr("\nYielded manual\n")
end
-- Print cycle count
stderr("Cycles: %u\n", machine:read_reg("mcycle"))
