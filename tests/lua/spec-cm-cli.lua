-- Copyright Cartesi and individual authors (see AUTHORS)
-- SPDX-License-Identifier: LGPL-3.0-or-later
--
-- This program is free software: you can redistribute it and/or modify it under
-- the terms of the GNU Lesser General Public License as published by the Free
-- Software Foundation, either version 3 of the License, or (at your option) any
-- later version.
--
-- This program is distributed in the hope that it will be useful, but WITHOUT ANY
-- WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
-- PARTICULAR PURPOSE. See the GNU Lesser General Public License for more details.
--
-- You should have received a copy of the GNU Lesser General Public License along
-- with this program (see COPYING). If not, see <https://www.gnu.org/licenses/>.
--

-- Systematic test of every cartesi-machine.lua command-line option.
-- For config-shaping options, the test runs cartesi-machine.lua with
-- --store-config=<tmp> and asserts on the materialized initial config
-- returned by machine:get_initial_config(), validating the full
-- CLI -> machine builder -> get_initial_config() pipeline.

local lester = require("cartesi.third-party.lester")
local describe, it, expect = lester.describe, lester.it, lester.expect

-- Scratch directory for temp files created by CLI invocations (stores, configs, etc.)
-- Declared at module level so the post-describe cleanup can reference it.
local scratch = os.tmpname() .. ".d"
assert(os.execute("mkdir -p " .. scratch), "failed to create scratch directory")
local scratch_serial = 0

-- Refuse rm -rf on anything outside the system temp roots.
local function safer_rm_rf(dir)
    assert(not dir:match("%.%."), "refusing rm -rf on path with ..: " .. dir)
    assert(dir:match("^/tmp/") or dir:match("^/var/folders/"), "refusing rm -rf on path outside temp: " .. dir)
    os.execute("rm -rf '" .. dir:gsub("'", "'\\''") .. "'")
end

describe("cartesi-machine CLI", function()
    local cartesi = require("cartesi")
    local evmu = require("cartesi.evmu")

    -- EVM ABI function signature for EvmAdvance (must match libcmt's EVM_ADVANCE)
    local ADVANCE_SIG = [[
    EvmAdvance(
        uint256 chainId,
        address appContract,
        address msgSender,
        uint256 blockNumber,
        uint256 blockTimestamp,
        uint256 prevRandao,
        uint256 index,
        bytes payload
    )
]]

    local function encode_advance(index, payload_raw)
        return evmu.encode_calldata(ADVANCE_SIG, {
            chainId = 0,
            appContract = "0x0000000000000000000000000000000000000000",
            msgSender = "0x0000000000000000000000000000000000000000",
            blockNumber = index,
            blockTimestamp = 0,
            prevRandao = 0,
            index = index,
            payload = evmu.raw(payload_raw),
        })
    end

    local function write_bin(path, bytes)
        local f <close> = assert(io.open(path, "wb"))
        f:write(bytes)
    end

    local function read_bin(path)
        local f <close> = assert(io.open(path, "rb"))
        return f:read("*a")
    end

    -- Interpreter used for sub-invocations of cartesi-machine.lua.
    -- Under coverage (coverage=yes), the Makefile exports LUA_CLI as
    -- "lua5.4 -lluacov" so that cartesi-machine.lua children are measured.
    local CLI_LUA = os.getenv("LUA_CLI") or arg[-1]
    local CLI = os.getenv("CM_CLI") or "../../src/cartesi-machine.lua"

    local images_path = os.getenv("CARTESI_IMAGES_PATH") or "../build/images"
    if images_path:sub(-1) ~= "/" then
        images_path = images_path .. "/"
    end

    local function scratch_path(suffix)
        scratch_serial = scratch_serial + 1
        return scratch .. "/" .. scratch_serial .. (suffix or "")
    end

    -- Shell-quote a single argument
    local function shquote(s)
        return "'" .. s:gsub("'", "'\\''") .. "'"
    end

    -- Run cartesi-machine.lua with the given flags (array of strings).
    -- stdin_text is fed to the process stdin (default: /dev/null).
    -- Returns rc (integer), stdout (string), stderr (string).
    local function run(flags, stdin_text)
        local args = {}
        for _, f in ipairs(flags) do
            args[#args + 1] = shquote(f)
        end
        local tmp_out = os.tmpname()
        local tmp_err = os.tmpname()
        local tmp_rc = os.tmpname()
        local stdin_redir = "</dev/null"
        local tmp_in
        if stdin_text then
            tmp_in = os.tmpname()
            local f = io.open(tmp_in, "w")
            assert(f, "cannot open stdin tmp")
            f:write(stdin_text)
            f:close()
            stdin_redir = "<" .. tmp_in
        end
        local cmd = string.format(
            "(CARTESI_IMAGES_PATH=%s %s %s %s) %s >%s 2>%s; printf '%%d' $? >%s",
            shquote(images_path),
            CLI_LUA,
            CLI,
            table.concat(args, " "),
            stdin_redir,
            tmp_out,
            tmp_err,
            tmp_rc
        )
        os.execute(cmd)
        local function readfile(p)
            local f = io.open(p, "r")
            if not f then
                return ""
            end
            local s = f:read("*a")
            f:close()
            os.remove(p)
            return s
        end
        local rc = tonumber(readfile(tmp_rc)) or 1
        local stdout = readfile(tmp_out)
        local stderr = readfile(tmp_err)
        if tmp_in then
            os.remove(tmp_in)
        end
        return rc, stdout, stderr
    end

    -- Run and assert success (rc == 0). Returns stdout.
    local function run_ok(flags, stdin_text)
        local rc, stdout, stderr = run(flags, stdin_text)
        assert(
            rc == 0,
            string.format("expected rc=0, got %d\nflags: %s\nstderr: %s", rc, table.concat(flags, " "), stderr)
        )
        return stdout, stderr
    end

    -- Run and assert failure (rc ~= 0) with stderr matching pattern.
    local function run_fail(flags, pattern, stdin_text)
        local rc, _, stderr = run(flags, stdin_text)
        assert(rc ~= 0, string.format("expected non-zero rc\nflags: %s\nstderr: %s", table.concat(flags, " "), stderr))
        if pattern then
            assert(stderr:find(pattern), string.format("stderr did not match %q\nstderr: %s", pattern, stderr))
        end
    end

    -- Base flags used in most config-extracting invocations.
    local base_cfg_flags = { "--max-mcycle=0", "--no-init-splash", "--quiet" }

    -- Run with --store-config=<tmp> and return the parsed initial config table.
    -- Options (flags starting with -) come first, then base_cfg_flags, then
    -- --store-config, then any positional args (so option processing is not
    -- terminated early before --store-config is seen).
    local function config_for(flags, stdin_text)
        local tmp = scratch_path(".lua")
        local opts = {}
        local positional = {}
        local past_dashdash = false
        for _, f in ipairs(flags) do
            if past_dashdash or (f ~= "--" and f:sub(1, 1) ~= "-") then
                positional[#positional + 1] = f
                past_dashdash = true
            elseif f == "--" then
                past_dashdash = true
            else
                opts[#opts + 1] = f
            end
        end
        local all_flags = {}
        for _, f in ipairs(opts) do
            all_flags[#all_flags + 1] = f
        end
        for _, f in ipairs(base_cfg_flags) do
            all_flags[#all_flags + 1] = f
        end
        all_flags[#all_flags + 1] = "--store-config=" .. tmp
        if #positional > 0 then
            all_flags[#all_flags + 1] = "--"
            for _, f in ipairs(positional) do
                all_flags[#all_flags + 1] = f
            end
        end
        run_ok(all_flags, stdin_text)
        local cfg = dofile(tmp)
        os.remove(tmp)
        return cfg
    end

    -- -------------------------------------------------------------------------
    -- Early-exit options
    --
    -- What: Options that print information and exit before building a machine:
    --       -h/--help, --version, --version-json, and --assert-version.
    -- How:  run() each flag, assert rc == 0 and expected stdout substrings;
    --       run_fail() for a version mismatch to confirm the non-zero exit path.
    -- -------------------------------------------------------------------------
    it("early exit options", function()
        local rc, stdout = run({ "-h" })
        expect.equal(rc, 0)
        expect.truthy(stdout:find("cartesi%-machine"))

        rc, stdout = run({ "--help" })
        expect.equal(rc, 0)
        expect.truthy(stdout:find("cartesi%-machine"))

        rc, stdout = run({ "--version" })
        expect.equal(rc, 0)
        expect.truthy(stdout:find("cartesi%-machine"))

        rc, stdout = run({ "--version-json" })
        expect.equal(rc, 0)
        expect.truthy(stdout:find('"version"'))
        expect.truthy(stdout:find('"marchid"'))

        run_fail({ "--assert-version=999.0" }, "version mismatch")

        -- assert-version with current major.minor should succeed and continue
        local ver = string.format("%d.%d", cartesi.VERSION_MAJOR, cartesi.VERSION_MINOR)
        run_ok({ "--assert-version=" .. ver, "--max-mcycle=0", "--no-init-splash", "--quiet" })
    end)

    -- -------------------------------------------------------------------------
    -- RAM / DTB / uarch-processor config-shaping options
    --
    -- What: Options that shape the RAM, DTB, and uarch-processor fields of the
    --       initial machine config: --ram-length (three number-parse variants),
    --       --no-ram-image, --ram-image, --no-bootargs, --append-bootargs,
    --       --dtb-image, and --uarch-processor.
    -- How:  config_for() each flag and assert field values on the returned
    --       config table.  The --uarch-processor=data_filename: case exercises
    --       the backing_store def-merge path where a partial spec is merged
    --       with the existing default.
    -- -------------------------------------------------------------------------
    it("RAM, DTB, and uarch-processor options", function()
        -- --ram-length: three parse_number branches
        local cfg = config_for({ "--ram-length=64Mi" })
        expect.equal(cfg.ram.length, (64 * 1024 * 1024))

        cfg = config_for({ "--ram-length=0x4000000" })
        expect.equal(cfg.ram.length, 0x4000000)

        cfg = config_for({ "--ram-length=64 << 20" })
        expect.equal(cfg.ram.length, (64 * 1024 * 1024))

        -- --no-ram-image
        cfg = config_for({ "--no-ram-image" })
        expect.equal(cfg.ram.backing_store.data_filename, "")

        -- --ram-image
        local linux_bin = images_path .. "linux.bin"
        cfg = config_for({ "--ram-image=" .. linux_bin })
        expect.truthy(cfg.ram.backing_store.data_filename:find("linux%.bin"))

        -- --no-bootargs
        cfg = config_for({ "--no-bootargs" })
        expect.equal(cfg.dtb.bootargs, "")

        -- --append-bootargs (single and double)
        cfg = config_for({ "--append-bootargs=loglevel=3", "--append-bootargs=quiet" })
        expect.truthy(cfg.dtb.bootargs:find("loglevel=3"))
        expect.truthy(cfg.dtb.bootargs:find("quiet"))

        -- --dtb-image: use a small temp file (DTB region is 1 MiB)
        local dtb_tmp = scratch_path(".dtb")
        os.execute("truncate -s 4096 " .. dtb_tmp)
        cfg = config_for({ "--dtb-image=" .. dtb_tmp })
        expect.truthy(cfg.dtb.backing_store.data_filename:find("%d+%.dtb"))

        -- --uarch-processor=data_filename:: only data_filename supplied, other fields merged from backing_store def
        cfg = config_for({ "--uarch-processor=data_filename:" })
        expect.equal(cfg.uarch.processor.backing_store.data_filename, "")
        expect.truthy(cfg.uarch.processor.backing_store.dht_filename ~= nil)

        -- Remaining --<range>=<key>:<value> backing-store forms: each exercises the
        -- parse_backing_store path for its memory range.
        cfg = config_for({ "--ram=data_filename:" .. linux_bin })
        expect.truthy(cfg.ram.backing_store.data_filename:find("linux%.bin"))

        cfg = config_for({ "--dtb=data_filename:" .. dtb_tmp })
        expect.truthy(cfg.dtb.backing_store.data_filename:find("%d+%.dtb"))

        cfg = config_for({ "--processor=data_filename:" })
        expect.equal(cfg.processor.backing_store.data_filename, "")

        cfg = config_for({ "--pmas=data_filename:" })
        expect.equal(cfg.pmas.backing_store.data_filename, "")

        cfg = config_for({ "--uarch-ram=data_filename:" })
        expect.equal(cfg.uarch.ram.backing_store.data_filename, "")

        -- --uarch-ram-image= is a deprecated alias for --uarch-ram=data_filename:.
        -- Only run when the uarch binary is present (it is a build artifact).
        local uarch_ram_bin = "../uarch/uarch-ram.bin"
        local uf = io.open(uarch_ram_bin, "r")
        if uf then
            uf:close()
            cfg = config_for({ "--uarch-ram-image=" .. uarch_ram_bin })
            expect.truthy(cfg.uarch.ram.backing_store.data_filename:find("uarch%-ram%.bin"))
        end
    end)

    -- -------------------------------------------------------------------------
    -- Flash drive options
    --
    -- What: --flash-drive variants (label, start, length, read_only, mount:true,
    --       mount:false, mke2fs, user), --no-root-flash-drive, --hash-tree,
    --       override_bool explicit-false fix (read_only and shared toggle),
    --       and filename preservation through partial re-invocation.
    -- How:  config_for() each combination; assertions on cfg.flash_drive[i]
    --       fields verify the machine config, while assertions on
    --       cfg.dtb.init and cfg.dtb.bootargs substrings verify the guest
    --       init script and bootargs generated for each variant.
    -- -------------------------------------------------------------------------
    it("flash drive options", function()
        -- Default root flash drive present
        local cfg = config_for({})
        expect.truthy(cfg.flash_drive and cfg.flash_drive[1])
        expect.equal(cfg.flash_drive[1].label, "root")

        -- --flash-drive: verify label, start, length, read_only fields
        local flash_tmp = scratch_path(".ext2")
        os.execute("truncate -s 65536 " .. flash_tmp)
        cfg = config_for({
            "--flash-drive=label:data,start:0x80000020000000,length:0x10000,data_filename:"
                .. flash_tmp
                .. ",read_only",
        })
        local found_data
        for _, fd in ipairs(cfg.flash_drive) do
            if fd.label == "data" then
                found_data = fd
                break
            end
        end
        expect.truthy(found_data)
        expect.equal(found_data.start, 0x80000020000000)
        expect.equal(found_data.length, 0x10000)
        expect.equal(found_data.read_only, true)

        -- --no-root-flash-drive + replacement
        cfg = config_for({
            "--no-root-flash-drive",
            "--flash-drive=label:myroot,start:0x80000000000000,length:0x10000,data_filename:" .. flash_tmp,
        })
        for _, fd in ipairs(cfg.flash_drive) do
            expect.truthy(fd.label ~= "root")
        end
        -- DTB_BOOTARGS_ROOT (including init=) must be absent after removal
        expect.truthy(not cfg.dtb.bootargs:find("pmem0", 1, true))
        expect.truthy(not cfg.dtb.bootargs:find("init=", 1, true))

        -- mount:true with label: dtb.init gets a mount command for /mnt/<label> and chown for user
        local ft = scratch_path(".ext2")
        os.execute("truncate -s 65536 " .. ft)
        cfg = config_for({
            "--flash-drive=label:mt,start:0x80000030000000,length:0x10000,data_filename:"
                .. ft
                .. ",mount:true,user:nobody",
        })
        expect.truthy(cfg.dtb.init:find("mount[^\n]*/mnt/mt"))
        expect.truthy(cfg.dtb.init:find("chown nobody"))

        -- mount:false: dtb.init has no mount command for that drive
        cfg = config_for({
            "--flash-drive=label:mf,start:0x80000040000000,length:0x10000,data_filename:" .. ft .. ",mount:false",
        })
        expect.truthy(not cfg.dtb.init:find("/mnt/mf"))

        -- mke2fs without data_filename: mke2fs command appears in dtb.init
        cfg = config_for({
            "--flash-drive=label:mk,start:0x80000050000000,length:0x100000,mke2fs",
        })
        expect.truthy(cfg.dtb.init:find("mke2fs"))

        -- Repeated label:root updates the existing root entry; read_only also
        -- rewrites "rw" -> "ro" in bootargs.
        -- data_filename and length must be provided: the --flash-drive handler sets
        -- data_filename="" for unspecified keys, which would overwrite the default.
        cfg = config_for({ "--flash-drive=label:root,data_filename:" .. flash_tmp .. ",length:0x10000,read_only" })
        for _, fd in ipairs(cfg.flash_drive) do
            if fd.label == "root" then
                expect.truthy(fd.read_only)
            end
        end
        expect.truthy(not cfg.dtb.bootargs:find("pmem0 rw"))

        -- override_bool fix: explicit read_only:false after read_only:true must clear the flag.
        -- If override_bool were broken (the "a and b or c" form), false wouldn't stick,
        -- and bootargs would be rewritten to "ro".
        cfg = config_for({
            "--flash-drive=label:root,read_only",
            "--flash-drive=label:root,read_only:false",
        })
        expect.truthy(cfg.dtb.bootargs:find("pmem0 rw"))
        for _, fd in ipairs(cfg.flash_drive) do
            if fd.label == "root" then
                expect.truthy(not fd.read_only)
            end
        end

        -- backing_store.shared explicit false via override_bool.
        local fs_tmp = scratch_path(".ext2")
        os.execute("truncate -s 65536 " .. fs_tmp)
        cfg = config_for({
            "--flash-drive=label:stest,start:0x80000090000000,length:0x10000,data_filename:"
                .. fs_tmp
                .. ",shared:true",
            "--flash-drive=label:stest,shared:false",
        })
        local stest_fd
        for _, fd in ipairs(cfg.flash_drive) do
            if fd.label == "stest" then
                stest_fd = fd
                break
            end
        end
        expect.truthy(stest_fd and stest_fd.backing_store.shared == false)

        -- Filename preserved: a partial re-invocation (no data_filename) must not stomp
        -- the backing_store.data_filename set in the first invocation.
        -- set_empty_omitted_filenames runs at assembly time, so the nil from the second
        -- invocation must not overwrite the value from the first.
        local fk_tmp = scratch_path(".ext2")
        os.execute("truncate -s 65536 " .. fk_tmp)
        cfg = config_for({
            "--flash-drive=label:keep,start:0x800000a0000000,length:0x10000,data_filename:" .. fk_tmp,
            "--flash-drive=label:keep,read_only",
        })
        local keep_fd
        for _, fd in ipairs(cfg.flash_drive) do
            if fd.label == "keep" then
                keep_fd = fd
                break
            end
        end
        expect.truthy(keep_fd and keep_fd.backing_store.data_filename ~= "")

        -- Unlabeled flash-drive with data_filename: exercises the "no label" branch
        -- of the default-mount logic (mount defaults to false).
        cfg = config_for({
            "--flash-drive=start:0x80000060000000,length:0x10000,data_filename:" .. ft,
        })
        expect.truthy(#cfg.flash_drive >= 2)

        -- Unlabeled flash-drive with mount:true: also resolves to mount=false.
        cfg = config_for({ "--flash-drive=start:0x80000070000000,length:0x10000,mount:true" })
        expect.truthy(#cfg.flash_drive >= 2)

        -- Flash-drive with no data_filename and no mke2fs: mount=false, no init
        -- script entry generated.
        cfg = config_for({
            "--flash-drive=label:empty,start:0x80000080000000,length:0x10000,mke2fs:false",
        })
        expect.truthy(not cfg.dtb.init:find("/mnt/empty"))

        -- --hash-tree: hash_function and phtc_size variations
        cfg = config_for({ "--hash-tree=hash_function:sha256" })
        expect.equal(cfg.hash_tree.hash_function, "sha256")

        cfg = config_for({ "--hash-tree=hash_function:keccak256" })
        expect.equal(cfg.hash_tree.hash_function, "keccak256")
    end)

    -- -------------------------------------------------------------------------
    -- NVRAM options
    --
    -- What: --nvram with start/length, read_only, and user sub-options.
    -- How:  config_for() each variant; assert cfg.nvram[1] address fields
    --       for the basic case, and check cfg.dtb.init for the chmod 0444
    --       command (read_only) and busybox chown command (user).
    -- -------------------------------------------------------------------------
    it("nvram options", function()
        -- Basic NVRAM entry
        local cfg = config_for({
            "--nvram=label:n1,start:0x70000000,length:0x1000",
        })
        expect.truthy(cfg.nvram and cfg.nvram[1])
        expect.equal(cfg.nvram[1].start, 0x70000000)
        expect.equal(cfg.nvram[1].length, 0x1000)

        -- read_only: triggers chmod 0444 in dtb.init
        cfg = config_for({
            "--nvram=label:n2,start:0x70001000,length:0x1000,read_only",
        })
        expect.truthy(cfg.dtb.init:find("chmod 0444"))

        -- user: triggers chown in dtb.init
        cfg = config_for({
            "--nvram=label:n3,start:0x70002000,length:0x1000,user:nobody",
        })
        expect.truthy(cfg.dtb.init:find("busybox chown nobody"))

        -- Repeated --nvram with same label updates the existing entry (one entry, user merged in).
        cfg = config_for({
            "--nvram=label:shared,start:0x70010000,length:0x1000",
            "--nvram=label:shared,user:nobody",
        })
        local shared_count = 0
        for _, n in ipairs(cfg.nvram) do
            if n.label == "shared" then
                shared_count = shared_count + 1
            end
        end
        expect.equal(shared_count, 1)

        -- Accept-list: --nvram rejects keys that belong only to --flash-drive.
        run_fail({
            "--nvram=label:x,start:0x70003000,length:0x1000,mount:true",
            "--max-mcycle=0",
            "--no-init-splash",
            "--quiet",
        }, nil)
        run_fail(
            { "--nvram=label:x,start:0x70004000,length:0x1000,mke2fs", "--max-mcycle=0", "--no-init-splash", "--quiet" },
            nil
        )

        -- override_bool fix: read_only:false after read_only must clear the flag;
        -- chmod 0444 must not appear for that NVRAM.
        cfg = config_for({
            "--nvram=label:toggle,start:0x70005000,length:0x1000,read_only",
            "--nvram=label:toggle,read_only:false",
        })
        expect.truthy(not cfg.dtb.init:find("chmod 0444"))
    end)

    -- -------------------------------------------------------------------------
    -- NVRAM end-to-end
    --
    -- What: Boot the guest with a labeled --nvram backed by a host file
    --       (create,shared,user:dapp), write 8 big-endian bytes to it from
    --       inside the machine via `writebe64 | writemmap <label> 0 8`,
    --       then `yield manual rx-accepted 0` to break out of the run loop
    --       cleanly (so the machine destructor flushes the shared mapping),
    --       read the host file back, and assert the value round-trips.
    -- How:  run_ok() the CLI with a single command string after `--`; open
    --       the backing file in-process and unpack big-endian u64.
    -- -------------------------------------------------------------------------
    it("nvram end-to-end write and readback", function()
        local ram_bin = scratch_path(".bin")
        run_ok({
            "--nvram=start:0x90000000000000,length:0x1000,label:ramtest,"
                .. "data_filename:"
                .. ram_bin
                .. ",create,shared,user:dapp",
            "--max-mcycle=2000000000",
            "--no-init-splash",
            --"--quiet",
            "--",
            "writebe64 0xcafebabe | writemmap ramtest 0 8 && yield manual rx-accepted 0",
        })
        local f <close> = assert(io.open(ram_bin, "rb"))
        expect.equal(string.unpack(">I8", f:read(8)), 0xcafebabe)
    end)

    -- -------------------------------------------------------------------------
    -- HTIF yield masks and console-getchar flags
    --
    -- What: --no-htif-yield-manual, --no-htif-yield-automatic, --unreproducible,
    --       -i, and --htif-console-getchar.
    -- How:  config_for() each flag; assert the corresponding bitmask is clear
    --       or set in cfg.processor.registers.htif.iyield / .iconsole, and
    --       that iunrep is set for --unreproducible.
    -- -------------------------------------------------------------------------
    it("htif yield options", function()
        -- --no-htif-yield-manual
        local cfg = config_for({ "--no-htif-yield-manual" })
        expect.equal(cfg.processor.registers.htif.iyield & cartesi.HTIF_YIELD_CMD_MANUAL_MASK, 0)

        -- --no-htif-yield-automatic
        cfg = config_for({ "--no-htif-yield-automatic" })
        expect.equal(cfg.processor.registers.htif.iyield & cartesi.HTIF_YIELD_CMD_AUTOMATIC_MASK, 0)

        -- --unreproducible
        cfg = config_for({ "--unreproducible" })
        expect.equal(cfg.processor.registers.iunrep, 1)

        -- -i / --htif-console-getchar (redirect input to avoid TTY requirement)
        cfg = config_for({ "--console-io=input_source:from_null", "-i" })
        expect.truthy((cfg.processor.registers.htif.iconsole & cartesi.HTIF_CONSOLE_CMD_GETCHAR_MASK) ~= 0)

        cfg = config_for({ "--console-io=input_source:from_null", "--htif-console-getchar" })
        expect.truthy((cfg.processor.registers.htif.iconsole & cartesi.HTIF_CONSOLE_CMD_GETCHAR_MASK) ~= 0)
    end)

    -- -------------------------------------------------------------------------
    -- VirtIO and network options
    --
    -- What: --virtio-9p, --virtio-console, --virtio-net (user and tuntap),
    --       --network, --port-forward (TCP and full IPv4+UDP form), --volume,
    --       and -it.
    -- How:  config_for() each option; scan cfg.virtio for the expected entry
    --       type and verify sub-fields (tag, host_directory, host_port,
    --       guest_port, is_udp, iface).  The TUN/TAP case is skipped on
    --       Mac OS where that device type is not supported.
    -- -------------------------------------------------------------------------
    it("virtio network options", function()
        -- --virtio-9p
        local cfg = config_for({ "--virtio-9p=mytag:/tmp" })
        expect.truthy(cfg.virtio and #cfg.virtio > 0)
        local found_p9fs
        for _, v in ipairs(cfg.virtio) do
            if v.type == "p9fs" and v.tag == "mytag" then
                found_p9fs = v
                break
            end
        end
        expect.truthy(found_p9fs)
        expect.equal(found_p9fs.host_directory, "/tmp")
        expect.equal(cfg.processor.registers.iunrep, 1)

        -- --virtio-console
        cfg = config_for({ "--console-io=input_source:from_null", "--virtio-console" })
        local found_console
        for _, v in ipairs(cfg.virtio) do
            if v.type == "console" then
                found_console = true
                break
            end
        end
        expect.truthy(found_console)

        -- --virtio-net=user
        cfg = config_for({ "--virtio-net=user" })
        local found_net
        for _, v in ipairs(cfg.virtio) do
            if v.type == "net-user" then
                found_net = true
                break
            end
        end
        expect.truthy(found_net)

        -- --network implies virtio-net=user
        cfg = config_for({ "--network" })
        found_net = false
        for _, v in ipairs(cfg.virtio) do
            if v.type == "net-user" then
                found_net = true
                break
            end
        end
        expect.truthy(found_net)

        -- --port-forward (requires --virtio-net=user or --network)
        cfg = config_for({ "--network", "--port-forward=18080:80" })
        local net_entry
        for _, v in ipairs(cfg.virtio) do
            if v.type == "net-user" then
                net_entry = v
                break
            end
        end
        expect.truthy(net_entry and net_entry.hostfwd and #net_entry.hostfwd > 0)
        expect.equal(net_entry.hostfwd[1].host_port, 18080)
        expect.equal(net_entry.hostfwd[1].guest_port, 80)

        -- --volume (implies p9fs + sync-init-date + iunrep)
        cfg = config_for({ "--volume=/tmp:/mnt" })
        found_p9fs = false
        for _, v in ipairs(cfg.virtio) do
            if v.type == "p9fs" then
                found_p9fs = true
                break
            end
        end
        expect.truthy(found_p9fs)
        expect.equal(cfg.processor.registers.iunrep, 1)

        -- -it: virtio-console + sync-init-date
        cfg = config_for({ "--console-io=input_source:from_null", "-it" })
        found_console = false
        for _, v in ipairs(cfg.virtio) do
            if v.type == "console" then
                found_console = true
                break
            end
        end
        expect.truthy(found_console)
        expect.equal(cfg.processor.registers.iunrep, 1)

        -- --port-forward with explicit IPv4 host/guest addresses and UDP protocol
        cfg = config_for({
            "--network",
            "--port-forward=127.0.0.1:10.0.2.15:18081:81:udp",
        })
        local net_entry2
        for _, v in ipairs(cfg.virtio) do
            if v.type == "net-user" then
                net_entry2 = v
            end
        end
        expect.truthy(net_entry2 and net_entry2.hostfwd and net_entry2.hostfwd[1])
        expect.equal(net_entry2.hostfwd[1].is_udp, true)

        -- --virtio-net=<iface>: TUN/TAP interface (Linux only; skipped when /dev/net/tun is absent)
        if cartesi.PLATFORM ~= "Mac OS" and io.open("/dev/net/tun", "r") then
            cfg = config_for({ "--virtio-net=tap0" })
            local found_tap
            for _, v in ipairs(cfg.virtio) do
                if v.type == "net-tuntap" then
                    found_tap = v
                end
            end
            expect.truthy(found_tap)
        end
    end)

    -- -------------------------------------------------------------------------
    -- Console I/O options
    --
    -- What: --console-io sub-options: output_destination, output_flush_mode,
    --       output_buffer_size, tty_cols, tty_rows, input_source, output_fd,
    --       output_filename, input_fd, and input_filename.
    -- How:  run_ok() each variant.  input_fd and input_filename require
    --       --unreproducible because any non-null stdin source is forbidden in
    --       reproducible mode.
    -- -------------------------------------------------------------------------
    it("console IO options", function()
        -- --console-io combined options
        run_ok({
            "--console-io=output_destination:to_stderr,output_flush_mode:every_line,"
                .. "output_buffer_size:1024,tty_cols:80,tty_rows:24,input_source:from_null",
            "--max-mcycle=0",
            "--no-init-splash",
            "--quiet",
        })

        -- output_fd: routes console output to a file descriptor by number
        run_ok({ "--console-io=output_fd:2", "--max-mcycle=0", "--no-init-splash", "--quiet" })

        -- output_filename: routes console output to a named file
        run_ok({
            "--console-io=output_filename:" .. scratch_path(".out"),
            "--max-mcycle=0",
            "--no-init-splash",
            "--quiet",
        })

        -- input_fd: reads console input from a file descriptor by number (requires unreproducible mode)
        run_ok({ "--unreproducible", "--console-io=input_fd:0", "--max-mcycle=0", "--no-init-splash", "--quiet" })

        -- input_filename: reads console input from a named file (requires unreproducible mode)
        run_ok({
            "--unreproducible",
            "--console-io=input_filename:/dev/null",
            "--max-mcycle=0",
            "--no-init-splash",
            "--quiet",
        })
    end)

    -- -------------------------------------------------------------------------
    -- Execution / uarch runtime options
    --
    -- What: Runtime flags that affect execution but are not reflected in the
    --       initial machine config: --concurrency, --uarch-ram-image,
    --       --max-mcycle, --skip-version-check, and --no-reserve.
    -- How:  run_ok() each flag to confirm it parses without error.
    --       --uarch-ram-image is also checked with config_for() when the
    --       image file is present on disk.
    -- -------------------------------------------------------------------------
    it("execution options", function()
        -- --concurrency (runtime setting, not in initial config; just verify it parses)
        run_ok({ "--concurrency=update_hash_tree:2", "--max-mcycle=0", "--no-init-splash", "--quiet" })

        -- --uarch-ram-image
        -- The standard uarch-ram.bin lives next to linux.bin; if present, test it.
        local uarch_bin = images_path .. "uarch-ram.bin"
        local f = io.open(uarch_bin, "r")
        if f then
            f:close()
            local cfg = config_for({ "--uarch-ram-image=" .. uarch_bin })
            expect.truthy(cfg.uarch.ram.backing_store.data_filename:find("uarch%-ram%.bin"))
        end

        -- --max-mcycle (runtime, but confirm the flag parses without crashing)
        run_ok({ "--max-mcycle=0", "--no-init-splash", "--quiet" })
        run_ok({ "--max-mcycle=1", "--no-init-splash", "--quiet" })

        -- --skip-version-check and --no-reserve parse without error
        run_ok({ "--skip-version-check", "--max-mcycle=0", "--no-init-splash", "--quiet" })
        run_ok({ "--no-reserve", "--max-mcycle=0", "--no-init-splash", "--quiet" })
    end)

    -- -------------------------------------------------------------------------
    -- Hashing and proof options
    --
    -- What: --initial-hash, --final-hash, --periodic-hashes (two-arg and
    --       single-arg forms), --initial-proof, --final-proof,
    --       --dense-uarch-hashes, and --dump-address-ranges.
    -- How:  run_ok() each flag; regex-match 64-hex-digit lines in stderr to
    --       count hash emissions; open proof output files and assert they are
    --       non-empty.
    -- -------------------------------------------------------------------------
    it("hashing options", function()
        -- --initial-hash and --final-hash emit hashes to stderr as "<mcycle>: <hex64>"
        local _, err = run_ok({ "--initial-hash", "--final-hash", "--max-mcycle=0", "--no-init-splash", "--quiet" })
        local hash_count = 0
        for line in err:gmatch("[^\n]+") do
            if line:match("^%d+: [0-9a-f]+$") and #line:match("[0-9a-f]+$") == 64 then
                hash_count = hash_count + 1
            end
        end
        expect.truthy(hash_count >= 2)

        -- --periodic-hashes
        _, err = run_ok({ "--periodic-hashes=1,0", "--max-mcycle=2", "--no-init-splash", "--quiet" })
        hash_count = 0
        for line in err:gmatch("[^\n]+") do
            if line:match("^%d+: [0-9a-f]+$") and #line:match("[0-9a-f]+$") == 64 then
                hash_count = hash_count + 1
            end
        end
        expect.truthy(hash_count >= 1)

        -- --initial-proof / --final-proof written to files
        local proof_file = scratch_path(".json")
        run_ok({
            "--initial-proof=address:0x80000000,log2_size:12,filename:" .. proof_file,
            "--max-mcycle=0",
            "--no-init-splash",
            "--quiet",
        })
        local pf = io.open(proof_file, "r")
        assert(pf, "--initial-proof: output file not created")
        local proof_data = pf:read("*a")
        pf:close()
        expect.truthy(#proof_data > 10)

        -- --final-proof written to a file
        local final_proof_file = scratch_path(".json")
        run_ok({
            "--final-proof=address:0x80000000,log2_size:12,filename:" .. final_proof_file,
            "--max-mcycle=0",
            "--no-init-splash",
            "--quiet",
        })
        local fpf = io.open(final_proof_file, "r")
        assert(fpf, "--final-proof: output file not created")
        local fpdata = fpf:read("*a")
        fpf:close()
        expect.truthy(#fpdata > 10)

        -- --periodic-hashes=N single-argument form (no start offset, implies start=N)
        run_ok({ "--periodic-hashes=10", "--max-mcycle=0", "--no-init-splash", "--quiet" })

        -- --periodic-hashes=<period>,<start> with start > 0: exercises the
        -- next_hash_mcycle = periodic_hashes_start branch.
        run_ok({ "--periodic-hashes=10,5", "--max-mcycle=0", "--no-init-splash", "--quiet" })

        -- --dense-uarch-hashes=N single-argument form
        run_ok({ "--dense-uarch-hashes=1", "--max-mcycle=0", "--no-init-splash", "--quiet" })

        -- --dump-address-ranges=<dir>: writes one <start>--<length>.bin per address range under <dir>.
        -- Use the scratch area because the installed tests cwd may be read-only.
        local dump_dir = scratch_path(".dump")
        run_ok({ "--dump-address-ranges=" .. dump_dir, "--max-mcycle=0", "--no-init-splash", "--quiet" })
        local cfg = config_for({})
        local m <close> = cartesi.machine(cfg)
        for _, v in ipairs(m:get_address_ranges()) do
            local filename = dump_dir .. "/" .. string.format("%016x--%016x.bin", v.start, v.length)
            local f = io.open(filename, "r")
            assert(f, "--dump-address-ranges: expected file not created: " .. filename)
            f:close()
            assert(os.remove(filename))
        end
    end)

    -- -------------------------------------------------------------------------
    -- Persistence round-trip options
    --
    -- What: --store-config / --load-config, --store-json-config /
    --       --load-json-config (including bare to-stdout forms), --store,
    --       --load, --store=<dir>/%h (hash-substituted path), --create,
    --       --store sharing:all, --load sharing:all, and --load clone:<src>.
    -- How:  Each store flag is run, then the produced file or directory is
    --       read back (via dofile, config_for, or filesystem existence checks)
    --       and key field values are asserted to survive the round-trip.
    -- -------------------------------------------------------------------------
    it("persistence: --store, --load, --create", function()
        -- --store-config to file and --load-config round-trip
        local cfg_file = scratch_path(".lua")
        run_ok({
            "--hash-tree=hash_function:sha256",
            "--ram-length=64Mi",
            "--max-mcycle=0",
            "--no-init-splash",
            "--quiet",
            "--store-config=" .. cfg_file,
        })
        local cfg = dofile(cfg_file)
        expect.equal(cfg.hash_tree.hash_function, "sha256")
        expect.equal(cfg.ram.length, (64 * 1024 * 1024))

        -- --load-config restores the saved config
        local cfg2 = config_for({ "--load-config=" .. cfg_file })
        expect.equal(cfg2.hash_tree.hash_function, "sha256")
        expect.equal(cfg2.ram.length, (64 * 1024 * 1024))

        -- --store-json-config to file and --load-json-config round-trip
        local json_file = scratch_path(".json")
        run_ok({
            "--hash-tree=hash_function:sha256",
            "--max-mcycle=0",
            "--no-init-splash",
            "--quiet",
            "--store-json-config=" .. json_file,
        })
        local jf = io.open(json_file, "r")
        assert(jf, "--store-json-config: file not created")
        local json_data = jf:read("*a")
        jf:close()
        expect.truthy(json_data:find('"sha256"'))

        local cfg3 = config_for({ "--load-json-config=" .. json_file })
        expect.equal(cfg3.hash_tree.hash_function, "sha256")

        -- --store-config to stdout (bare form)
        local stdout = run_ok({ "--max-mcycle=0", "--no-init-splash", "--quiet", "--store-config" })
        expect.truthy(stdout:find("return"))

        -- --store-json-config to stdout (bare form)
        stdout = run_ok({ "--max-mcycle=0", "--no-init-splash", "--quiet", "--store-json-config" })
        expect.truthy(stdout:find('"ram"'))

        -- --store=<dir>: machine stored at that path
        local store_dir = scratch_path(".store")
        run_ok({ "--store=" .. store_dir, "--max-mcycle=0", "--no-init-splash", "--quiet" })
        assert(os.execute("test -d " .. store_dir), "--store: directory not created")

        -- --load=<dir>: load the stored machine back and verify config
        local cfg4 = config_for({ "--load=" .. store_dir })
        expect.truthy(cfg4.ram ~= nil)

        -- --store=<dir>/%h: hash-substituted path
        local hash_store_base = scratch_path(".hashstore")
        os.execute("mkdir -p " .. hash_store_base)
        run_ok({
            "--store=" .. hash_store_base .. "/%h",
            "--max-mcycle=0",
            "--no-init-splash",
            "--quiet",
        })
        -- At least one subdirectory should exist inside hash_store_base
        local entries = io.popen("ls -1 " .. hash_store_base .. " 2>/dev/null")
        local first = entries and entries:read("*l")
        if entries then
            entries:close()
        end
        expect.truthy(first and #first == 64)

        -- --create=<dir>: create machine store
        local create_dir = scratch_path(".create")
        run_ok({ "--create=" .. create_dir, "--max-mcycle=0", "--no-init-splash", "--quiet" })
        assert(os.execute("test -d " .. create_dir), "--create: directory not created")

        -- --store=<dir>,sharing:all: store with memory sharing enabled
        local shared_store = scratch_path(".shared")
        run_ok({
            "--store=" .. shared_store .. ",sharing:all",
            "--max-mcycle=0",
            "--no-init-splash",
            "--quiet",
        })
        assert(os.execute("test -d " .. shared_store), "--store sharing:all: directory not created")

        -- --load=<dir>,sharing:all: load with memory sharing
        local cfg_sh = config_for({ "--load=" .. shared_store .. ",sharing:all" })
        expect.truthy(cfg_sh.ram ~= nil)

        -- --load=<dir>,clone:<src>,sharing:all: clone from src to dir, then load from dir
        local clone_dst = scratch_path(".clone")
        local cfg_cl = config_for({
            "--load=" .. clone_dst .. ",clone:" .. shared_store .. ",sharing:all",
        })
        expect.truthy(cfg_cl.ram ~= nil)
        assert(os.execute("test -d " .. clone_dst), "--load clone: clone directory not created")
    end)

    -- -------------------------------------------------------------------------
    -- Splash banner injection
    --
    -- What: When --no-init-splash is absent, init_splash injects the CARTESI
    --       ASCII art banner into dtb.init.
    -- How:  --store-config without --no-init-splash; assert cfg.dtb.init
    --       contains "CARTESI".
    -- -------------------------------------------------------------------------
    it("splash and init options", function()
        local tmp = scratch_path(".lua")
        run_ok({
            "--store-config=" .. tmp,
            "--max-mcycle=0",
            "--quiet",
            -- NOTE: no --no-init-splash, so the banner is injected
        })
        local cfg = dofile(tmp)
        expect.truthy(cfg.dtb.init:find("CARTESI"))
    end)

    -- -------------------------------------------------------------------------
    -- Guest init and entrypoint options
    --
    -- What: Options that append to dtb.init or dtb.entrypoint: -u/--user,
    --       -e/--env, -w/--workdir, -h/--hostname, --append-init,
    --       --append-init-file, --append-entrypoint, --append-entrypoint-file.
    -- How:  config_for() each flag; string-match the resulting dtb.init or
    --       dtb.entrypoint for the expected text.  The -h=val case is a
    --       regression guard: -h alone is --help, but -h=val must set hostname.
    -- -------------------------------------------------------------------------
    it("guest init options", function()
        -- -u / --user
        local cfg = config_for({ "-u=nobody" })
        expect.truthy(cfg.dtb.init:find("USER=nobody"))

        cfg = config_for({ "--user=testuser" })
        expect.truthy(cfg.dtb.init:find("USER=testuser"))

        -- -e / --env
        cfg = config_for({ "-e=MYVAR=hello" })
        expect.truthy(cfg.dtb.init:find("export MYVAR=hello"))

        cfg = config_for({ "--env=OTHER=world" })
        expect.truthy(cfg.dtb.init:find("export OTHER=world"))

        -- -w / --workdir
        cfg = config_for({ "-w=/tmp" })
        expect.truthy(cfg.dtb.init:find("WORKDIR=/tmp"))

        cfg = config_for({ "--workdir=/var" })
        expect.truthy(cfg.dtb.init:find("WORKDIR=/var"))

        -- -h / --hostname (regression: -h=val must not match -h help shorthand)
        cfg = config_for({ "-h=myhost" })
        expect.truthy(cfg.dtb.init:find("hostname myhost"))

        cfg = config_for({ "--hostname=anotherhost" })
        expect.truthy(cfg.dtb.init:find("hostname anotherhost"))

        -- --append-init
        cfg = config_for({ "--append-init=echo hello" })
        expect.truthy(cfg.dtb.init:find("echo hello"))

        -- --append-init-file
        local init_file = scratch_path(".sh")
        local f = assert(io.open(init_file, "w"))
        f:write("echo world\n")
        f:close()
        cfg = config_for({ "--append-init-file=" .. init_file })
        expect.truthy(cfg.dtb.init:find("echo world"))

        -- --append-entrypoint
        cfg = config_for({ "--append-entrypoint=/bin/echo hi" })
        expect.truthy(cfg.dtb.entrypoint:find("/bin/echo hi"))

        -- --append-entrypoint-file
        local ep_file = scratch_path(".sh")
        f = assert(io.open(ep_file, "w"))
        f:write("/bin/true\n")
        f:close()
        cfg = config_for({ "--append-entrypoint-file=" .. ep_file })
        expect.truthy(cfg.dtb.entrypoint:find("/bin/true"))
    end)

    -- -------------------------------------------------------------------------
    -- Positional arguments (command after --)
    --
    -- What: Positional argument dispatch sets dtb.entrypoint, both when
    --       preceded by an explicit -- separator and when the first non-option
    --       token appears directly.
    -- How:  config_for() with the positional form; assert a substring of
    --       cfg.dtb.entrypoint.
    -- -------------------------------------------------------------------------
    it("positional arguments", function()
        -- "-- <cmd>" puts cmd into entrypoint
        local cfg = config_for({ "--", "/bin/echo", "hello" })
        expect.truthy(cfg.dtb.entrypoint:find("/bin/echo"))

        -- First non-option token (no --) also triggers command mode
        cfg = config_for({ "/bin/true" })
        expect.truthy(cfg.dtb.entrypoint:find("/bin/true"))
    end)

    -- -------------------------------------------------------------------------
    -- CMIO buffer backing-store options
    --
    -- What: --cmio-rx-buffer and --cmio-tx-buffer with shared,data_filename:.
    -- How:  Create the backing files with truncate, then config_for() each
    --       flag and assert cfg.cmio.{rx,tx}_buffer.backing_store.shared is
    --       true.
    -- -------------------------------------------------------------------------
    it("cmio options", function()
        local rx_tmp = scratch_path(".rx")
        os.execute("truncate -s 2097152 " .. rx_tmp)
        local cfg = config_for({ "--cmio-rx-buffer=shared,data_filename:" .. rx_tmp })
        expect.truthy(cfg.cmio and cfg.cmio.rx_buffer)
        expect.equal(cfg.cmio.rx_buffer.backing_store.shared, true)

        local tx_tmp = scratch_path(".tx")
        os.execute("truncate -s 2097152 " .. tx_tmp)
        cfg = config_for({ "--cmio-tx-buffer=shared,data_filename:" .. tx_tmp })
        expect.truthy(cfg.cmio and cfg.cmio.tx_buffer)
        expect.equal(cfg.cmio.tx_buffer.backing_store.shared, true)
    end)

    -- -------------------------------------------------------------------------
    -- CMIO advance/inspect option parsing (pre-run, no guest boot)
    --
    -- What: --cmio-advance-state and --cmio-inspect-state option-string parsing,
    --       including both the key:value form and the bare --cmio-inspect-state.
    -- How:  run_ok() with --no-rollback and --max-mcycle=0 so the option parser
    --       and HTIF config check run but the guest is never booted.
    -- -------------------------------------------------------------------------
    it("cmio advance/inspect options", function()
        -- --cmio-advance-state: option parses and machine runs through check_cmio_htif_config
        run_ok({
            "--cmio-advance-state=input:inp-%i.bin,input_index_begin:0,input_index_end:0,"
                .. "report:rep-%i-%o.bin,output:out-%i-%o.bin",
            "--no-rollback",
            "--max-mcycle=0",
            "--no-init-splash",
            "--quiet",
        })

        -- --cmio-inspect-state=<opts>
        run_ok({
            "--cmio-inspect-state=query:q.bin,report:qrep-%o.bin",
            "--no-rollback",
            "--max-mcycle=0",
            "--no-init-splash",
            "--quiet",
        })

        -- bare --cmio-inspect-state (no arguments)
        run_ok({
            "--cmio-inspect-state",
            "--no-rollback",
            "--max-mcycle=0",
            "--no-init-splash",
            "--quiet",
        })
    end)

    -- -------------------------------------------------------------------------
    -- Remote / JSON-RPC options
    --
    -- What: --remote-address, --remote-health-check, --remote-spawn,
    --       --remote-shutdown, --no-remote-create, --no-remote-destroy, and
    --       --no-rollback.
    -- How:  Each case spawns a real server with jsonrpc.spawn_server(), runs
    --       the CLI against it, and asserts the expected rc or config fields.
    --       --no-remote-create is verified by first creating a machine then
    --       reconnecting without re-creating.
    -- -------------------------------------------------------------------------
    it("remote machine options", function()
        local jsonrpc = require("cartesi.jsonrpc")

        -- --remote-health-check: connect to a live server and check health
        do
            local srv <close>, address = jsonrpc.spawn_server()
            assert(srv, "failed to spawn server")
            local rc = run({ "--remote-address=" .. address, "--remote-health-check" })
            expect.equal(rc, 0)
        end

        -- --remote-spawn: spawn and connect in one step (uses address 127.0.0.1:0 for auto-port)
        run_ok({
            "--remote-spawn",
            "--remote-address=127.0.0.1:0",
            "--max-mcycle=0",
            "--no-init-splash",
            "--quiet",
        })

        -- --remote-address with config inspection: hash_function propagates to remote machine
        do
            local server <close>, address = jsonrpc.spawn_server()
            server:set_cleanup_call(jsonrpc.NOTHING) -- let the CLI subprocess shut it down
            local cfg = config_for({
                "--remote-address=" .. address,
                "--hash-tree=hash_function:sha256",
            })
            expect.equal(cfg.hash_tree.hash_function, "sha256")
        end

        -- --remote-shutdown: connect, create machine, shutdown server
        do
            local server <close>, address = jsonrpc.spawn_server()
            server:set_cleanup_call(jsonrpc.NOTHING)
            run_ok({
                "--remote-address=" .. address,
                "--remote-shutdown",
                "--max-mcycle=0",
                "--no-init-splash",
                "--quiet",
            })
        end

        -- --no-remote-create / --no-remote-destroy: just check they parse without crashing
        -- (behavioral verification requires a pre-existing machine on the server)
        do
            local srv <close>, address = jsonrpc.spawn_server()
            assert(srv, "failed to spawn server")
            -- Create a machine on the server first, then reconnect with --no-remote-create
            run_ok({
                "--remote-address=" .. address,
                "--max-mcycle=0",
                "--no-init-splash",
                "--quiet",
                "--no-remote-destroy",
            })
            run_ok({
                "--remote-address=" .. address,
                "--no-remote-create",
                "--no-remote-destroy",
                "--max-mcycle=0",
                "--no-init-splash",
                "--quiet",
            })
        end

        -- --no-rollback parses without error
        run_ok({ "--no-rollback", "--max-mcycle=0", "--no-init-splash", "--quiet" })
    end)

    -- -------------------------------------------------------------------------
    -- --replace-memory-range
    --
    -- What: --replace-memory-range overlays a flash drive region with data
    --       from a separate file after machine creation.
    -- How:  Create a flash image and a replacement image with truncate; run_ok()
    --       with both --flash-drive=... and --replace-memory-range=... targeting
    --       the same address range.
    -- -------------------------------------------------------------------------
    it("replace memory range options", function()
        local flash_file = scratch_path(".ext2")
        os.execute("truncate -s 65536 " .. flash_file)
        local repl_file = scratch_path(".bin")
        os.execute("truncate -s 65536 " .. repl_file)
        run_ok({
            "--flash-drive=label:rep,start:0x80000060000000,length:0x10000,data_filename:" .. flash_file,
            "--replace-memory-range=start:0x80000060000000,length:0x10000,data_filename:" .. repl_file,
            "--max-mcycle=0",
            "--no-init-splash",
            "--quiet",
        })

        -- Accept-list: --replace-memory-range rejects keys that belong only to --flash-drive
        -- or --nvram, plus create/truncate (which machine_address_ranges::replace does not wire
        -- to prepare_ar_backing_store, so they would be silently ignored during replace).
        for _, bad in ipairs({ "user:nobody", "create", "truncate" }) do
            run_fail({
                "--replace-memory-range=start:0x80000060000000,length:0x10000," .. bad,
                "--max-mcycle=0",
                "--no-init-splash",
                "--quiet",
            }, nil)
        end
    end)

    -- -------------------------------------------------------------------------
    -- replace_memory_range honors the shared flag at runtime
    --
    -- What: verify that --replace-memory-range's `shared` flag actually
    --       controls whether guest writes propagate to the host backing
    --       file, not just that the flag is accepted by the CLI.
    -- How:  Build a template with a labeled NVRAM and an entrypoint that
    --       does writemmap + manual yield (twice, though only the first
    --       executes because manual yield breaks the run loop).  Store
    --       the template at mcycle=0 so each load starts from the same
    --       point.  Load + --replace-memory-range with `shared`: writes
    --       must reach the host file.  Load + --replace-memory-range
    --       without `shared`: writes go to a private COW mapping and must
    --       NOT reach the host file.
    -- -------------------------------------------------------------------------
    it("replace_memory_range shared flag controls write propagation", function()
        local template_dir = scratch_path("-tmpl")
        run_ok({
            "--nvram=start:0x90000000000000,length:0x1000,label:ramtest,user:dapp",
            "--store=" .. template_dir,
            "--max-mcycle=0",
            "--no-init-splash",
            "--",
            "writebe64 0xdeadbeef | writemmap ramtest 0 8 && "
                .. "yield manual rx-accepted 0 && "
                .. "writebe64 0xcafebabe | writemmap ramtest 0 8 && "
                .. "yield manual rx-accepted 0",
        })

        -- Shared replace: the write before the first yield reaches the host file.
        local shared_file = scratch_path("-shared.bin")
        os.execute("truncate -s 4096 " .. shared_file)
        run_ok({
            "--load=" .. template_dir,
            "--replace-memory-range=label:ramtest,data_filename:" .. shared_file .. ",shared",
            "--max-mcycle=2000000000",
            "--no-init-splash",
        })
        do
            local f <close> = assert(io.open(shared_file, "rb"))
            expect.equal(string.unpack(">I8", f:read(8)), 0xdeadbeef)
        end

        -- Non-shared replace: the write lands in a private COW mapping and does
        -- not reach the host file, which stays zero-initialized.
        local private_file = scratch_path("-private.bin")
        os.execute("truncate -s 4096 " .. private_file)
        run_ok({
            "--load=" .. template_dir,
            "--replace-memory-range=label:ramtest,data_filename:" .. private_file,
            "--max-mcycle=2000000000",
            "--no-init-splash",
        })
        do
            local f <close> = assert(io.open(private_file, "rb"))
            expect.equal(string.unpack(">I8", f:read(8)), 0)
        end
    end)

    -- -------------------------------------------------------------------------
    -- Cross-kind label collision
    --
    -- What: flash drives and NVRAMs share a single label namespace enforced by
    --       the machine constructor; using the same label for both must fail.
    -- How:  run_fail() with a --flash-drive and --nvram that share a label.
    -- -------------------------------------------------------------------------
    it("flash drive and nvram share label namespace", function()
        local flash_tmp = scratch_path(".ext2")
        os.execute("truncate -s 65536 " .. flash_tmp)
        run_fail({
            "--flash-drive=label:collide,start:0x80000020000000,length:0x10000,data_filename:" .. flash_tmp,
            "--nvram=label:collide,start:0x70000000,length:0x1000",
            "--max-mcycle=0",
            "--no-init-splash",
            "--quiet",
        }, nil)
    end)

    -- -------------------------------------------------------------------------
    -- Error paths
    --
    -- What: Expected failure modes: malformed --port-forward, log2_size too
    --       small for --initial-proof, --gdb conflicting with
    --       --periodic-hashes, and --assert-rolling-template failing because
    --       the machine is not a rolling template.
    -- How:  run_fail() each case; where the CLI emits a stable stderr
    --       substring, pass it as the pattern argument.
    -- -------------------------------------------------------------------------
    it("error paths", function()
        -- Malformed --port-forward
        run_fail({ "--network", "--port-forward=not-a-port" }, nil)

        -- log2_size < 3 in --initial-proof
        run_fail({
            "--initial-proof=address:0x80000000,log2_size:2",
            "--max-mcycle=0",
        }, "log2_size must be at least 3")

        -- --gdb conflicts with --periodic-hashes
        run_fail({
            "--gdb=127.0.0.1:19234",
            "--periodic-hashes=100,0",
            "--max-mcycle=0",
            "--no-init-splash",
            "--quiet",
        }, "not supported when debugging")

        -- --assert-rolling-template: exits non-zero when machine is not a rolling template
        run_fail({ "--assert-rolling-template", "--max-mcycle=0", "--no-init-splash", "--quiet" }, nil)

        -- --port-forward with a 3-octet value: matches the pattern [0-9:.]+
        -- but is not a valid IP, port number, or protocol, so handle_port_forward_option
        -- reaches the error() at line 1036.
        -- --virtio-net=user must precede it to satisfy the virtio_net_user_config assert.
        run_fail({
            "--virtio-net=user",
            "--port-forward=1.2.3",
            "--max-mcycle=0",
            "--no-init-splash",
            "--quiet",
        }, "malformed")

        -- Malformed suffixes of options with optional '=' values: the handler
        -- returns false, the catchall rejects "unrecognized option".
        run_fail({ "--remote-forkXXX" }, nil)
        run_fail({ "--store-configXXX" }, nil)
        run_fail({ "--store-json-configXXX" }, nil)

        -- --gdb= (empty value) is rejected; bare --gdb combined with --periodic-hashes
        -- exercises the default-address branch and trips the "not supported when
        -- debugging" assertion before the stub ever listens.
        run_fail({ "--gdb=" }, nil)
        run_fail({
            "--gdb",
            "--periodic-hashes=100,0",
            "--max-mcycle=0",
            "--no-init-splash",
            "--quiet",
        }, "not supported when debugging")
    end)

    -- -------------------------------------------------------------------------
    -- --load-config error paths
    --
    -- What: --load-config reports an error for a syntactically invalid config
    --       file and for a file whose top-level chunk raises at runtime.
    -- How:  Write a bad config file, then run_fail() and assert stderr contains
    --       "Failed to load machine config".  --quiet is omitted because the
    --       CLI silences that message in quiet mode.
    -- -------------------------------------------------------------------------
    it("load config error paths", function()
        -- Syntax error in config file
        local bad = scratch_path(".lua")
        local f = assert(io.open(bad, "w"))
        f:write("return {{{\n")
        f:close()
        run_fail({ "--load-config=" .. bad, "--max-mcycle=0", "--no-init-splash" }, "Failed to load machine config")

        -- Runtime error in config file
        local rt = scratch_path(".lua")
        f = assert(io.open(rt, "w"))
        f:write("error('boom')\n")
        f:close()
        run_fail({ "--load-config=" .. rt, "--max-mcycle=0", "--no-init-splash" }, "Failed to load machine config")
    end)

    -- -------------------------------------------------------------------------
    -- Step-logging and uarch options
    --
    -- What: --log-step, --log-step-uarch, --log-reset-uarch, --max-uarch-cycle,
    --       --auto-reset-uarch, and --dense-uarch-hashes=len,start.
    -- How:  run_ok() each flag; for --log-step also open the output file and
    --       assert it is non-empty to confirm the log was written.
    -- -------------------------------------------------------------------------
    it("log step options", function()
        local log_file = scratch_path(".bin")

        -- --log-step=N,<file>
        run_ok({
            "--log-step=1," .. log_file,
            "--max-mcycle=1",
            "--no-init-splash",
            "--quiet",
        })
        local f = io.open(log_file, "r")
        assert(f, "--log-step: output file not created")
        local data = f:read("*a")
        f:close()
        expect.truthy(#data > 0)

        -- --log-step-uarch
        run_ok({
            "--log-step-uarch",
            "--store-config=" .. scratch_path(".lua"),
            "--max-mcycle=0",
            "--no-init-splash",
            "--quiet",
        })

        -- --log-reset-uarch
        run_ok({
            "--log-reset-uarch",
            "--store-config=" .. scratch_path(".lua"),
            "--max-mcycle=0",
            "--no-init-splash",
            "--quiet",
        })

        -- --max-uarch-cycle
        run_ok({ "--max-uarch-cycle=0", "--max-mcycle=0", "--no-init-splash", "--quiet" })

        -- --auto-reset-uarch
        run_ok({ "--auto-reset-uarch", "--max-mcycle=0", "--no-init-splash", "--quiet" })

        -- --dense-uarch-hashes=<length>,<start>
        run_ok({ "--dense-uarch-hashes=1,0", "--max-mcycle=0", "--no-init-splash", "--quiet" })
    end)

    -- -------------------------------------------------------------------------
    -- Post-run uarch advance path (--max-uarch-cycle, --auto-reset-uarch)
    --
    -- What: --max-uarch-cycle and --auto-reset-uarch exercise the uarch advance
    --       path that runs after the main machine loop.
    -- How:  run_ok() with --max-mcycle=0 so the main loop is bypassed; the
    --       post-loop uarch-run branch is still entered.
    -- -------------------------------------------------------------------------
    it("max uarch cycle runtime", function()
        -- max-uarch-cycle=1 runs one uarch step then stops (machine is still running)
        run_ok({ "--max-uarch-cycle=1", "--max-mcycle=0", "--no-init-splash", "--quiet" })
        -- auto-reset-uarch resets uarch state after the uarch halts
        run_ok({ "--auto-reset-uarch", "--max-uarch-cycle=1000000", "--max-mcycle=0", "--no-init-splash", "--quiet" })
        -- Without --auto-reset-uarch the uarch-halt path prints uCycles instead of resetting.
        run_ok({ "--max-uarch-cycle=1000000", "--max-mcycle=0", "--no-init-splash", "--quiet" })
    end)

    -- -------------------------------------------------------------------------
    -- Interactive mode (-i and -it)
    --
    -- What: -i (HTIF console getchar) and -it (virtio console) dispatch.
    -- How:  run_ok() with --console-io=input_source:from_null so the CLI does
    --       not attempt to bind a TTY.
    -- -------------------------------------------------------------------------
    it("interactive mode", function()
        -- -i: feed EOF; use from_null to avoid TTY requirement
        run_ok({ "--console-io=input_source:from_null", "-i", "--max-mcycle=1", "--no-init-splash", "--quiet" })

        -- -it: virtio console; use from_null to avoid TTY requirement
        run_ok({ "--console-io=input_source:from_null", "-it", "--max-mcycle=1", "--no-init-splash", "--quiet" })
    end)

    -- -------------------------------------------------------------------------
    -- Full-guest rollup flow: advance + inspect with ioctl-echo-loop
    --
    -- What: End-to-end CMIO pipeline with --cmio-advance-state,
    --       --cmio-inspect-state, and --assert-rolling-template using
    --       ioctl-echo-loop from the guest rootfs.
    -- How:  Encode two EvmAdvance inputs with cartesi.evmu.encode_calldata and
    --       write a query file; run the CLI with both CMIO options and
    --       --assert-rolling-template; assert that output, output-hash, and
    --       query-report files are produced.  This boots Linux and exercises
    --       the CMIO save/load helpers, yield dispatch, and the rolling-template
    --       success path.
    -- -------------------------------------------------------------------------
    it("rollup advance and inspect", function()
        local dir = scratch
        write_bin(dir .. "/input-0.bin", encode_advance(0, "hello"))
        write_bin(dir .. "/input-1.bin", encode_advance(1, "world"))
        write_bin(dir .. "/query.bin", "inspect-me")

        run_ok({
            "--cmio-advance-state=input:"
                .. dir
                .. "/input-%i.bin,"
                .. "input_index_begin:0,input_index_end:2,"
                .. "output:"
                .. dir
                .. "/out-%i-%o.bin,"
                .. "report:"
                .. dir
                .. "/rep-%i-%o.bin,"
                .. "output_hashes_root_hash:"
                .. dir
                .. "/outh-%i.bin",
            "--cmio-inspect-state=query:" .. dir .. "/query.bin," .. "report:" .. dir .. "/qrep-%o.bin",
            "--no-rollback",
            "--assert-rolling-template",
            "--max-mcycle=2000000000",
            "--no-init-splash",
            "--quiet",
            "--",
            "ioctl-echo-loop --vouchers=1 --notices=1 --reports=1",
        })

        local voucher_sig = "Voucher(address destination, uint256 value, bytes payload)"
        local out00 = evmu.decode_calldata(voucher_sig, read_bin(dir .. "/out-0-0.bin"), "raw")
        expect.equal(out00.payload, "hello")
        local out10 = evmu.decode_calldata(voucher_sig, read_bin(dir .. "/out-1-0.bin"), "raw")
        expect.equal(out10.payload, "world")
        assert(io.open(dir .. "/outh-0.bin", "r"), "no output-hash for input 0")
        assert(io.open(dir .. "/outh-1.bin", "r"), "no output-hash for input 1")
        expect.equal(read_bin(dir .. "/qrep-0.bin"), "inspect-me")
    end)

    -- -------------------------------------------------------------------------
    -- Rollback flow: snapshot / commit / rollback via remote server
    --
    -- What: The do_snapshot, do_commit, and do_rollback branches of the CLI's
    --       main loop, exercised when a remote server is available.
    -- How:  Spawn a JSON-RPC server; feed three inputs where
    --       ioctl-echo-loop --reject=1 rejects the middle input, so input 1
    --       takes the rollback path while inputs 0 and 2 take snapshot + commit.
    -- -------------------------------------------------------------------------
    it("rollup rollback flow", function()
        local jsonrpc = require("cartesi.jsonrpc")
        local server <close>, address = jsonrpc.spawn_server()
        server:set_cleanup_call(jsonrpc.NOTHING)
        local dir = scratch
        write_bin(dir .. "/inpr-0.bin", encode_advance(0, "ok"))
        write_bin(dir .. "/inpr-1.bin", encode_advance(1, "reject-me"))
        write_bin(dir .. "/inpr-2.bin", encode_advance(2, "also-ok"))

        -- ioctl-echo-loop --reject=1 rejects the second input, exercising do_rollback;
        -- inputs 0 and 2 exercise do_snapshot + do_commit
        run_ok({
            "--remote-address=" .. address,
            "--cmio-advance-state=input:"
                .. dir
                .. "/inpr-%i.bin,"
                .. "input_index_begin:0,input_index_end:3,"
                .. "output:"
                .. dir
                .. "/rbo-%i-%o.bin,"
                .. "report:"
                .. dir
                .. "/rbr-%i-%o.bin,"
                .. "output_hashes_root_hash:"
                .. dir
                .. "/rboh-%i.bin",
            "--max-mcycle=2000000000",
            "--no-init-splash",
            "--quiet",
            "--",
            "ioctl-echo-loop --vouchers=1 --notices=1 --reports=1 --reject=1",
        })
    end)

    -- -------------------------------------------------------------------------
    -- --assert-rolling-template failure path
    --
    -- What: When the last machine state after all inputs is RX_REJECTED,
    --       --assert-rolling-template must cause the CLI to exit with rc == 2.
    -- How:  Run a single input with ioctl-echo-loop --reject=0 so the only
    --       advance is rejected; assert run() returns rc == 2.
    -- -------------------------------------------------------------------------
    it("rollup rolling template failure", function()
        local dir = scratch
        write_bin(dir .. "/inrt-0.bin", encode_advance(0, "rej"))

        -- ioctl-echo-loop --reject=0 rejects the first (and only) input, so
        -- the machine ends in RX_REJECTED; --assert-rolling-template then sets exit_code=2
        local rc = run({
            "--cmio-advance-state=input:"
                .. dir
                .. "/inrt-%i.bin,"
                .. "input_index_begin:0,input_index_end:1,"
                .. "output:"
                .. dir
                .. "/rt-%i-%o.bin,"
                .. "report:"
                .. dir
                .. "/rtrp-%i-%o.bin,"
                .. "output_hashes_root_hash:"
                .. dir
                .. "/rth-%i.bin",
            "--no-rollback",
            "--assert-rolling-template",
            "--max-mcycle=2000000000",
            "--no-init-splash",
            "--quiet",
            "--",
            "ioctl-echo-loop --reports=1 --reject=0",
        })
        expect.equal(rc, 2)
    end)

    -- -------------------------------------------------------------------------
    -- --remote-fork: fork a remote server with and without rebind
    --
    -- What: --remote-fork forks the remote server; optionally rebinding to a
    --       new address.
    -- How:  Spawn a server; run with bare --remote-fork (forked child is left
    --       alive).  Then spawn again and run with --remote-fork=<free addr>
    --       and --remote-shutdown to exercise the rebind path.
    -- -------------------------------------------------------------------------
    it("remote fork", function()
        local jsonrpc = require("cartesi.jsonrpc")

        -- Fork without rebind: forked server is left alive (hits "Left alive" log path)
        do
            local server <close>, address = jsonrpc.spawn_server()
            server:set_cleanup_call(jsonrpc.NOTHING)
            run_ok({
                "--remote-address=" .. address,
                "--remote-fork",
                "--max-mcycle=0",
                "--no-init-splash",
                "--quiet",
            })
        end

        -- Fork with rebind to explicit address
        do
            local server2 <close>, address2 = jsonrpc.spawn_server()
            server2:set_cleanup_call(jsonrpc.NOTHING)
            -- Obtain a free port by spawning and immediately shutting down
            local tmp_srv <close>, rebind_addr = jsonrpc.spawn_server()
            tmp_srv:shutdown_server()
            run_ok({
                "--remote-address=" .. address2,
                "--remote-fork=" .. rebind_addr,
                "--remote-shutdown",
                "--max-mcycle=0",
                "--no-init-splash",
                "--quiet",
            })
        end
    end)

    -- -------------------------------------------------------------------------
    -- --gdb: GDB stub init and listen
    --
    -- What: --gdb=<addr> initializes the GDB stub and waits for a TCP
    --       connection before proceeding.
    -- How:  Launch the CLI with --gdb in the background via a small shell
    --       wrapper; poll-send the GDB detach packet (+$D#44) with nc to
    --       trigger the listen path; then wait for the CLI process to exit.
    -- -------------------------------------------------------------------------
    it("GDB stub", function()
        local port = 53210
        local gdb_addr = "127.0.0.1:" .. port
        local log = scratch_path(".log")

        -- Launch CLI with --gdb in background
        local runner = scratch_path(".sh")
        local f = assert(io.open(runner, "w"))
        f:write(
            string.format(
                "#!/bin/sh\n%s %s --gdb=%s --max-mcycle=1000000 --no-init-splash --quiet >%s 2>&1 &\necho $!\n",
                CLI_LUA,
                CLI,
                gdb_addr,
                log
            )
        )
        f:close()
        os.execute("chmod +x " .. runner)
        local pipe = io.popen(runner)
        local pid = pipe and pipe:read("*l")
        if pipe then
            pipe:close()
        end

        -- Wait for listen, send GDB detach packet, then wait for process
        os.execute(
            string.format(
                "for i in 1 2 3 4 5 6 7 8 9 10; do "
                    .. "printf '+$D#44' | nc -w 1 127.0.0.1 %d >/dev/null && break; sleep 0.2; "
                    .. "done 2>/dev/null || true",
                port
            )
        )
        if pid then
            os.execute("wait " .. pid .. " 2>/dev/null || kill " .. pid .. " 2>/dev/null")
        end
    end)
end)

-- Cleanup scratch directory (runs once when the module is loaded)
safer_rm_rf(scratch)
