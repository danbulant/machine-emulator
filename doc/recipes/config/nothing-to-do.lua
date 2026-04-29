return {
  processor = {
    x = {
      0x0, -- default
      0x0, -- default
      0x0, -- default
      0x0, -- default
      0x0, -- default
      0x0, -- default
      0x0, -- default
      0x0, -- default
      0x0, -- default
      0x0, -- default
      0x0, -- default
      0x0, -- default
      0x0, -- default
      0x0, -- default
      0x0, -- default
      0x0, -- default
      0x0, -- default
      0x0, -- default
      0x0, -- default
      0x0, -- default
      0x0, -- default
      0x0, -- default
      0x0, -- default
      0x0, -- default
      0x0, -- default
      0x0, -- default
      0x0, -- default
      0x0, -- default
      0x0, -- default
      0x0, -- default
      0x0, -- default
    },
    iflags = 0x18, -- default
    ilrsc = 0xffffffffffffffff, -- default
    marchid = 0xc, -- default
    mcause = 0x0, -- default
    mcounteren = 0x0, -- default
    mcycle = 0x0, -- default
    medeleg = 0x0, -- default
    mepc = 0x0, -- default
    mideleg = 0x0, -- default
    mie = 0x0, -- default
    mimpid = 0x1, -- default
    minstret = 0x0, -- default
    mip = 0x0, -- default
    misa = 0x8000000000141101, -- default
    mscratch = 0x0, -- default
    mstatus = 0xa00000000, -- default
    mtval = 0x0, -- default
    mtvec = 0x0, -- default
    mvendorid = 0x6361727465736920, -- default
    pc = 0x1000, -- default
    satp = 0x0, -- default
    scause = 0x0, -- default
    scounteren = 0x0, -- default
    sepc = 0x0, -- default
    sscratch = 0x0, -- default
    stval = 0x0, -- default
    stvec = 0x0, -- default
  },
  ram = {
    length = 0x4000000,
    image_filename = "/opt/cartesi/share/images/linux.bin",
  },
  rom = {
    image_filename = "/opt/cartesi/share/images/rom.bin",
    bootargs = "console=hvc0 rootfstype=ext2 root=/dev/mtdblock0 rw quiet swiotlb=noforce mtdparts=flash.0:-(root)",
  },
  htif = {
    tohost = 0x0, -- default
    fromhost = 0x0, -- default
    console_getchar = false, -- default
    yield_automatic = false, -- default
    yield_manual = false, -- default
  },
  clint = {
    mtimecmp = 0x0, -- default
  },
  flash_drive = {
    {
      start = 0x8000000000000000,
      length = 0x5000000,
      image_filename = "/opt/cartesi/share/images/rootfs.ext2",
      shared = false, -- default
    },
  },
}

