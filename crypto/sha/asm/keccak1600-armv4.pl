#!/usr/bin/env perl
# Copyright 2017 The OpenSSL Project Authors. All Rights Reserved.
#
# Licensed under the OpenSSL license (the "License").  You may not use
# this file except in compliance with the License.  You can obtain a copy
# in the file LICENSE in the source distribution or at
# https://www.openssl.org/source/license.html
#
# ====================================================================
# Written by Andy Polyakov <appro@openssl.org> for the OpenSSL
# project. The module is, however, dual licensed under OpenSSL and
# CRYPTOGAMS licenses depending on where you obtain it. For further
# details see http://www.openssl.org/~appro/cryptogams/.
# ====================================================================
#
# Keccak-1600 for ARMv4.
#
# June 2017.
#
# Non-NEON code is KECCAK_1X variant (see sha/keccak1600.c) with bit
# interleaving. How does it compare to Keccak Code Package? It's as
# fast, but several times smaller, and is endian- and ISA-neutral. ISA
# neutrality means that minimum ISA requirement is ARMv4, yet it can
# be assembled even as Thumb-2. NEON code path is KECCAK_1X_ALT with
# register layout taken from Keccak Code Package. It's also as fast,
# in fact faster by 10-15% on some processors, and endian-neutral.
#
########################################################################
# Numbers are cycles per processed byte. Non-NEON results account even
# for input bit interleaving [which takes ~1/4-1/3 of time].
#
#		r=1600(*),NEON		r=1088(**),NEON
#
# Cortex-A5	80/+220%, 24		110,       36
# Cortex-A7	71/+180%, 23		99,        34
# Cortex-A8	48/+290%, 20		67,        30
# Cortex-A9	48/+290%, 17		66,        26
# Cortex-A15	34/+210%, 12		47,        18
# Snapdragon S4	44/+230%, 16		59,        24
#
# (*)	Not used in real life, meaningful as estimate for single absorb
#	operation performance. Percentage after slash is improvement
#	over compiler-generated KECCAK_1X reference code.
# (**)	Corresponds to SHA3-256, 8KB message size.

my @C = map("r$_",(0..9));
my @E = map("r$_",(10..12,14));

########################################################################
# Stack layout
# ----->+-----------------------+
#       | uint64_t A[5][5]      |
#       | ...                   |
# +200->+-----------------------+
#       | uint64_t D[5]         |
#       | ...                   |
# +240->+-----------------------+
#       | uint64_t T[2][5]      |
#       | ...                   |
# +320->+-----------------------+
#       | saved lr              |
# +324->+-----------------------+
#       | loop counter          |
# +328->+-----------------------+
#       | ...

my @A = map([ 8*$_, 8*($_+1), 8*($_+2), 8*($_+3), 8*($_+4) ], (0,5,10,15,20));
my @D = map(8*$_, (25..29));
my @T = map([ 8*$_, 8*($_+1), 8*($_+2), 8*($_+3), 8*($_+4) ], (30,35));

$code.=<<___;
.text

#if defined(__thumb2__)
.syntax	unified
.thumb
#else
.code	32
#endif

.type	iotas32, %object
.align	5
iotas32:
	.long	0x00000001, 0x00000000
	.long	0x00000000, 0x00000089
	.long	0x00000000, 0x8000008b
	.long	0x00000000, 0x80008080
	.long	0x00000001, 0x0000008b
	.long	0x00000001, 0x00008000
	.long	0x00000001, 0x80008088
	.long	0x00000001, 0x80000082
	.long	0x00000000, 0x0000000b
	.long	0x00000000, 0x0000000a
	.long	0x00000001, 0x00008082
	.long	0x00000000, 0x00008003
	.long	0x00000001, 0x0000808b
	.long	0x00000001, 0x8000000b
	.long	0x00000001, 0x8000008a
	.long	0x00000001, 0x80000081
	.long	0x00000000, 0x80000081
	.long	0x00000000, 0x80000008
	.long	0x00000000, 0x00000083
	.long	0x00000000, 0x80008003
	.long	0x00000001, 0x80008088
	.long	0x00000000, 0x80000088
	.long	0x00000001, 0x00008000
	.long	0x00000000, 0x80008082
.size	iotas32,.-iotas32

.type	KeccakF1600_int, %function
.align	5
KeccakF1600_int:
	ldmia	sp,{@C[0]-@C[9]}		@ A[0][0..4]
	add	@E[0],sp,#$A[1][0]
KeccakF1600_enter:
	str	lr,[sp,#320]
	eor	@E[1],@E[1],@E[1]
	str	@E[1],[sp,#324]
	b	.Lround_enter

.align	4
.Lround:
	ldmia	sp,{@C[0]-@C[9]}		@ A[0][0..4]
.Lround_enter:
	ldmia	@E[0],{@E[0]-@E[2],@E[3]}	@ A[1][0..1]
	eor	@C[0],@C[0],@E[0]
	 add	@E[0],sp,#$A[1][2]
	eor	@C[1],@C[1],@E[1]
	eor	@C[2],@C[2],@E[2]
	eor	@C[3],@C[3],@E[3]
	ldmia	@E[0],{@E[0]-@E[2],@E[3]}	@ A[1][2..3]
	eor	@C[4],@C[4],@E[0]
	 add	@E[0],sp,#$A[1][4]
	eor	@C[5],@C[5],@E[1]
	eor	@C[6],@C[6],@E[2]
	eor	@C[7],@C[7],@E[3]
	ldmia	@E[0],{@E[0]-@E[2],@E[3]}	@ A[1][4]..A[2][0]
	eor	@C[8],@C[8],@E[0]
	 add	@E[0],sp,#$A[2][1]
	eor	@C[9],@C[9],@E[1]
	eor	@C[0],@C[0],@E[2]
	eor	@C[1],@C[1],@E[3]
	ldmia	@E[0],{@E[0]-@E[2],@E[3]}	@ A[2][1..2]
	eor	@C[2],@C[2],@E[0]
	 add	@E[0],sp,#$A[2][3]
	eor	@C[3],@C[3],@E[1]
	eor	@C[4],@C[4],@E[2]
	eor	@C[5],@C[5],@E[3]
	ldmia	@E[0],{@E[0]-@E[2],@E[3]}	@ A[2][3..4]
	eor	@C[6],@C[6],@E[0]
	 add	@E[0],sp,#$A[3][0]
	eor	@C[7],@C[7],@E[1]
	eor	@C[8],@C[8],@E[2]
	eor	@C[9],@C[9],@E[3]
	ldmia	@E[0],{@E[0]-@E[2],@E[3]}	@ A[3][0..1]
	eor	@C[0],@C[0],@E[0]
	 add	@E[0],sp,#$A[3][2]
	eor	@C[1],@C[1],@E[1]
	eor	@C[2],@C[2],@E[2]
	eor	@C[3],@C[3],@E[3]
	ldmia	@E[0],{@E[0]-@E[2],@E[3]}	@ A[3][2..3]
	eor	@C[4],@C[4],@E[0]
	 add	@E[0],sp,#$A[3][4]
	eor	@C[5],@C[5],@E[1]
	eor	@C[6],@C[6],@E[2]
	eor	@C[7],@C[7],@E[3]
	ldmia	@E[0],{@E[0]-@E[2],@E[3]}	@ A[3][4]..A[4][0]
	eor	@C[8],@C[8],@E[0]
	 add	@E[0],sp,#$A[4][1]
	eor	@C[9],@C[9],@E[1]
	eor	@C[0],@C[0],@E[2]
	eor	@C[1],@C[1],@E[3]
	ldmia	@E[0],{@E[0]-@E[2],@E[3]}	@ A[4][1..2]
	eor	@C[2],@C[2],@E[0]
	 add	@E[0],sp,#$A[4][3]
	eor	@C[3],@C[3],@E[1]
	eor	@C[4],@C[4],@E[2]
	eor	@C[5],@C[5],@E[3]
	ldmia	@E[0],{@E[0]-@E[2],@E[3]}	@ A[4][3..4]
	eor	@C[6],@C[6],@E[0]
	eor	@C[7],@C[7],@E[1]
	eor	@C[8],@C[8],@E[2]
	eor	@C[9],@C[9],@E[3]

	eor	@E[0],@C[0],@C[5],ror#32-1	@ E[0] = ROL64(C[2], 1) ^ C[0];
	eor	@E[1],@C[1],@C[4]
	str	@E[0],[sp,#$D[1]]		@ D[1] = E[0]
	eor	@E[2],@C[6],@C[1],ror#32-1	@ E[1] = ROL64(C[0], 1) ^ C[3];
	str	@E[1],[sp,#$D[1]+4]
	eor	@E[3],@C[7],@C[0]
	str	@E[2],[sp,#$D[4]]		@ D[4] = E[1]
	eor	@C[0],@C[8],@C[3],ror#32-1	@ C[0] = ROL64(C[1], 1) ^ C[4];
	str	@E[3],[sp,#$D[4]+4]
	eor	@C[1],@C[9],@C[2]
	str	@C[0],[sp,#$D[0]]		@ D[0] = C[0]
	eor	@C[2],@C[2],@C[7],ror#32-1	@ C[1] = ROL64(C[3], 1) ^ C[1];
	str	@C[1],[sp,#$D[0]+4]
	eor	@C[3],@C[3],@C[6]
	str	@C[2],[sp,#$D[2]]		@ D[2] = C[1]
	eor	@C[4],@C[4],@C[9],ror#32-1	@ C[2] = ROL64(C[4], 1) ^ C[2];
	str	@C[3],[sp,#$D[2]+4]
	eor	@C[5],@C[5],@C[8]
	 ldr	@C[8],[sp,#$A[3][0]]
	 ldr	@C[9],[sp,#$A[3][0]+4]
	str	@C[4],[sp,#$D[3]]		@ D[3] = C[2]
	str	@C[5],[sp,#$D[3]+4]

	ldr	@C[6],[sp,#$A[0][1]]
	eor	@C[8],@C[8],@C[0]
	ldr	@C[7],[sp,#$A[0][1]+4]
	eor	@C[9],@C[9],@C[1]
	str	@C[8],[sp,#$T[0][0]]		@ T[0][0] = A[3][0] ^ C[0]; /* borrow T[0][0] */
	ldr	@C[8],[sp,#$A[0][2]]
	str	@C[9],[sp,#$T[0][0]+4]
	ldr	@C[9],[sp,#$A[0][2]+4]
	eor	@C[6],@C[6],@E[0]
	eor	@C[7],@C[7],@E[1]
	str	@C[6],[sp,#$T[0][1]]		@ T[0][1] = A[0][1] ^ E[0]; /* D[1] */
	ldr	@C[6],[sp,#$A[0][3]]
	str	@C[7],[sp,#$T[0][1]+4]
	ldr	@C[7],[sp,#$A[0][3]+4]
	eor	@C[8],@C[8],@C[2]
	eor	@C[9],@C[9],@C[3]
	str	@C[8],[sp,#$T[0][2]]		@ T[0][2] = A[0][2] ^ C[1]; /* D[2] */
	ldr	@C[8],[sp,#$A[0][4]]
	str	@C[9],[sp,#$T[0][2]+4]
	ldr	@C[9],[sp,#$A[0][4]+4]
	eor	@C[6],@C[6],@C[4]
	eor	@C[7],@C[7],@C[5]
	str	@C[6],[sp,#$T[0][3]]		@ T[0][3] = A[0][3] ^ C[2]; /* D[3] */
	eor	@C[8],@C[8],@E[2]
	str	@C[7],[sp,#$T[0][3]+4]
	eor	@C[9],@C[9],@E[3]
	 ldr	@C[6],[sp,#$A[3][3]]
	 ldr	@C[7],[sp,#$A[3][3]+4]
	str	@C[8],[sp,#$T[0][4]]		@ T[0][4] = A[0][4] ^ E[1]; /* D[4] */
	str	@C[9],[sp,#$T[0][4]+4]

	ldr	@C[8],[sp,#$A[4][4]]
	eor	@C[4],@C[4],@C[6]
	ldr	@C[9],[sp,#$A[4][4]+4]
	eor	@C[5],@C[5],@C[7]
	ror	@C[7],@C[4],#32-10		@ C[3] = ROL64(A[3][3] ^ C[2], rhotates[3][3]);   /* D[3] */
	ldr	@C[4],[sp,#$A[0][0]]
	ror	@C[6],@C[5],#32-11
	ldr	@C[5],[sp,#$A[0][0]+4]
	eor	@C[8],@C[8],@E[2]
	eor	@C[9],@C[9],@E[3]
	ror	@C[8],@C[8],#32-7		@ C[4] = ROL64(A[4][4] ^ E[1], rhotates[4][4]);   /* D[4] */
	ldr	@E[2],[sp,#$A[2][2]]
	ror	@C[9],@C[9],#32-7
	ldr	@E[3],[sp,#$A[2][2]+4]
	eor	@C[0],@C[0],@C[4]
	eor	@C[1],@C[1],@C[5]		@ C[0] =       A[0][0] ^ C[0]; /* rotate by 0 */  /* D[0] */
	eor	@E[2],@E[2],@C[2]
	ldr	@C[2],[sp,#$A[1][1]]
	eor	@E[3],@E[3],@C[3]
	ldr	@C[3],[sp,#$A[1][1]+4]
	ror	@C[5],@E[2],#32-21		@ C[2] = ROL64(A[2][2] ^ C[1], rhotates[2][2]);   /* D[2] */
	 ldr	@E[2],[sp,#324]			@ load counter
	eor	@C[2],@C[2],@E[0]
	ror	@C[4],@E[3],#32-22
	 adr	@E[3],iotas32
	eor	@C[3],@C[3],@E[1]
	ror	@C[2],@C[2],#32-22		@ C[1] = ROL64(A[1][1] ^ E[0], rhotates[1][1]);   /* D[1] */
	 add	@E[3],@E[3],@E[2]
	ror	@C[3],@C[3],#32-22

	ldr	@E[0],[@E[3],#0]		@ iotas[i].lo
	add	@E[2],@E[2],#8
	ldr	@E[1],[@E[3],#4]		@ iotas[i].hi
	cmp	@E[2],#192
	str	@E[2],[sp,#324]			@ store counter

	bic	@E[2],@C[4],@C[2]
	bic	@E[3],@C[5],@C[3]
	eor	@E[2],@E[2],@C[0]
	eor	@E[3],@E[3],@C[1]
	eor	@E[0],@E[0],@E[2]
	eor	@E[1],@E[1],@E[3]
	str	@E[0],[sp,#$A[0][0]]		@ A[0][0] = C[0] ^ (~C[1] & C[2]) ^ iotas[i];
	bic	@E[2],@C[6],@C[4]
	str	@E[1],[sp,#$A[0][0]+4]
	bic	@E[3],@C[7],@C[5]
	eor	@E[2],@E[2],@C[2]
	eor	@E[3],@E[3],@C[3]
	str	@E[2],[sp,#$A[0][1]]		@ A[0][1] = C[1] ^ (~C[2] & C[3]);
	bic	@E[0],@C[8],@C[6]
	str	@E[3],[sp,#$A[0][1]+4]
	bic	@E[1],@C[9],@C[7]
	eor	@E[0],@E[0],@C[4]
	eor	@E[1],@E[1],@C[5]
	str	@E[0],[sp,#$A[0][2]]		@ A[0][2] = C[2] ^ (~C[3] & C[4]);
	bic	@E[2],@C[0],@C[8]
	str	@E[1],[sp,#$A[0][2]+4]
	bic	@E[3],@C[1],@C[9]
	eor	@E[2],@E[2],@C[6]
	eor	@E[3],@E[3],@C[7]
	str	@E[2],[sp,#$A[0][3]]		@ A[0][3] = C[3] ^ (~C[4] & C[0]);
	bic	@E[0],@C[2],@C[0]
	str	@E[3],[sp,#$A[0][3]+4]
	 add	@E[3],sp,#$D[0]
	bic	@E[1],@C[3],@C[1]
	eor	@E[0],@E[0],@C[8]
	eor	@E[1],@E[1],@C[9]
	str	@E[0],[sp,#$A[0][4]]		@ A[0][4] = C[4] ^ (~C[0] & C[1]);
	str	@E[1],[sp,#$A[0][4]+4]

	ldmia	@E[3],{@C[6]-@C[9],@E[0],@E[1],@E[2],@E[3]}	@ D[0..3]
	ldr	@C[0],[sp,#$A[1][0]]
	ldr	@C[1],[sp,#$A[1][0]+4]
	ldr	@C[2],[sp,#$A[2][1]]
	ldr	@C[3],[sp,#$A[2][1]+4]
	ldr	@C[4],[sp,#$D[4]]
	eor	@C[0],@C[0],@C[6]
	ldr	@C[5],[sp,#$D[4]+4]
	eor	@C[1],@C[1],@C[7]
	str	@C[0],[sp,#$T[1][0]]		@ T[1][0] = A[1][0] ^ (C[3] = D[0]);
	add	@C[0],sp,#$A[1][2]
	str	@C[1],[sp,#$T[1][0]+4]
	eor	@C[2],@C[2],@C[8]
	eor	@C[3],@C[3],@C[9]
	str	@C[2],[sp,#$T[1][1]]		@ T[1][1] = A[2][1] ^ (C[4] = D[1]); /* borrow T[1][1] */
	str	@C[3],[sp,#$T[1][1]+4]
	ldmia	@C[0],{@C[0]-@C[3]}		@ A[1][2..3]
	eor	@C[0],@C[0],@E[0]
	eor	@C[1],@C[1],@E[1]
	str	@C[0],[sp,#$T[1][2]]		@ T[1][2] = A[1][2] ^ (E[0] = D[2]);
	ldr	@C[0],[sp,#$A[2][4]]
	str	@C[1],[sp,#$T[1][2]+4]
	ldr	@C[1],[sp,#$A[2][4]+4]
	eor	@C[2],@C[2],@E[2]
	eor	@C[3],@C[3],@E[3]
	str	@C[2],[sp,#$T[1][3]]		@ T[1][3] = A[1][3] ^ (E[1] = D[3]);
	 ldr	@C[2],[sp,#$T[0][3]]
	str	@C[3],[sp,#$T[1][3]+4]
	 ldr	@C[3],[sp,#$T[0][3]+4]
	eor	@C[0],@C[0],@C[4]
	 ldr	@E[2],[sp,#$A[1][4]]
	eor	@C[1],@C[1],@C[5]
	 ldr	@E[3],[sp,#$A[1][4]+4]
	str	@C[0],[sp,#$T[1][4]]		@ T[1][4] = A[2][4] ^ (C[2] = D[4]); /* borrow T[1][4] */

	ror	@C[0],@C[2],#32-14		@ C[0] = ROL64(T[0][3],        rhotates[0][3]);
	 str	@C[1],[sp,#$T[1][4]+4]
	ror	@C[1],@C[3],#32-14
	eor	@C[2],@E[2],@C[4]
	ldr	@C[4],[sp,#$A[2][0]]
	eor	@C[3],@E[3],@C[5]
	ldr	@C[5],[sp,#$A[2][0]+4]
	ror	@C[2],@C[2],#32-10		@ C[1] = ROL64(A[1][4] ^ C[2], rhotates[1][4]);   /* D[4] */
	ldr	@E[2],[sp,#$A[3][1]]
	ror	@C[3],@C[3],#32-10
	ldr	@E[3],[sp,#$A[3][1]+4]
	eor	@C[6],@C[6],@C[4]
	eor	@C[7],@C[7],@C[5]
	ror	@C[5],@C[6],#32-1		@ C[2] = ROL64(A[2][0] ^ C[3], rhotates[2][0]);   /* D[0] */
	eor	@E[2],@E[2],@C[8]
	ror	@C[4],@C[7],#32-2
	ldr	@C[8],[sp,#$A[4][2]]
	eor	@E[3],@E[3],@C[9]
	ldr	@C[9],[sp,#$A[4][2]+4]
	ror	@C[7],@E[2],#32-22		@ C[3] = ROL64(A[3][1] ^ C[4], rhotates[3][1]);   /* D[1] */
	eor	@E[0],@E[0],@C[8]
	ror	@C[6],@E[3],#32-23
	eor	@E[1],@E[1],@C[9]
	ror	@C[9],@E[0],#32-30		@ C[4] = ROL64(A[4][2] ^ E[0], rhotates[4][2]);   /* D[2] */

	bic	@E[0],@C[4],@C[2]
	 ror	@C[8],@E[1],#32-31
	bic	@E[1],@C[5],@C[3]
	eor	@E[0],@E[0],@C[0]
	eor	@E[1],@E[1],@C[1]
	str	@E[0],[sp,#$A[1][0]]		@ A[1][0] = C[0] ^ (~C[1] & C[2])
	bic	@E[2],@C[6],@C[4]
	str	@E[1],[sp,#$A[1][0]+4]
	bic	@E[3],@C[7],@C[5]
	eor	@E[2],@E[2],@C[2]
	eor	@E[3],@E[3],@C[3]
	str	@E[2],[sp,#$A[1][1]]		@ A[1][1] = C[1] ^ (~C[2] & C[3]);
	bic	@E[0],@C[8],@C[6]
	str	@E[3],[sp,#$A[1][1]+4]
	bic	@E[1],@C[9],@C[7]
	eor	@E[0],@E[0],@C[4]
	eor	@E[1],@E[1],@C[5]
	str	@E[0],[sp,#$A[1][2]]		@ A[1][2] = C[2] ^ (~C[3] & C[4]);
	bic	@E[2],@C[0],@C[8]
	str	@E[1],[sp,#$A[1][2]+4]
	bic	@E[3],@C[1],@C[9]
	eor	@E[2],@E[2],@C[6]
	eor	@E[3],@E[3],@C[7]
	str	@E[2],[sp,#$A[1][3]]		@ A[1][3] = C[3] ^ (~C[4] & C[0]);
	bic	@E[0],@C[2],@C[0]
	str	@E[3],[sp,#$A[1][3]+4]
	 add	@E[3],sp,#$D[3]
	bic	@E[1],@C[3],@C[1]
	 ldr	@C[1],[sp,#$T[0][1]]
	eor	@E[0],@E[0],@C[8]
	 ldr	@C[0],[sp,#$T[0][1]+4]
	eor	@E[1],@E[1],@C[9]
	str	@E[0],[sp,#$A[1][4]]		@ A[1][4] = C[4] ^ (~C[0] & C[1]);
	str	@E[1],[sp,#$A[1][4]+4]

	ldr	@C[2],[sp,#$T[1][2]]
	ldr	@C[3],[sp,#$T[1][2]+4]
	ldmia	@E[3],{@E[0]-@E[2],@E[3]}	@ D[3..4]
	ldr	@C[4],[sp,#$A[2][3]]
	ror	@C[0],@C[0],#32-1		@ C[0] = ROL64(T[0][1],        rhotates[0][1]);
	ldr	@C[5],[sp,#$A[2][3]+4]
	ror	@C[2],@C[2],#32-3		@ C[1] = ROL64(T[1][2],        rhotates[1][2]);
	ldr	@C[6],[sp,#$A[3][4]]
	ror	@C[3],@C[3],#32-3
	ldr	@C[7],[sp,#$A[3][4]+4]
	eor	@E[0],@E[0],@C[4]
	ldr	@C[8],[sp,#$A[4][0]]
	eor	@E[1],@E[1],@C[5]
	ldr	@C[9],[sp,#$A[4][0]+4]
	ror	@C[5],@E[0],#32-12		@ C[2] = ROL64(A[2][3] ^ D[3], rhotates[2][3]);
	ldr	@E[0],[sp,#$D[0]]
	ror	@C[4],@E[1],#32-13
	ldr	@E[1],[sp,#$D[0]+4]
	eor	@C[6],@C[6],@E[2]
	eor	@C[7],@C[7],@E[3]
	ror	@C[6],@C[6],#32-4		@ C[3] = ROL64(A[3][4] ^ D[4], rhotates[3][4]);
	eor	@C[8],@C[8],@E[0]
	ror	@C[7],@C[7],#32-4
	eor	@C[9],@C[9],@E[1]
	ror	@C[8],@C[8],#32-9		@ C[4] = ROL64(A[4][0] ^ D[0], rhotates[4][0]);

	bic	@E[0],@C[4],@C[2]
	 ror	@C[9],@C[9],#32-9
	bic	@E[1],@C[5],@C[3]
	eor	@E[0],@E[0],@C[0]
	eor	@E[1],@E[1],@C[1]
	str	@E[0],[sp,#$A[2][0]]		@ A[2][0] = C[0] ^ (~C[1] & C[2])
	bic	@E[2],@C[6],@C[4]
	str	@E[1],[sp,#$A[2][0]+4]
	bic	@E[3],@C[7],@C[5]
	eor	@E[2],@E[2],@C[2]
	eor	@E[3],@E[3],@C[3]
	str	@E[2],[sp,#$A[2][1]]		@ A[2][1] = C[1] ^ (~C[2] & C[3]);
	bic	@E[0],@C[8],@C[6]
	str	@E[3],[sp,#$A[2][1]+4]
	bic	@E[1],@C[9],@C[7]
	eor	@E[0],@E[0],@C[4]
	eor	@E[1],@E[1],@C[5]
	str	@E[0],[sp,#$A[2][2]]		@ A[2][2] = C[2] ^ (~C[3] & C[4]);
	bic	@E[2],@C[0],@C[8]
	str	@E[1],[sp,#$A[2][2]+4]
	bic	@E[3],@C[1],@C[9]
	eor	@E[2],@E[2],@C[6]
	eor	@E[3],@E[3],@C[7]
	str	@E[2],[sp,#$A[2][3]]		@ A[2][3] = C[3] ^ (~C[4] & C[0]);
	bic	@E[0],@C[2],@C[0]
	str	@E[3],[sp,#$A[2][3]+4]
	bic	@E[1],@C[3],@C[1]
	eor	@E[0],@E[0],@C[8]
	eor	@E[1],@E[1],@C[9]
	str	@E[0],[sp,#$A[2][4]]		@ A[2][4] = C[4] ^ (~C[0] & C[1]);
	 add	@C[2],sp,#$T[1][0]
	str	@E[1],[sp,#$A[2][4]+4]

	add	@E[3],sp,#$D[2]
	ldr	@C[1],[sp,#$T[0][4]]
	ldr	@C[0],[sp,#$T[0][4]+4]
	ldmia	@C[2],{@C[2]-@C[5]}		@ T[1][0..1]
	ldmia	@E[3],{@E[0]-@E[2],@E[3]}	@ D[2..3]
	ror	@C[1],@C[1],#32-13		@ C[0] = ROL64(T[0][4],        rhotates[0][4]);
	ldr	@C[6],[sp,#$A[3][2]]
	ror	@C[0],@C[0],#32-14
	ldr	@C[7],[sp,#$A[3][2]+4]
	ror	@C[2],@C[2],#32-18		@ C[1] = ROL64(T[1][0],        rhotates[1][0]);
	ldr	@C[8],[sp,#$A[4][3]]
	ror	@C[3],@C[3],#32-18
	ldr	@C[9],[sp,#$A[4][3]+4]
	ror	@C[4],@C[4],#32-5		@ C[2] = ROL64(T[1][1],        rhotates[2][1]); /* originally A[2][1] */
	eor	@E[0],@E[0],@C[6]
	ror	@C[5],@C[5],#32-5
	eor	@E[1],@E[1],@C[7]
	ror	@C[7],@E[0],#32-7		@ C[3] = ROL64(A[3][2] ^ D[2], rhotates[3][2]);
	eor	@C[8],@C[8],@E[2]
	ror	@C[6],@E[1],#32-8
	eor	@C[9],@C[9],@E[3]
	ror	@C[8],@C[8],#32-28		@ C[4] = ROL64(A[4][3] ^ D[3], rhotates[4][3]);

	bic	@E[0],@C[4],@C[2]
	 ror	@C[9],@C[9],#32-28
	bic	@E[1],@C[5],@C[3]
	eor	@E[0],@E[0],@C[0]
	eor	@E[1],@E[1],@C[1]
	str	@E[0],[sp,#$A[3][0]]		@ A[3][0] = C[0] ^ (~C[1] & C[2])
	bic	@E[2],@C[6],@C[4]
	str	@E[1],[sp,#$A[3][0]+4]
	bic	@E[3],@C[7],@C[5]
	eor	@E[2],@E[2],@C[2]
	eor	@E[3],@E[3],@C[3]
	str	@E[2],[sp,#$A[3][1]]		@ A[3][1] = C[1] ^ (~C[2] & C[3]);
	bic	@E[0],@C[8],@C[6]
	str	@E[3],[sp,#$A[3][1]+4]
	bic	@E[1],@C[9],@C[7]
	eor	@E[0],@E[0],@C[4]
	eor	@E[1],@E[1],@C[5]
	str	@E[0],[sp,#$A[3][2]]		@ A[3][2] = C[2] ^ (~C[3] & C[4]);
	bic	@E[2],@C[0],@C[8]
	str	@E[1],[sp,#$A[3][2]+4]
	bic	@E[3],@C[1],@C[9]
	eor	@E[2],@E[2],@C[6]
	eor	@E[3],@E[3],@C[7]
	str	@E[2],[sp,#$A[3][3]]		@ A[3][3] = C[3] ^ (~C[4] & C[0]);
	bic	@E[0],@C[2],@C[0]
	str	@E[3],[sp,#$A[3][3]+4]
	bic	@E[1],@C[3],@C[1]
	eor	@E[0],@E[0],@C[8]
	eor	@E[1],@E[1],@C[9]
	str	@E[0],[sp,#$A[3][4]]		@ A[3][4] = C[4] ^ (~C[0] & C[1]);
	 add	@E[3],sp,#$T[1][3]
	str	@E[1],[sp,#$A[3][4]+4]

	ldr	@C[0],[sp,#$T[0][2]]
	ldr	@C[1],[sp,#$T[0][2]+4]
	ldmia	@E[3],{@E[0]-@E[2],@E[3]}	@ T[1][3..4]
	ldr	@C[7],[sp,#$T[0][0]]
	ror	@C[0],@C[0],#32-31		@ C[0] = ROL64(T[0][2],        rhotates[0][2]);
	ldr	@C[6],[sp,#$T[0][0]+4]
	ror	@C[1],@C[1],#32-31
	ldr	@C[8],[sp,#$A[4][1]]
	ror	@C[3],@E[0],#32-27		@ C[1] = ROL64(T[1][3],        rhotates[1][3]);
	ldr	@E[0],[sp,#$D[1]]
	ror	@C[2],@E[1],#32-28
	ldr	@C[9],[sp,#$A[4][1]+4]
	ror	@C[5],@E[2],#32-19		@ C[2] = ROL64(T[1][4],        rhotates[2][4]); /* originally A[2][4] */
	ldr	@E[1],[sp,#$D[1]+4]
	ror	@C[4],@E[3],#32-20
	eor	@C[8],@C[8],@E[0]
	ror	@C[7],@C[7],#32-20		@ C[3] = ROL64(T[0][0],        rhotates[3][0]); /* originally A[3][0] */
	eor	@C[9],@C[9],@E[1]
	ror	@C[6],@C[6],#32-21

	bic	@E[0],@C[4],@C[2]
	 ror	@C[8],@C[8],#32-1		@ C[4] = ROL64(A[4][1] ^ D[1], rhotates[4][1]);
	bic	@E[1],@C[5],@C[3]
	 ror	@C[9],@C[9],#32-1
	eor	@E[0],@E[0],@C[0]
	eor	@E[1],@E[1],@C[1]
	str	@E[0],[sp,#$A[4][0]]		@ A[4][0] = C[0] ^ (~C[1] & C[2])
	bic	@E[2],@C[6],@C[4]
	str	@E[1],[sp,#$A[4][0]+4]
	bic	@E[3],@C[7],@C[5]
	eor	@E[2],@E[2],@C[2]
	eor	@E[3],@E[3],@C[3]
	str	@E[2],[sp,#$A[4][1]]		@ A[4][1] = C[1] ^ (~C[2] & C[3]);
	bic	@E[0],@C[8],@C[6]
	str	@E[3],[sp,#$A[4][1]+4]
	bic	@E[1],@C[9],@C[7]
	eor	@E[0],@E[0],@C[4]
	eor	@E[1],@E[1],@C[5]
	str	@E[0],[sp,#$A[4][2]]		@ A[4][2] = C[2] ^ (~C[3] & C[4]);
	bic	@E[2],@C[0],@C[8]
	str	@E[1],[sp,#$A[4][2]+4]
	bic	@E[3],@C[1],@C[9]
	eor	@E[2],@E[2],@C[6]
	eor	@E[3],@E[3],@C[7]
	str	@E[2],[sp,#$A[4][3]]		@ A[4][3] = C[3] ^ (~C[4] & C[0]);
	bic	@E[0],@C[2],@C[0]
	str	@E[3],[sp,#$A[4][3]+4]
	bic	@E[1],@C[3],@C[1]
	eor	@E[2],@E[0],@C[8]
	eor	@E[3],@E[1],@C[9]
	str	@E[2],[sp,#$A[4][4]]		@ A[4][4] = C[4] ^ (~C[0] & C[1]);
	 add	@E[0],sp,#$A[1][0]
	str	@E[3],[sp,#$A[4][4]+4]

	blo	.Lround

	ldr	pc,[sp,#320]
.size	KeccakF1600_int,.-KeccakF1600_int

.type	KeccakF1600, %function
.align	5
KeccakF1600:
	stmdb	sp!,{r0,r4-r11,lr}
	sub	sp,sp,#320+16			@ space for A[5][5],D[5],T[2][5],...

	add	@E[0],r0,#$A[1][0]
	add	@E[1],sp,#$A[1][0]
	mov	@E[2],r0
	ldmia	@E[0]!,{@C[0]-@C[9]}		@ copy A[5][5] to stack
	stmia	@E[1]!,{@C[0]-@C[9]}
	ldmia	@E[0]!,{@C[0]-@C[9]}
	stmia	@E[1]!,{@C[0]-@C[9]}
	ldmia	@E[0]!,{@C[0]-@C[9]}
	stmia	@E[1]!,{@C[0]-@C[9]}
	ldmia	@E[0], {@C[0]-@C[9]}
	stmia	@E[1], {@C[0]-@C[9]}
	ldmia	@E[2], {@C[0]-@C[9]}		@ A[0][0..4]
	add	@E[0],sp,#$A[1][0]
	stmia	sp,    {@C[0]-@C[9]}

	bl	KeccakF1600_enter

	ldr	@E[1], [sp,#320+16]		@ restore pointer to A
	ldmia	sp,    {@C[0]-@C[9]}
	stmia	@E[1]!,{@C[0]-@C[9]}		@ return A[5][5]
	ldmia	@E[0]!,{@C[0]-@C[9]}
	stmia	@E[1]!,{@C[0]-@C[9]}
	ldmia	@E[0]!,{@C[0]-@C[9]}
	stmia	@E[1]!,{@C[0]-@C[9]}
	ldmia	@E[0]!,{@C[0]-@C[9]}
	stmia	@E[1]!,{@C[0]-@C[9]}
	ldmia	@E[0], {@C[0]-@C[9]}
	stmia	@E[1], {@C[0]-@C[9]}

	add	sp,sp,#320+20
	ldmia	sp!,{r4-r11,pc}
.size	KeccakF1600,.-KeccakF1600
___
{ my ($hi,$lo,$i,$A_flat, $len,$bsz,$inp) = map("r$_",(5..8, 10..12));

########################################################################
# Stack layout
# ----->+-----------------------+
#       | uint64_t A[5][5]      |
#       | ...                   |
#       | ...                   |
# +336->+-----------------------+
#       | uint64_t *A           |
# +340->+-----------------------+
#       | const void *inp       |
# +344->+-----------------------+
#       | size_t len            |
# +348->+-----------------------+
#       | size_t bs             |
# +352->+-----------------------+
#       | ....

$code.=<<___;
.global	SHA3_absorb
.type	SHA3_absorb,%function
.align	5
SHA3_absorb:
	stmdb	sp!,{r0-r12,lr}
	sub	sp,sp,#320+16

	mov	r12,r0
	add	r14,sp,#0
	mov	$len,r2
	mov	$bsz,r3

	ldmia	r12!,{@C[0]-@C[9]}	@ copy A[5][5] to stack
	stmia	r14!,{@C[0]-@C[9]}
	ldmia	r12!,{@C[0]-@C[9]}
	stmia	r14!,{@C[0]-@C[9]}
	ldmia	r12!,{@C[0]-@C[9]}
	stmia	r14!,{@C[0]-@C[9]}
	ldmia	r12!,{@C[0]-@C[9]}
	stmia	r14!,{@C[0]-@C[9]}
	ldmia	r12, {@C[0]-@C[9]}
	stmia	r14, {@C[0]-@C[9]}

	ldr	$inp,[sp,#340]

.Loop_absorb:
	subs	r0,$len,$bsz
	blo	.Labsorbed
	add	$A_flat,sp,#0
	str	r0,[sp,#344]		@ save len - bsz

.Loop_block:
	ldmia	$A_flat,{r2-r3}		@ A_flat[i]
	ldrb	r0,[$inp,#7]!		@ inp[7]
	mov	$i,#8

.Lane_loop:
	subs	$i,$i,#1
	lsl	r1,r0,#24
	blo	.Lane_done
#ifdef	__thumb2__
	it	ne
	ldrbne	r0,[$inp,#-1]!
#else
	ldrneb	r0,[$inp,#-1]!
#endif
	adds	r1,r1,r1		@ sip through carry flag
	adc	$hi,$hi,$hi
	adds	r1,r1,r1
	adc	$lo,$lo,$lo
	adds	r1,r1,r1
	adc	$hi,$hi,$hi
	adds	r1,r1,r1
	adc	$lo,$lo,$lo
	adds	r1,r1,r1
	adc	$hi,$hi,$hi
	adds	r1,r1,r1
	adc	$lo,$lo,$lo
	adds	r1,r1,r1
	adc	$hi,$hi,$hi
	adds	r1,r1,r1
	adc	$lo,$lo,$lo
	b	.Lane_loop

.Lane_done:
	eor	r2,r2,$lo
	eor	r3,r3,$hi
	add	$inp,$inp,#8
	stmia	$A_flat!,{r2-r3}	@ A_flat[i++] ^= BitInterleave(inp[0..7])
	subs	$bsz,$bsz,#8
	bhi	.Loop_block

	str	$inp,[sp,#340]

	bl	KeccakF1600_int

	ldr	$inp,[sp,#340]
	ldr	$len,[sp,#344]
	ldr	$bsz,[sp,#348]
	b	.Loop_absorb

.align	4
.Labsorbed:
	add	r12,sp,#$A[1][0]
	ldr	r14, [sp,#336]		@ pull pointer to A[5][5]
	ldmia	sp,  {@C[0]-@C[9]}
	stmia	r14!,{@C[0]-@C[9]}	@ return A[5][5]
	ldmia	r12!,{@C[0]-@C[9]}
	stmia	r14!,{@C[0]-@C[9]}
	ldmia	r12!,{@C[0]-@C[9]}
	stmia	r14!,{@C[0]-@C[9]}
	ldmia	r12!,{@C[0]-@C[9]}
	stmia	r14!,{@C[0]-@C[9]}
	ldmia	r12, {@C[0]-@C[9]}
	stmia	r14, {@C[0]-@C[9]}

	add	sp,sp,#320+32
	mov	r0,$len			@ return value
	ldmia	sp!,{r4-r12,pc}
.size	SHA3_absorb,.-SHA3_absorb
___
}
{ my ($A_flat,$out,$len,$bsz, $byte,$shl) = map("r$_", (4..9));

$code.=<<___;
.global	SHA3_squeeze
.type	SHA3_squeeze,%function
.align	5
SHA3_squeeze:
	stmdb	sp!,{r4-r10,lr}
	mov	r12,r0
	mov	$A_flat,r0
	mov	$out,r1
	mov	$len,r2
	mov	$bsz,r3
	mov	r14,r3
	b	.Loop_squeeze

.align	4
.Loop_squeeze:
	ldmia	r12!,{r0,r1}		@ A_flat[i++]
	mov	$shl,#28

.Lane_squeeze:
	lsl	r2,r0,$shl
	lsl	r3,r1,$shl
	eor	$byte,$byte,$byte
	adds	r3,r3,r3		@ sip through carry flag
	adc	$byte,$byte,$byte
	adds	r2,r2,r2
	adc	$byte,$byte,$byte
	adds	r3,r3,r3
	adc	$byte,$byte,$byte
	adds	r2,r2,r2
	adc	$byte,$byte,$byte
	adds	r3,r3,r3
	adc	$byte,$byte,$byte
	adds	r2,r2,r2
	adc	$byte,$byte,$byte
	adds	r3,r3,r3
	adc	$byte,$byte,$byte
	adds	r2,r2,r2
	adc	$byte,$byte,$byte
	subs	$len,$len,#1		@ len -= 1
	str	$byte,[$out],#1
	beq	.Lsqueeze_done
	subs	$shl,$shl,#4
	bhs	.Lane_squeeze

	subs	r14,r14,#8		@ bsz -= 8
	bhi	.Loop_squeeze

	mov	r0,$A_flat

	bl	KeccakF1600

	mov	r12,$A_flat
	mov	r14,$bsz
	b	.Loop_squeeze

.Lsqueeze_done:
	ldmia	sp!,{r4-r10,pc}
.size	SHA3_squeeze,.-SHA3_squeeze
___
}

$code.=<<___;
.fpu	neon

.type	iotas64, %object
.align 5
iotas64:
	.quad	0x0000000000000001
	.quad	0x0000000000008082
	.quad	0x800000000000808a
	.quad	0x8000000080008000
	.quad	0x000000000000808b
	.quad	0x0000000080000001
	.quad	0x8000000080008081
	.quad	0x8000000000008009
	.quad	0x000000000000008a
	.quad	0x0000000000000088
	.quad	0x0000000080008009
	.quad	0x000000008000000a
	.quad	0x000000008000808b
	.quad	0x800000000000008b
	.quad	0x8000000000008089
	.quad	0x8000000000008003
	.quad	0x8000000000008002
	.quad	0x8000000000000080
	.quad	0x000000000000800a
	.quad	0x800000008000000a
	.quad	0x8000000080008081
	.quad	0x8000000000008080
	.quad	0x0000000080000001
	.quad	0x8000000080008008
.size	iotas64,.-iotas64

.type	KeccakF1600_neon, %function
.align	5
KeccakF1600_neon:
	add	r1, r0, #16
	adr	r2, iotas64
	mov	r3, #24			@ loop counter
	b	.Loop_neon

.align	4
.Loop_neon:
	@ Theta
	vst1.64		{q4},  [r0:64]		@ offload A[0..1][4]
	veor		q13, q0,  q5		@ A[0..1][0]^A[2..3][0]
	vst1.64		{d18}, [r1:64]		@ offload A[2][4]
	veor		q14, q1,  q6		@ A[0..1][1]^A[2..3][1]
	veor		q15, q2,  q7		@ A[0..1][2]^A[2..3][2]
	veor		d26, d26, d27		@ C[0]=A[0][0]^A[1][0]^A[2][0]^A[3][0]
	veor		d27, d28, d29		@ C[1]=A[0][1]^A[1][1]^A[2][1]^A[3][1]
	veor		q14, q3,  q8		@ A[0..1][3]^A[2..3][3]
	veor		q4,  q4,  q9		@ A[0..1][4]^A[2..3][4]
	veor		d30, d30, d31		@ C[2]=A[0][2]^A[1][2]^A[2][2]^A[3][2]
	veor		d31, d28, d29		@ C[3]=A[0][3]^A[1][3]^A[2][3]^A[3][3]
	veor		d25, d8,  d9		@ C[4]=A[0][4]^A[1][4]^A[2][4]^A[3][4]
	veor		q13, q13, q10		@ C[0..1]^=A[4][0..1]
	veor		q14, q15, q11		@ C[2..3]^=A[4][2..3]
	veor		d25, d25, d24		@ C[4]^=A[4][4]

	vadd.u64	q4,  q13, q13		@ C[0..1]<<1
	vadd.u64	q15, q14, q14		@ C[2..3]<<1
	vadd.u64	d18, d25, d25		@ C[4]<<1
	vsri.u64	q4,  q13, #63		@ ROL64(C[0..1],1)
	vsri.u64	q15, q14, #63		@ ROL64(C[2..3],1)
	vsri.u64	d18, d25, #63		@ ROL64(C[4],1)
	veor		d25, d25, d9		@ D[0] = C[4] ^= ROL64(C[1],1)
	veor		q13, q13, q15		@ D[1..2] = C[0..1] ^ ROL64(C[2..3],1)
	veor		d28, d28, d18		@ D[3] = C[2] ^= ROL64(C[4],1)
	veor		d29, d29, d8		@ D[4] = C[3] ^= ROL64(C[0],1)

	veor		d0,  d0,  d25		@ A[0][0] ^= C[4]
	veor		d1,  d1,  d25		@ A[1][0] ^= C[4]
	veor		d10, d10, d25		@ A[2][0] ^= C[4]
	veor		d11, d11, d25		@ A[3][0] ^= C[4]
	veor		d20, d20, d25		@ A[4][0] ^= C[4]

	veor		d2,  d2,  d26		@ A[0][1] ^= D[1]
	veor		d3,  d3,  d26		@ A[1][1] ^= D[1]
	veor		d12, d12, d26		@ A[2][1] ^= D[1]
	veor		d13, d13, d26		@ A[3][1] ^= D[1]
	veor		d21, d21, d26		@ A[4][1] ^= D[1]
	vmov		d26, d27

	veor		d6,  d6,  d28		@ A[0][3] ^= C[2]
	veor		d7,  d7,  d28		@ A[1][3] ^= C[2]
	veor		d16, d16, d28		@ A[2][3] ^= C[2]
	veor		d17, d17, d28		@ A[3][3] ^= C[2]
	veor		d23, d23, d28		@ A[4][3] ^= C[2]
	vld1.64		{q4},  [r0:64]		@ restore A[0..1][4]
	vmov		d28, d29

	vld1.64		{d18}, [r1:64]		@ restore A[2][4]
	veor		q2,  q2,  q13		@ A[0..1][2] ^= D[2]
	veor		q7,  q7,  q13		@ A[2..3][2] ^= D[2]
	veor		d22, d22, d27		@ A[4][2]    ^= D[2]

	veor		q4,  q4,  q14		@ A[0..1][4] ^= C[3]
	veor		q9,  q9,  q14		@ A[2..3][4] ^= C[3]
	veor		d24, d24, d29		@ A[4][4]    ^= C[3]

	@ Rho + Pi
	vmov		d26, d2			@ C[1] = A[0][1]
	vshl.u64	d2,  d3,  #44
	vmov		d27, d4			@ C[2] = A[0][2]
	vshl.u64	d4,  d14, #43
	vmov		d28, d6			@ C[3] = A[0][3]
	vshl.u64	d6,  d17, #21
	vmov		d29, d8			@ C[4] = A[0][4]
	vshl.u64	d8,  d24, #14
	vsri.u64	d2,  d3,  #64-44	@ A[0][1] = ROL64(A[1][1], rhotates[1][1])
	vsri.u64	d4,  d14, #64-43	@ A[0][2] = ROL64(A[2][2], rhotates[2][2])
	vsri.u64	d6,  d17, #64-21	@ A[0][3] = ROL64(A[3][3], rhotates[3][3])
	vsri.u64	d8,  d24, #64-14	@ A[0][4] = ROL64(A[4][4], rhotates[4][4])

	vshl.u64	d3,  d9,  #20
	vshl.u64	d14, d16, #25
	vshl.u64	d17, d15, #15
	vshl.u64	d24, d21, #2
	vsri.u64	d3,  d9,  #64-20	@ A[1][1] = ROL64(A[1][4], rhotates[1][4])
	vsri.u64	d14, d16, #64-25	@ A[2][2] = ROL64(A[2][3], rhotates[2][3])
	vsri.u64	d17, d15, #64-15	@ A[3][3] = ROL64(A[3][2], rhotates[3][2])
	vsri.u64	d24, d21, #64-2		@ A[4][4] = ROL64(A[4][1], rhotates[4][1])

	vshl.u64	d9,  d22, #61
	@ vshl.u64	d16, d19, #8
	vshl.u64	d15, d12, #10
	vshl.u64	d21, d7,  #55
	vsri.u64	d9,  d22, #64-61	@ A[1][4] = ROL64(A[4][2], rhotates[4][2])
	vext.8		d16, d19, d19, #8-1	@ A[2][3] = ROL64(A[3][4], rhotates[3][4])
	vsri.u64	d15, d12, #64-10	@ A[3][2] = ROL64(A[2][1], rhotates[2][1])
	vsri.u64	d21, d7,  #64-55	@ A[4][1] = ROL64(A[1][3], rhotates[1][3])

	vshl.u64	d22, d18, #39
	@ vshl.u64	d19, d23, #56
	vshl.u64	d12, d5,  #6
	vshl.u64	d7,  d13, #45
	vsri.u64	d22, d18, #64-39	@ A[4][2] = ROL64(A[2][4], rhotates[2][4])
	vext.8		d19, d23, d23, #8-7	@ A[3][4] = ROL64(A[4][3], rhotates[4][3])
	vsri.u64	d12, d5,  #64-6		@ A[2][1] = ROL64(A[1][2], rhotates[1][2])
	vsri.u64	d7,  d13, #64-45	@ A[1][3] = ROL64(A[3][1], rhotates[3][1])

	vshl.u64	d18, d20, #18
	vshl.u64	d23, d11, #41
	vshl.u64	d5,  d10, #3
	vshl.u64	d13, d1,  #36
	vsri.u64	d18, d20, #64-18	@ A[2][4] = ROL64(A[4][0], rhotates[4][0])
	vsri.u64	d23, d11, #64-41	@ A[4][3] = ROL64(A[3][0], rhotates[3][0])
	vsri.u64	d5,  d10, #64-3		@ A[1][2] = ROL64(A[2][0], rhotates[2][0])
	vsri.u64	d13, d1,  #64-36	@ A[3][1] = ROL64(A[1][0], rhotates[1][0])

	vshl.u64	d1,  d28, #28
	vshl.u64	d10, d26, #1
	vshl.u64	d11, d29, #27
	vshl.u64	d20, d27, #62
	vsri.u64	d1,  d28, #64-28	@ A[1][0] = ROL64(C[3],    rhotates[0][3])
	vsri.u64	d10, d26, #64-1		@ A[2][0] = ROL64(C[1],    rhotates[0][1])
	vsri.u64	d11, d29, #64-27	@ A[3][0] = ROL64(C[4],    rhotates[0][4])
	vsri.u64	d20, d27, #64-62	@ A[4][0] = ROL64(C[2],    rhotates[0][2])

	@ Chi + Iota
	vbic		q13, q2,  q1
	vbic		q14, q3,  q2
	vbic		q15, q4,  q3
	veor		q13, q13, q0		@ A[0..1][0] ^ (~A[0..1][1] & A[0..1][2])
	veor		q14, q14, q1		@ A[0..1][1] ^ (~A[0..1][2] & A[0..1][3])
	veor		q2,  q2,  q15		@ A[0..1][2] ^= (~A[0..1][3] & A[0..1][4])
	vst1.64		{q13}, [r0:64]		@ offload A[0..1][0]
	vbic		q13, q0,  q4
	vbic		q15, q1,  q0
	vmov		q1,  q14		@ A[0..1][1]
	veor		q3,  q3,  q13		@ A[0..1][3] ^= (~A[0..1][4] & A[0..1][0])
	veor		q4,  q4,  q15		@ A[0..1][4] ^= (~A[0..1][0] & A[0..1][1])

	vbic		q13, q7,  q6
	vmov		q0,  q5			@ A[2..3][0]
	vbic		q14, q8,  q7
	vmov		q15, q6			@ A[2..3][1]
	veor		q5,  q5,  q13		@ A[2..3][0] ^= (~A[2..3][1] & A[2..3][2])
	vbic		q13, q9,  q8
	veor		q6,  q6,  q14		@ A[2..3][1] ^= (~A[2..3][2] & A[2..3][3])
	vbic		q14, q0,  q9
	veor		q7,  q7,  q13		@ A[2..3][2] ^= (~A[2..3][3] & A[2..3][4])
	vbic		q13, q15, q0
	veor		q8,  q8,  q14		@ A[2..3][3] ^= (~A[2..3][4] & A[2..3][0])
	vmov		q14, q10		@ A[4][0..1]
	veor		q9,  q9,  q13		@ A[2..3][4] ^= (~A[2..3][0] & A[2..3][1])

	vld1.64		d25, [r2:64]!		@ Iota[i++]
	vbic		d26, d22, d21
	vbic		d27, d23, d22
	vld1.64		{q0}, [r0:64]		@ restore A[0..1][0]
	veor		d20, d20, d26		@ A[4][0] ^= (~A[4][1] & A[4][2])
	vbic		d26, d24, d23
	veor		d21, d21, d27		@ A[4][1] ^= (~A[4][2] & A[4][3])
	vbic		d27, d28, d24
	veor		d22, d22, d26		@ A[4][2] ^= (~A[4][3] & A[4][4])
	vbic		d26, d29, d28
	veor		d23, d23, d27		@ A[4][3] ^= (~A[4][4] & A[4][0])
	veor		d0,  d0,  d25		@ A[0][0] ^= Iota[i]
	veor		d24, d24, d26		@ A[4][4] ^= (~A[4][0] & A[4][1])

	subs	r3, r3, #1
	bne	.Loop_neon

	bx	lr
.size	KeccakF1600_neon,.-KeccakF1600_neon

.global	SHA3_absorb_neon
.type	SHA3_absorb_neon, %function
.align	5
SHA3_absorb_neon:
	stmdb	sp!, {r4-r6,lr}
	vstmdb	sp!, {d8-d15}

	mov	r4, r1			@ inp
	mov	r5, r2			@ len
	mov	r6, r3			@ bsz

	vld1.32	{d0}, [r0:64]!		@ A[0][0]
	vld1.32	{d2}, [r0:64]!		@ A[0][1]
	vld1.32	{d4}, [r0:64]!		@ A[0][2]
	vld1.32	{d6}, [r0:64]!		@ A[0][3]
	vld1.32	{d8}, [r0:64]!		@ A[0][4]

	vld1.32	{d1}, [r0:64]!		@ A[1][0]
	vld1.32	{d3}, [r0:64]!		@ A[1][1]
	vld1.32	{d5}, [r0:64]!		@ A[1][2]
	vld1.32	{d7}, [r0:64]!		@ A[1][3]
	vld1.32	{d9}, [r0:64]!		@ A[1][4]

	vld1.32	{d10}, [r0:64]!		@ A[2][0]
	vld1.32	{d12}, [r0:64]!		@ A[2][1]
	vld1.32	{d14}, [r0:64]!		@ A[2][2]
	vld1.32	{d16}, [r0:64]!		@ A[2][3]
	vld1.32	{d18}, [r0:64]!		@ A[2][4]

	vld1.32	{d11}, [r0:64]!		@ A[3][0]
	vld1.32	{d13}, [r0:64]!		@ A[3][1]
	vld1.32	{d15}, [r0:64]!		@ A[3][2]
	vld1.32	{d17}, [r0:64]!		@ A[3][3]
	vld1.32	{d19}, [r0:64]!		@ A[3][4]

	vld1.32	{d20-d23}, [r0:64]!	@ A[4][0..3]
	vld1.32	{d24}, [r0:64]		@ A[4][4]
	sub	r0, r0, #24*8		@ rewind
	b	.Loop_absorb_neon

.align	4
.Loop_absorb_neon:
	subs	r12, r5, r6		@ len - bsz
	blo	.Labsorbed_neon
	mov	r5, r12

	vld1.8	{d31}, [r4]!		@ endian-neutral loads...
	cmp	r6, #8*2
	veor	d0, d0, d31		@ A[0][0] ^= *inp++
	blo	.Lprocess_neon
	vld1.8	{d31}, [r4]!
	veor	d2, d2, d31		@ A[0][1] ^= *inp++
	beq	.Lprocess_neon
	vld1.8	{d31}, [r4]!
	cmp	r6, #8*4
	veor	d4, d4, d31		@ A[0][2] ^= *inp++
	blo	.Lprocess_neon
	vld1.8	{d31}, [r4]!
	veor	d6, d6, d31		@ A[0][3] ^= *inp++
	beq	.Lprocess_neon
	vld1.8	{d31},[r4]!
	cmp	r6, #8*6
	veor	d8, d8, d31		@ A[0][4] ^= *inp++
	blo	.Lprocess_neon

	vld1.8	{d31}, [r4]!
	veor	d1, d1, d31		@ A[1][0] ^= *inp++
	beq	.Lprocess_neon
	vld1.8	{d31}, [r4]!
	cmp	r6, #8*8
	veor	d3, d3, d31		@ A[1][1] ^= *inp++
	blo	.Lprocess_neon
	vld1.8	{d31}, [r4]!
	veor	d5, d5, d31		@ A[1][2] ^= *inp++
	beq	.Lprocess_neon
	vld1.8	{d31}, [r4]!
	cmp	r6, #8*10
	veor	d7, d7, d31		@ A[1][3] ^= *inp++
	blo	.Lprocess_neon
	vld1.8	{d31}, [r4]!
	veor	d9, d9, d31		@ A[1][4] ^= *inp++
	beq	.Lprocess_neon

	vld1.8	{d31}, [r4]!
	cmp	r6, #8*12
	veor	d10, d10, d31		@ A[2][0] ^= *inp++
	blo	.Lprocess_neon
	vld1.8	{d31}, [r4]!
	veor	d12, d12, d31		@ A[2][1] ^= *inp++
	beq	.Lprocess_neon
	vld1.8	{d31}, [r4]!
	cmp	r6, #8*14
	veor	d14, d14, d31		@ A[2][2] ^= *inp++
	blo	.Lprocess_neon
	vld1.8	{d31}, [r4]!
	veor	d16, d16, d31		@ A[2][3] ^= *inp++
	beq	.Lprocess_neon
	vld1.8	{d31}, [r4]!
	cmp	r6, #8*16
	veor	d18, d18, d31		@ A[2][4] ^= *inp++
	blo	.Lprocess_neon

	vld1.8	{d31}, [r4]!
	veor	d11, d11, d31		@ A[3][0] ^= *inp++
	beq	.Lprocess_neon
	vld1.8	{d31}, [r4]!
	cmp	r6, #8*18
	veor	d13, d13, d31		@ A[3][1] ^= *inp++
	blo	.Lprocess_neon
	vld1.8	{d31}, [r4]!
	veor	d15, d15, d31		@ A[3][2] ^= *inp++
	beq	.Lprocess_neon
	vld1.8	{d31}, [r4]!
	cmp	r6, #8*20
	veor	d17, d17, d31		@ A[3][3] ^= *inp++
	blo	.Lprocess_neon
	vld1.8	{d31}, [r4]!
	veor	d19, d19, d31		@ A[3][4] ^= *inp++
	beq	.Lprocess_neon

	vld1.8	{d31}, [r4]!
	cmp	r6, #8*22
	veor	d20, d20, d31		@ A[4][0] ^= *inp++
	blo	.Lprocess_neon
	vld1.8	{d31}, [r4]!
	veor	d21, d21, d31		@ A[4][1] ^= *inp++
	beq	.Lprocess_neon
	vld1.8	{d31}, [r4]!
	cmp	r6, #8*24
	veor	d22, d22, d31		@ A[4][2] ^= *inp++
	blo	.Lprocess_neon
	vld1.8	{d31}, [r4]!
	veor	d23, d23, d31		@ A[4][3] ^= *inp++
	beq	.Lprocess_neon
	vld1.8	{d31}, [r4]!
	veor	d24, d24, d31		@ A[4][4] ^= *inp++

.Lprocess_neon:
	bl	KeccakF1600_neon
	b 	.Loop_absorb_neon

.align	4
.Labsorbed_neon:
	vst1.32	{d0}, [r0:64]!		@ A[0][0..4]
	vst1.32	{d2}, [r0:64]!
	vst1.32	{d4}, [r0:64]!
	vst1.32	{d6}, [r0:64]!
	vst1.32	{d8}, [r0:64]!

	vst1.32	{d1}, [r0:64]!		@ A[1][0..4]
	vst1.32	{d3}, [r0:64]!
	vst1.32	{d5}, [r0:64]!
	vst1.32	{d7}, [r0:64]!
	vst1.32	{d9}, [r0:64]!

	vst1.32	{d10}, [r0:64]!		@ A[2][0..4]
	vst1.32	{d12}, [r0:64]!
	vst1.32	{d14}, [r0:64]!
	vst1.32	{d16}, [r0:64]!
	vst1.32	{d18}, [r0:64]!

	vst1.32	{d11}, [r0:64]!		@ A[3][0..4]
	vst1.32	{d13}, [r0:64]!
	vst1.32	{d15}, [r0:64]!
	vst1.32	{d17}, [r0:64]!
	vst1.32	{d19}, [r0:64]!

	vst1.32	{d20-d23}, [r0:64]!	@ A[4][0..4]
	vst1.32	{d24}, [r0:64]

	mov	r0, r5			@ return value
	vldmia	sp!, {d8-d15}
	ldmia	sp!, {r4-r6,pc}
.size	SHA3_absorb_neon,.-SHA3_absorb_neon

.global	SHA3_squeeze_neon
.type	SHA3_squeeze_neon, %function
.align	5
SHA3_squeeze_neon:
	stmdb	sp!, {r4-r6,lr}

	mov	r4, r1			@ out
	mov	r5, r2			@ len
	mov	r6, r3			@ bsz
	mov	r12, r0			@ A_flat
	mov	r14, r3			@ bsz
	b	.Loop_squeeze_neon

.align	4
.Loop_squeeze_neon:
	cmp	r5, #8
	blo	.Lsqueeze_neon_tail
	vld1.32	{d0}, [r12]!
	vst1.8	{d0}, [r4]!		@ endian-neutral store

	subs	r5, r5, #8		@ len -= 8
	beq	.Lsqueeze_neon_done

	subs	r14, r14, #8		@ bsz -= 8
	bhi	.Loop_squeeze_neon

	vstmdb	sp!,  {d8-d15}

	vld1.32	{d0}, [r0:64]!		@ A[0][0..4]
	vld1.32	{d2}, [r0:64]!
	vld1.32	{d4}, [r0:64]!
	vld1.32	{d6}, [r0:64]!
	vld1.32	{d8}, [r0:64]!

	vld1.32	{d1}, [r0:64]!		@ A[1][0..4]
	vld1.32	{d3}, [r0:64]!
	vld1.32	{d5}, [r0:64]!
	vld1.32	{d7}, [r0:64]!
	vld1.32	{d9}, [r0:64]!

	vld1.32	{d10}, [r0:64]!		@ A[2][0..4]
	vld1.32	{d12}, [r0:64]!
	vld1.32	{d14}, [r0:64]!
	vld1.32	{d16}, [r0:64]!
	vld1.32	{d18}, [r0:64]!

	vld1.32	{d11}, [r0:64]!		@ A[3][0..4]
	vld1.32	{d13}, [r0:64]!
	vld1.32	{d15}, [r0:64]!
	vld1.32	{d17}, [r0:64]!
	vld1.32	{d19}, [r0:64]!

	vld1.32	{d20-d23}, [r0:64]!	@ A[4][0..4]
	vld1.32	{d24}, [r0:64]
	sub	r0, r0, #24*8		@ rewind

	bl	KeccakF1600_neon

	mov	r12, r0			@ A_flat
	vst1.32	{d0}, [r0:64]!		@ A[0][0..4]
	vst1.32	{d2}, [r0:64]!
	vst1.32	{d4}, [r0:64]!
	vst1.32	{d6}, [r0:64]!
	vst1.32	{d8}, [r0:64]!

	vst1.32	{d1}, [r0:64]!		@ A[1][0..4]
	vst1.32	{d3}, [r0:64]!
	vst1.32	{d5}, [r0:64]!
	vst1.32	{d7}, [r0:64]!
	vst1.32	{d9}, [r0:64]!

	vst1.32	{d10}, [r0:64]!		@ A[2][0..4]
	vst1.32	{d12}, [r0:64]!
	vst1.32	{d14}, [r0:64]!
	vst1.32	{d16}, [r0:64]!
	vst1.32	{d18}, [r0:64]!

	vst1.32	{d11}, [r0:64]!		@ A[3][0..4]
	vst1.32	{d13}, [r0:64]!
	vst1.32	{d15}, [r0:64]!
	vst1.32	{d17}, [r0:64]!
	vst1.32	{d19}, [r0:64]!

	vst1.32	{d20-d23}, [r0:64]!	@ A[4][0..4]
	mov	r14, r6			@ bsz
	vst1.32	{d24}, [r0:64]
	mov	r0,  r12		@ rewind

	vldmia	sp!, {d8-d15}
	b	.Loop_squeeze_neon

.align	4
.Lsqueeze_neon_tail:
	ldmia	r12, {r2,r3}
	cmp	r5, #2
	strb	r2, [r4],#1		@ endian-neutral store
	lsr	r2, r2, #8
	blo	.Lsqueeze_neon_done
	strb	r2, [r4], #1
	lsr	r2, r2, #8
	beq	.Lsqueeze_neon_done
	strb	r2, [r4], #1
	lsr	r2, r2, #8
	cmp	r5, #4
	blo	.Lsqueeze_neon_done
	strb	r2, [r4], #1
	beq	.Lsqueeze_neon_done

	strb	r3, [r4], #1
	lsr	r3, r3, #8
	cmp	r5, #6
	blo	.Lsqueeze_neon_done
	strb	r3, [r4], #1
	lsr	r3, r3, #8
	beq	.Lsqueeze_neon_done
	strb	r3, [r4], #1

.Lsqueeze_neon_done:
	ldmia	sp!, {r4-r6,pc}
.size	SHA3_squeeze_neon,.-SHA3_squeeze_neon
.asciz	"Keccak-1600 absorb and squeeze for ARMv4/NEON, CRYPTOGAMS by <appro\@openssl.org>"
.align	2
___

print $code;

close STDOUT; # enforce flush
