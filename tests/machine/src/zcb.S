/* Copyright Cartesi and individual authors (see AUTHORS)
 * SPDX-License-Identifier: Apache-2.0
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

// Value tests for the Zcb extension instructions. The upstream riscv-tests
// rv64uc-p-rvc test covers the base C extension but predates Zcb, and
// compressed.S only covers hint/illegal/trap behavior, so nothing exercises the
// Zcb handler bodies. The expected results are the same as the non-compressed
// counterparts (c.mul == mul, c.zext.b == andi 0xff, c.lbu == lbu, ...), so the
// vectors are taken from the corresponding rv64um / rv64ui tests. Zcb uses the
// compressed register set, so all operands are in x8-x15 (s0-s1, a0-a5).

#include <address-range-defines.h>

// Uses HTIF to exit the emulator with exit code in an immediate
#define exit_imm(imm) \
	li gp, imm; \
	j exit;

// Enable Zcb (and Zbb/Zba, required by the c.sext/c.zext mnemonics) for a block
#define ZCB(code...) \
	.option push; \
	.option arch, +zcb, +zbb, +zba; \
	code; \
	.option pop;

// Register-register op with rd == rs1 (Zcb CA format): s0 = mnem(s0, s1).
// mnem is the bare compressed mnemonic, e.g. c.mul (operands added below so the
// preprocessor does not split the instruction on its comma).
#define TEST_C_RR(mnem, result, val1, val2) \
	li s0, val1; \
	li s1, val2; \
	ZCB(mnem s0, s1) \
	li t0, result; \
	bne s0, t0, fail;

// Single-register op with rd == rs1: s0 = mnem(s0).
#define TEST_C_R(mnem, result, val1) \
	li s0, val1; \
	ZCB(mnem s0) \
	li t0, result; \
	bne s0, t0, fail;

// Compressed load: s0 = load(s1). Stores val at scratch with a base store first.
#define TEST_C_LD(load_mnem, result, store_insn, val) \
	la s1, scratch; \
	li t0, val; \
	store_insn t0, 0(s1); \
	ZCB(load_mnem s0, 0(s1)) \
	li t0, result; \
	bne s0, t0, fail;

// Compressed store: store(s1) = s0; read it back with a base load.
#define TEST_C_ST(store_mnem, result, load_insn, val) \
	la s1, scratch; \
	li s0, val; \
	ZCB(store_mnem s0, 0(s1)) \
	load_insn t0, 0(s1); \
	li t1, result; \
	bne t0, t1, fail;

.section .text.init
.align 2;
.global _start;
_start:
	// Trap to fail on any unexpected exception
	la t0, fail;
	csrw mtvec, t0;

test_c_mul:
	// vectors from rv64um/mul.S
	TEST_C_RR(c.mul, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000)
	TEST_C_RR(c.mul, 0x0000000000000001, 0x0000000000000001, 0x0000000000000001)
	TEST_C_RR(c.mul, 0x0000000000000015, 0x0000000000000003, 0x0000000000000007)
	TEST_C_RR(c.mul, 0x0000000000001200, 0x0000000000007e00, 0x6db6db6db6db6db7)
	TEST_C_RR(c.mul, 0x0000000000000000, 0x0000000000000000, 0xffffffffffff8000)
	TEST_C_RR(c.mul, 0x0000000000000000, 0xffffffff80000000, 0x0000000000000000)

test_c_zext_b:
	TEST_C_R(c.zext.b, 0x00000000000000ff, 0xffffffffffffffff)
	TEST_C_R(c.zext.b, 0x0000000000000000, 0xffffffffffffff00)

test_c_sext_b:
	TEST_C_R(c.sext.b, 0xffffffffffffffff, 0x00000000000000ff)
	TEST_C_R(c.sext.b, 0x000000000000007f, 0x000000000000007f)

test_c_zext_h:
	TEST_C_R(c.zext.h, 0x000000000000ffff, 0xffffffffffffffff)
	TEST_C_R(c.zext.h, 0x0000000000000000, 0xffffffffffff0000)

test_c_sext_h:
	TEST_C_R(c.sext.h, 0xffffffffffffffff, 0x000000000000ffff)
	TEST_C_R(c.sext.h, 0x0000000000007fff, 0x0000000000007fff)

test_c_zext_w:
	TEST_C_R(c.zext.w, 0x00000000ffffffff, 0xffffffffffffffff)
	TEST_C_R(c.zext.w, 0x0000000000000000, 0xffffffff00000000)

test_c_not:
	TEST_C_R(c.not, 0xffffffffffffffff, 0x0000000000000000)
	TEST_C_R(c.not, 0x00000000ffff0000, 0xffffffff0000ffff)

test_c_lbu:
	// vectors from rv64ui/lbu.S and lhu.S / lh.S
	TEST_C_LD(c.lbu, 0x00000000000000ff, sb, 0xff)
	TEST_C_LD(c.lbu, 0x0000000000000000, sb, 0x00)

test_c_lhu:
	TEST_C_LD(c.lhu, 0x000000000000ffff, sh, 0xffff)
	TEST_C_LD(c.lhu, 0x0000000000005678, sh, 0x5678)

test_c_lh:
	TEST_C_LD(c.lh, 0xffffffffffffffff, sh, 0xffff)
	TEST_C_LD(c.lh, 0x0000000000000678, sh, 0x0678)

test_c_sb:
	TEST_C_ST(c.sb, 0x00000000000000aa, lbu, 0xaa)

test_c_sh:
	TEST_C_ST(c.sh, 0x000000000000beef, lhu, 0xbeef)

success:
	exit_imm(0);

// catch exception and exit
fail:
	exit_imm(1);

// Exits via HTIF using gp content as the exit code
exit:
	slli gp, gp, 16;
	srli gp, gp, 15;
	ori gp, gp, 1;
1:
	li t0, AR_HTIF_START_DEF
	sd gp, 0(t0);
	j 1b;

.data
.align 3
scratch: .dword 0; .dword 0;
