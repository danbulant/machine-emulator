--[[
Test suite for machine API surface.
Specifically, it provides test coverage for:
    machine.cpp (get_address_name, get_reg_address)
    shadow-registers.hpp (shadow_registers_get_what, shadow_registers_get_what_name)
    shadow-tlb.hpp (shadow_tlb_get_what, shadow_tlb_get_what_name)
    shadow-uarch-state.hpp (shadow_uarch_state_get_what, shadow_uarch_state_get_what_name)
    pmas.hpp (pmas_get_what, pmas_get_what_name)
]]

local lester = require("cartesi.third-party.lester")
local cartesi = require("cartesi")
local describe, it, expect = lester.describe, lester.it, lester.expect

local variants = {
    {
        name = "local",
        create = function(config)
            return cartesi.machine(config)
        end,
    },
    {
        name = "remote",
        create = function(config)
            local jsonrpc = require("cartesi.jsonrpc")
            return jsonrpc.spawn_server():set_cleanup_call(jsonrpc.SHUTDOWN):create(config)
        end,
    },
}

for _, variant in ipairs(variants) do
    describe("machine API (" .. variant.name .. ")", function()
        local machine <close> = variant.create({ ram = { length = 0x1000 } })

        describe("get_address_name", function()
            -- Build table of reg name -> expected get_address_name output.
            -- Names follow shadow_registers_get_what_name / shadow_uarch_state_get_what_name strings.
            local reg_address_names = {}
            for i = 0, 31 do
                reg_address_names["x" .. i] = "x" .. i
                reg_address_names["f" .. i] = "f" .. i
                reg_address_names["uarch_x" .. i] = "uarch.x" .. i
            end
            local identity_regs = {
                "pc",
                "fcsr",
                "mvendorid",
                "marchid",
                "mimpid",
                "mcycle",
                "icycleinstret",
                "mstatus",
                "mtvec",
                "mscratch",
                "mepc",
                "mcause",
                "mtval",
                "misa",
                "mie",
                "mip",
                "medeleg",
                "mideleg",
                "mcounteren",
                "menvcfg",
                "stvec",
                "sscratch",
                "sepc",
                "scause",
                "stval",
                "satp",
                "scounteren",
                "senvcfg",
                "ilrsc",
                "iprv",
                "iunrep",
            }
            for _, name in ipairs(identity_regs) do
                reg_address_names[name] = name
            end
            local namespaced_regs = {
                iflags_X = "iflags.X",
                iflags_Y = "iflags.Y",
                iflags_H = "iflags.H",
                clint_mtimecmp = "clint.mtimecmp",
                plic_girqpend = "plic.girqpend",
                plic_girqsrvd = "plic.girqsrvd",
                htif_tohost = "htif.tohost",
                htif_fromhost = "htif.fromhost",
                htif_ihalt = "htif.ihalt",
                htif_iconsole = "htif.iconsole",
                htif_iyield = "htif.iyield",
                uarch_halt_flag = "uarch.halt_flag",
                uarch_cycle = "uarch.cycle",
                uarch_pc = "uarch.pc",
            }
            for reg_name, addr_name in pairs(namespaced_regs) do
                reg_address_names[reg_name] = addr_name
            end

            it("should roundtrip get_reg_address through get_address_name", function()
                for reg_name, expected in pairs(reg_address_names) do
                    local paddr = machine:get_reg_address(reg_name)
                    expect.equal(machine:get_address_name(paddr), expected)
                end
            end)

            it("should return correct names for TLB slot fields", function()
                -- shadow_tlb_slot layout (32 bytes): vaddr_page@0, vp_offset@8, pma_index@16, zero_padding_@24
                local tlb_slot_size = 32 -- sizeof(shadow_tlb_slot)
                local tlb_set_bytes = 256 * tlb_slot_size -- TLB_SET_SIZE * sizeof(shadow_tlb_slot)
                local tlb_fields = {
                    [0] = "tlb.slot.vaddr_page",
                    [8] = "tlb.slot.vp_offset",
                    [16] = "tlb.slot.pma_index",
                    [24] = "tlb.slot.zero_padding_",
                }
                for set_index = 0, 2 do
                    for _, slot_index in ipairs({ 0, 17 }) do
                        for field_offset, expected in pairs(tlb_fields) do
                            local paddr = cartesi.AR_SHADOW_TLB_START
                                + set_index * tlb_set_bytes
                                + slot_index * tlb_slot_size
                                + field_offset
                            expect.equal(machine:get_address_name(paddr), expected)
                        end
                    end
                end
            end)

            it("should return correct names for PMA entry fields", function()
                -- pmas_entry layout (16 bytes): istart@0, ilength@8
                expect.equal(machine:get_address_name(cartesi.AR_PMAS_START + 0), "pma.istart")
                expect.equal(machine:get_address_name(cartesi.AR_PMAS_START + 8), "pma.ilength")
            end)

            it("should return uarch.ram for uarch RAM address", function()
                expect.equal(machine:get_address_name(cartesi.UARCH_RAM_START_ADDRESS), "uarch.ram")
            end)

            it("should return memory for unmapped address", function()
                expect.equal(machine:get_address_name(cartesi.AR_RAM_START), "memory")
            end)

            it("should return unknown_ for misaligned addresses in each shadow region", function()
                expect.equal(machine:get_address_name(cartesi.AR_SHADOW_STATE_START + 1), "state.unknown_")
                expect.equal(machine:get_address_name(cartesi.AR_SHADOW_TLB_START + 1), "tlb.unknown_")
                expect.equal(machine:get_address_name(cartesi.AR_PMAS_START + 1), "pma.unknown_")
                expect.equal(machine:get_address_name(cartesi.UARCH_SHADOW_START_ADDRESS + 1), "uarch.unknown_")
            end)

            it("should return correct names for peripheral regions", function()
                expect.equal(machine:get_address_name(cartesi.AR_DTB_START), "dtb")
                expect.equal(machine:get_address_name(cartesi.AR_DTB_START + cartesi.AR_DTB_LENGTH - 1), "dtb")
                expect.equal(machine:get_address_name(cartesi.AR_CLINT_START), "clint")
                expect.equal(machine:get_address_name(cartesi.AR_CLINT_START + cartesi.AR_CLINT_LENGTH - 1), "clint")
                expect.equal(machine:get_address_name(cartesi.AR_HTIF_START), "htif")
                expect.equal(machine:get_address_name(cartesi.AR_HTIF_START + cartesi.AR_HTIF_LENGTH - 1), "htif")
                expect.equal(machine:get_address_name(cartesi.AR_PLIC_START), "plic")
                expect.equal(machine:get_address_name(cartesi.AR_PLIC_START + cartesi.AR_PLIC_LENGTH - 1), "plic")
                expect.equal(machine:get_address_name(cartesi.AR_CMIO_RX_BUFFER_START), "cmio.rx_buffer")
                expect.equal(machine:get_address_name(cartesi.AR_CMIO_TX_BUFFER_START), "cmio.tx_buffer")
                expect.equal(machine:get_address_name(cartesi.AR_FIRST_VIRTIO_START), "virtio")
                expect.equal(machine:get_address_name(cartesi.AR_LAST_VIRTIO_END - 1), "virtio")
            end)
        end)
    end)
end
