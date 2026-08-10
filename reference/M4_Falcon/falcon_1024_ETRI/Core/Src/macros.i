#ifndef MACROS_I
#define MACROS_I

.macro load a, a0, a1, a2, a3, mem0, mem1, mem2, mem3
  ldr.w \a0, [\a, \mem0]
  ldr.w \a1, [\a, \mem1]
  ldr.w \a2, [\a, \mem2]
  ldr.w \a3, [\a, \mem3]
.endm

.macro load3 a, a0, a1, a2, mem0, mem1, mem2
  ldr.w \a0, [\a, \mem0]
  ldr.w \a1, [\a, \mem1]
  ldr.w \a2, [\a, \mem2]
.endm

.macro load3_update a, a0, a1, a2, mem0, mem1, mem2
  ldr.w \a0, [\a], \mem0
  ldr.w \a1, [\a], \mem1
  ldr.w \a2, [\a], \mem2
.endm

.macro store a, a0, a1, a2, a3, mem0, mem1, mem2, mem3
  str.w \a0, [\a, \mem0]
  str.w \a1, [\a, \mem1]
  str.w \a2, [\a, \mem2]
  str.w \a3, [\a, \mem3]
.endm

.macro store_inv_gs a, a0, a1, a2, a3, mem0, mem1, mem2, mem3
  str.w \a1, [\a, \mem1]
  str.w \a2, [\a, \mem2]
  str.w \a3, [\a, \mem3]
  str.w \a0, [\a], \mem0
.endm

.macro store_update a, a0, a1, a2, a3
  str.w \a0, [\a], #4
  str.w \a1, [\a], #4
  str.w \a2, [\a], #4
  str.w \a3, [\a], #4
.endm

.macro store3 a, a0, a1, a2, mem0, mem1, mem2
  str.w \a0, [\a], \mem0
  str.w \a1, [\a], \mem1
  str.w \a2, [\a], \mem2
.endm

.macro store3_update a, a0, a1, a2, mem0, mem1, mem2
  str.w \a0, [\a], \mem0
  str.w \a1, [\a], \mem1
  str.w \a2, [\a], \mem2
.endm

.macro doublebarrett_fast a, tmp, tmp2, q, barrettconst1, barrettconst2
  smlawb \tmp, \barrettconst1, \a, \barrettconst2
  smlabt \tmp, \q, \tmp, \a
  smlawt \tmp2, \barrettconst1, \a, \barrettconst2
  smulbt \tmp2, \q, \tmp2
  add    \tmp2, \a, \tmp2, lsl#16
  pkhbt  \a, \tmp, \tmp2
.endm

.macro half_barrett poly0, poly1, poly2, poly3, barrettconst, barrettconst2, tmp, tmp2, q
  doublebarrett_fast \poly0, \tmp, \tmp2, \q, \barrettconst, \barrettconst2
  doublebarrett_fast \poly1, \tmp, \tmp2, \q, \barrettconst, \barrettconst2
  doublebarrett_fast \poly2, \tmp, \tmp2, \q, \barrettconst, \barrettconst2
  doublebarrett_fast \poly3, \tmp, \tmp2, \q, \barrettconst, \barrettconst2
.endm

.macro montgomery q, qinv, a, tmp
  smulbt \tmp, \a, \qinv
  smlabb \tmp, \q, \tmp, \a
.endm

.macro montgomery_inplace q, qinv, a, tmp
  smulbt \tmp, \a, \qinv
  smlabb \a, \q, \tmp, \a
.endm

.macro doublemontgomery a, tmp, tmp2, q, qinv, montconst
  smulbb \tmp2, \a, \montconst
  montgomery \q, \qinv, \tmp2, \tmp
  smultb \a, \a, \montconst
  montgomery \q, \qinv, \a, \tmp2
  pkhtb \a, \tmp2, \tmp, asr#16
.endm

.macro doubleplantardmul a0, a1, tmp, tmp2, qprime, q, qa
  smulbb	\tmp, \a0, \a1
  smultt	\tmp2, \a0, \a1
  mul		\tmp, \tmp, \qprime
  mul		\tmp2, \tmp2, \qprime
  smlatb	\tmp, \tmp, \q, \qa
  smlatb	\tmp2, \tmp2, \q, \qa
  pkhtb		\a0, \tmp2, \tmp, asr#16
.endm

.macro mul_twiddle_plant a, twiddle, tmp, q, qa
	smulwb \tmp, \twiddle, \a
	smulwt \a,   \twiddle, \a
	smlabb \tmp, \tmp, \q, \qa
	smlabb \a, \a, \q, \qa
	pkhtb \a, \a, \tmp, asr#16
.endm

.macro mul_twiddle_plant_gs dst, src, twiddle, tmp, q, qa
	smulwb \tmp, \twiddle, \src
	smulwt \src, \twiddle, \src
	smlabb \tmp, \tmp, \q, \qa
	smlabb \src, \src, \q, \qa
	pkhtb \dst, \src, \tmp, asr#16
.endm

.macro mul_twiddle_plant2 a, twiddle1, twiddle2, tmp, q, qa
	smulwb \tmp, \twiddle1, \a
	smulwt \a,   \twiddle2, \a
	smlabb \tmp, \tmp, \q, \qa
	smlabb \a, \a, \q, \qa
	pkhtb \a, \a, \tmp, asr#16
.endm

#endif /* MACROS_I */