#include "macros.i"

.syntax unified
.cpu cortex-m4
.thumb


//계수 4개에 대한 (계수가 2개씩 패킹된 register 2개 c0, c1)iNTT_GS의 1-layer GS butterfly 연산
.macro _1_layer_inv_gs_doublebutterfly c0, c1, xi0, xi1, twiddle1, twiddle2, q, qa, tmp
	vmov \twiddle1, \xi0
	vmov \twiddle2, \xi1
	pkhbt \tmp, \c0, \c1, lsl#16		//tmp = a_0 || a_2
	pkhtb \c1, \c1, \c0, asr#16		//tmp2 = a_1 || a_3
	sadd16.w \c0, \tmp, \c1				//c0 = a_0+a_1 || a_2+a_3, 이건 연산 끝 값 유지
	ssub16.w \c1, \tmp, \c1				//c1 = a_0-a_1 || a_2-a_3
	mul_twiddle_plant2 \c1, \twiddle1, \twiddle2, \tmp, \q, \qa	//c1 = (a_0-a_1)*zeta1 || (a_2-a_3)*zeta2
	pkhbt \tmp, \c0, \c1, lsl#16		//tmp = a_0+a_1 || (a_0-a_1)*zeta1
	pkhtb \c1, \c1, \c0, asr#16		//c1 = a_2+a_3 || (a_2-a_3)*zeta2
	mov \c0, \tmp						//c0 = a_0+a_1 || (a_0-a_1)*zeta1
.endm

.macro _1_layer_four_inv_gs_doublebutterfly c0, c1, c2, c3, c4, c5, c6, c7, xi0, xi1, xi2, xi3, xi4, xi5, xi6, xi7, twiddle1, twiddle2, q, qa, tmp
	_1_layer_inv_gs_doublebutterfly \c0, \c1, \xi0, \xi1, \twiddle1, \twiddle2, \q, \qa, \tmp
	_1_layer_inv_gs_doublebutterfly \c2, \c3, \xi2, \xi3, \twiddle1, \twiddle2, \q, \qa, \tmp
	_1_layer_inv_gs_doublebutterfly \c4, \c5, \xi4, \xi5, \twiddle1, \twiddle2, \q, \qa, \tmp
	_1_layer_inv_gs_doublebutterfly \c6, \c7, \xi6, \xi7, \twiddle1, \twiddle2, \q, \qa, \tmp
.endm

.macro inv_gs_doublebutterfly c0, c1, twiddle1, q, qa, tmp, tmp2
	ssub16 \tmp, \c0, \c1
	sadd16 \c0, \c0, \c1
	mul_twiddle_plant_gs \c1, \tmp, \twiddle1, \tmp2, \q, \qa
.endm

.macro _2_5_layer_four_inv_gs_doublebutterfly c0, c1, c2, c3, c4, c5, c6, c7, xi0, xi1, xi2, xi3 twiddle1, q, qa, tmp, tmp2	//tmp2=twiddle2=r11
	vmov \twiddle1, \xi0
	inv_gs_doublebutterfly \c0, \c1, \twiddle1, \q, \qa, \tmp, \tmp2
	vmov \twiddle1, \xi1
	inv_gs_doublebutterfly \c2, \c3, \twiddle1, \q, \qa, \tmp, \tmp2
	vmov \twiddle1, \xi2
	inv_gs_doublebutterfly \c4, \c5, \twiddle1, \q, \qa, \tmp, \tmp2
	vmov \twiddle1, \xi3
	inv_gs_doublebutterfly \c6, \c7, \twiddle1, \q, \qa, \tmp, \tmp2
.endm

.macro _3_6_8_layer_four_inv_gs_doublebutterfly c0, c1, c2, c3, c4, c5, c6, c7, xi0, xi1, twiddle1, q, qa, tmp, tmp2	//tmp2=twiddle2=r11
	vmov \twiddle1, \xi0
	inv_gs_doublebutterfly \c0, \c2, \twiddle1, \q, \qa, \tmp, \tmp2
	inv_gs_doublebutterfly \c1, \c3, \twiddle1, \q, \qa, \tmp, \tmp2
	vmov \twiddle1, \xi1
	inv_gs_doublebutterfly \c4, \c6, \twiddle1, \q, \qa, \tmp, \tmp2
	inv_gs_doublebutterfly \c5, \c7, \twiddle1, \q, \qa, \tmp, \tmp2
.endm

.macro _4_7_9_layer_four_inv_gs_doublebutterfly c0, c1, c2, c3, c4, c5, c6, c7, xi0, twiddle1, q, qa, tmp, tmp2	//tmp2=twiddle2=r11
	vmov \twiddle1, \xi0
	inv_gs_doublebutterfly \c0, \c4, \twiddle1, \q, \qa, \tmp, \tmp2
	inv_gs_doublebutterfly \c1, \c5, \twiddle1, \q, \qa, \tmp, \tmp2
	inv_gs_doublebutterfly \c2, \c6, \twiddle1, \q, \qa, \tmp, \tmp2
	inv_gs_doublebutterfly \c3, \c7, \twiddle1, \q, \qa, \tmp, \tmp2
.endm

.macro _8_mul_twiddle_plant c0, c1, c2, c3, c4, c5, c6, c7, twiddle, tmp, q, qa
	mul_twiddle_plant \c0, \twiddle, \tmp, \q, \qa
	mul_twiddle_plant \c1, \twiddle, \tmp, \q, \qa
	mul_twiddle_plant \c2, \twiddle, \tmp, \q, \qa
	mul_twiddle_plant \c3, \twiddle, \tmp, \q, \qa
	mul_twiddle_plant \c4, \twiddle, \tmp, \q, \qa
	mul_twiddle_plant \c5, \twiddle, \tmp, \q, \qa
	mul_twiddle_plant \c6, \twiddle, \tmp, \q, \qa
	mul_twiddle_plant \c7, \twiddle, \tmp, \q, \qa
.endm

.global intt_fast
.type intt_fast, %function
.align 2
intt_fast:
	//push {r4-r11, r14}				//callee-save register, r4-r11, r14 register를 stack에 저장
	push {r0-r11, r14}
	vpush.w {s0-s24}				//callee-save register, FP register s16-s24를 stack에 저장
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
	tmp2		.req r11	//inverse NTT GS를 위한 tmp
	tmp3 		.req r0		//barrett 감산을 위한 tmp

	// movw qa, #26632
	// r12에 q값 저장
	movw q, #12289	//0x3001

	//barrett reduction을 위한 값 설정
	//barrettconst1 = 0xfffaaac8 = -(2^32/q)
	movw barrettconst1, 0xaac8
	movt barrettconst1, 0xfffa
	vmov s0, barrettconst1		//추후에 계속 사용할거니까 저장
	//barrettconst2 = 2^15
	movw barrettconst2, #32768
	vmov s1, barrettconst2		//추후에 계속 사용할거니까 저장

	.equ strincr, 4				//계수를 2개씩 4byte씩 읽는다

	//1~4 layer======================================================================
	.equ distance, 16			//한 블록의 크기(byte), 계수 8개