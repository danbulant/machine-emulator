return {
  cmio = {
    rx_buffer = {
      backing_store = {
        create = false, -- default
        data_filename = "", -- default
        dht_filename = "", -- default
        dpt_filename = "", -- default
        shared = false, -- default
        truncate = false, -- default
      },
    },
    tx_buffer = {
      backing_store = {
        create = false, -- default
        data_filename = "", -- default
        dht_filename = "", -- default
        dpt_filename = "", -- default
        shared = false, -- default
        truncate = false, -- default
      },
    },
  },
  dtb = {
    backing_store = {
      create = false, -- default
      data_filename = "", -- default
      dht_filename = "", -- default
      dpt_filename = "", -- default
      shared = false, -- default
      truncate = false, -- default
    },
    bootargs = "quiet earlycon=sbi console=hvc0 uio_pdrv_genirq.of_id=generic-uio root=/dev/pmem0 rw init=/usr/sbin/cartesi-init", -- default
    entrypoint = "", -- default
    init = "echo \"\
         .\
        / \\\\\
      /    \\\\\
\\\\---/---\\\\  /----\\\\\
 \\\\       X       \\\\\
  \\\\----/  \\\\---/---\\\\\
       \\\\    / CARTESI\
        \\\\ /   MACHINE\
         '\
\"\
",
  },
  flash_drive = {
    {
      backing_store = {
        create = false,
        data_filename = "/usr/share/cartesi-machine/images/rootfs.ext2",
        dht_filename = "",
        dpt_filename = "",
        shared = false,
        truncate = false,
      },
      label = "root",
      length = 0x15dbe000,
      read_only = false,
      start = 0x80000000000000,
    },
  },
  hash_tree = {
    create = false, -- default
    hash_function = "keccak256", -- default
    phtc_filename = "", -- default
    phtc_size = 0x1000, -- default
    shared = false, -- default
    sht_filename = "", -- default
  },
  nvram = {},
  pmas = {
    backing_store = {
      create = false, -- default
      data_filename = "", -- default
      dht_filename = "", -- default
      dpt_filename = "", -- default
      shared = false, -- default
      truncate = false, -- default
    },
  },
  processor = {
    backing_store = {
      create = false, -- default
      data_filename = "", -- default
      dht_filename = "", -- default
      dpt_filename = "", -- default
      shared = false, -- default
      truncate = false, -- default
    },
    registers = {
      clint = {
        mtimecmp = 0x0, -- default
      },
      f0 = 0x0, -- default
      f1 = 0x0, -- default
      f10 = 0x0, -- default
      f11 = 0x0, -- default
      f12 = 0x0, -- default
      f13 = 0x0, -- default
      f14 = 0x0, -- default
      f15 = 0x0, -- default
      f16 = 0x0, -- default
      f17 = 0x0, -- default
      f18 = 0x0, -- default
      f19 = 0x0, -- default
      f2 = 0x0, -- default
      f20 = 0x0, -- default
      f21 = 0x0, -- default
      f22 = 0x0, -- default
      f23 = 0x0, -- default
      f24 = 0x0, -- default
      f25 = 0x0, -- default
      f26 = 0x0, -- default
      f27 = 0x0, -- default
      f28 = 0x0, -- default
      f29 = 0x0, -- default
      f3 = 0x0, -- default
      f30 = 0x0, -- default
      f31 = 0x0, -- default
      f4 = 0x0, -- default
      f5 = 0x0, -- default
      f6 = 0x0, -- default
      f7 = 0x0, -- default
      f8 = 0x0, -- default
      f9 = 0x0, -- default
      fcsr = 0x0, -- default
      htif = {
        fromhost = 0x0, -- default
        iconsole = 0x2, -- default
        ihalt = 0x1, -- default
        iyield = 0x3, -- default
        tohost = 0x0, -- default
      },
      icycleinstret = 0x0, -- default
      iflags = {
        H = 0x0, -- default
        X = 0x0, -- default
        Y = 0x0, -- default
      },
      ilrsc = 0xffffffffffffffff, -- default
      iprv = 0x3, -- default
      iunrep = 0x0, -- default
      marchid = 0x14, -- default
      mcause = 0x0, -- default
      mcounteren = 0x0, -- default
      mcycle = 0x0, -- default
      medeleg = 0x0, -- default
      menvcfg = 0x0, -- default
      mepc = 0x0, -- default
      mideleg = 0x0, -- default
      mie = 0x0, -- default
      mimpid = 0x14, -- default
      mip = 0x0, -- default
      misa = 0x800000000014112d, -- default
      mscratch = 0x0, -- default
      mstatus = 0xa00000000, -- default
      mtval = 0x0, -- default
      mtvec = 0x0, -- default
      mvendorid = 0x6361727465736920, -- default
      pc = 0x80000000, -- default
      plic = {
        girqpend = 0x0, -- default
        girqsrvd = 0x0, -- default
      },
      satp = 0x0, -- default
      scause = 0x0, -- default
      scounteren = 0x0, -- default
      senvcfg = 0x0, -- default
      sepc = 0x0, -- default
      sscratch = 0x0, -- default
      stval = 0x0, -- default
      stvec = 0x0, -- default
      x0 = 0x0, -- default
      x1 = 0x0, -- default
      x10 = 0x0, -- default
      x11 = 0x7ff00000, -- default
      x12 = 0x0, -- default
      x13 = 0x0, -- default
      x14 = 0x0, -- default
      x15 = 0x0, -- default
      x16 = 0x0, -- default
      x17 = 0x0, -- default
      x18 = 0x0, -- default
      x19 = 0x0, -- default
      x2 = 0x0, -- default
      x20 = 0x0, -- default
      x21 = 0x0, -- default
      x22 = 0x0, -- default
      x23 = 0x0, -- default
      x24 = 0x0, -- default
      x25 = 0x0, -- default
      x26 = 0x0, -- default
      x27 = 0x0, -- default
      x28 = 0x0, -- default
      x29 = 0x0, -- default
      x3 = 0x0, -- default
      x30 = 0x0, -- default
      x31 = 0x0, -- default
      x4 = 0x0, -- default
      x5 = 0x0, -- default
      x6 = 0x0, -- default
      x7 = 0x0, -- default
      x8 = 0x0, -- default
      x9 = 0x0, -- default
    },
  },
  ram = {
    backing_store = {
      create = false, -- default
      data_filename = "/usr/share/cartesi-machine/images/linux.bin",
      dht_filename = "", -- default
      dpt_filename = "", -- default
      shared = false, -- default
      truncate = false, -- default
    },
    length = 0x8000000,
  },
  uarch = {
    processor = {
      backing_store = {
        create = false, -- default
        data_filename = "", -- default
        dht_filename = "", -- default
        dpt_filename = "", -- default
        shared = false, -- default
        truncate = false, -- default
      },
      registers = {
        cycle = 0x0, -- default
        halt_flag = 0x0, -- default
        pc = 0x600000, -- default
        x0 = 0x0, -- default
        x1 = 0x0, -- default
        x10 = 0x0, -- default
        x11 = 0x0, -- default
        x12 = 0x0, -- default
        x13 = 0x0, -- default
        x14 = 0x0, -- default
        x15 = 0x0, -- default
        x16 = 0x0, -- default
        x17 = 0x0, -- default
        x18 = 0x0, -- default
        x19 = 0x0, -- default
        x2 = 0x0, -- default
        x20 = 0x0, -- default
        x21 = 0x0, -- default
        x22 = 0x0, -- default
        x23 = 0x0, -- default
        x24 = 0x0, -- default
        x25 = 0x0, -- default
        x26 = 0x0, -- default
        x27 = 0x0, -- default
        x28 = 0x0, -- default
        x29 = 0x0, -- default
        x3 = 0x0, -- default
        x30 = 0x0, -- default
        x31 = 0x0, -- default
        x4 = 0x0, -- default
        x5 = 0x0, -- default
        x6 = 0x0, -- default
        x7 = 0x0, -- default
        x8 = 0x0, -- default
        x9 = 0x0, -- default
      },
    },
    ram = {
      backing_store = {
        create = false, -- default
        data_filename = "", -- default
        dht_filename = "", -- default
        dpt_filename = "", -- default
        shared = false, -- default
        truncate = false, -- default
      },
    },
  },
  virtio = {},
}
