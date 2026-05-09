-- Load the Cartesi module
local cartesi = require("cartesi")

-- Instantiate machine from template
local machine = cartesi.machine("calculator-template")

-- Replace input NVRAM by label
machine:replace_memory_range({
    label = "input",
    backing_store = { data_filename = assert(arg[1], "missing input image filename") },
})

-- Replace output NVRAM by label
machine:replace_memory_range({
    label = "output",
    backing_store = {
        data_filename = assert(arg[2], "missing output image filename"),
        shared = true,
    },
})

-- Run machine until it halts or yields manual
repeat
    local break_reason = machine:run(math.maxinteger)
until break_reason == cartesi.BREAK_REASON_HALTED or break_reason == cartesi.BREAK_REASON_YIELDED_MANUALLY
