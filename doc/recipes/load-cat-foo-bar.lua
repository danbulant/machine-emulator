-- Load the Cartesi module
local cartesi = require("cartesi")

-- Instantiate machine from persistent state directory
local machine = cartesi.machine("cat-foo-bar")

-- Run machine until it halts or yields manual
repeat
    local break_reason = machine:run(math.maxinteger)
until break_reason == cartesi.BREAK_REASON_HALTED or break_reason == cartesi.BREAK_REASON_YIELDED_MANUALLY
