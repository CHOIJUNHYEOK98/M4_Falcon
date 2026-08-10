.endm

.global ntt_fast
.type ntt_fast, %function
.align 2
ntt_fast:
	push {r0-r12, r14}				//callee-save register, r4-r11, r14 register를 stack에 저장
	vpush.w {s0-s26}				//callee-save register, FP register s16-s24를 stack에 저장
	poly         .req r0			//레지스터 이름 명명
	twiddle_ptr  .req r1
	poly0        .req r2
	poly1        .req r3
	poly2        .req r4
	poly3        .req r5
	poly4        .req r6
	poly5        .req r7
	poly6        .req r8
	poly7        .req r9
	twiddle1     .req r10
	twiddle2     .req r11
	barrettconst1 .req r10
	barrettconst2 .req r11
	###  qinv        .req r11 ### q^-1 mod 2^2n; n=16
	q           .req r12
	### at the top of r12
	qa          .req r0
	### qa=2^a q;a=3; at the bottom of r12
	tmp         .req r14
	tmp2		.req r0
