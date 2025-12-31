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

.macro _2_5_8_layer_four_inv_gs_doublebutterfly c0, c1, c2, c3, c4, c5, c6, c7, xi0, xi1, xi2, xi3 twiddle1, q, qa, tmp, tmp2	//tmp2=twiddle2=r11
	vmov \twiddle1, \xi0
	inv_gs_doublebutterfly \c0, \c1, \twiddle1, \q, \qa, \tmp, \tmp2
	vmov \twiddle1, \xi1
	inv_gs_doublebutterfly \c2, \c3, \twiddle1, \q, \qa, \tmp, \tmp2
	vmov \twiddle1, \xi2
	inv_gs_doublebutterfly \c4, \c5, \twiddle1, \q, \qa, \tmp, \tmp2
	vmov \twiddle1, \xi3
	inv_gs_doublebutterfly \c6, \c7, \twiddle1, \q, \qa, \tmp, \tmp2
.endm

.macro _3_6_9_layer_four_inv_gs_doublebutterfly c0, c1, c2, c3, c4, c5, c6, c7, xi0, xi1, twiddle1, q, qa, tmp, tmp2	//tmp2=twiddle2=r11
	vmov \twiddle1, \xi0
	inv_gs_doublebutterfly \c0, \c2, \twiddle1, \q, \qa, \tmp, \tmp2
	inv_gs_doublebutterfly \c1, \c3, \twiddle1, \q, \qa, \tmp, \tmp2
	vmov \twiddle1, \xi1
	inv_gs_doublebutterfly \c4, \c6, \twiddle1, \q, \qa, \tmp, \tmp2
	inv_gs_doublebutterfly \c5, \c7, \twiddle1, \q, \qa, \tmp, \tmp2
.endm

.macro _4_7_10_layer_four_inv_gs_doublebutterfly c0, c1, c2, c3, c4, c5, c6, c7, xi0, twiddle1, q, qa, tmp, tmp2	//tmp2=twiddle2=r11
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
	add tmp, poly, #64*16*2		//64개 block, block당 계수 16개, 계수당 2byte
	vmov s2, tmp				//바깥 loop 종료조건 s2에 저장
	1:
		vldm twiddle_ptr!, {s8-s22}	//계수 15개 읽어오기
		load poly, poly0, poly1, poly2, poly3, #0, #distance/4, #2*distance/4, #3*distance/4
		load poly, poly4, poly5, poly6, poly7, #distance, #5*distance/4, #6*distance/4, #7*distance/4

		vmov s3, poly		//poly값 저장, butterfly에서 qa가 사용되는데 qa, poly모두 r0 레지스터 사용
		movw qa, #24578		//r0에 2*q값 저장

		//1-layer
		_1_layer_four_inv_gs_doublebutterfly poly0, poly1, poly2, poly3, poly4, poly5, poly6, poly7, s8, s9, s10, s11, s12, s13, s14, s15, twiddle1, twiddle2, q, qa, tmp //1-layer 계수 8개에 대한 GS-butterfly

		//2-layer
		_2_5_8_layer_four_inv_gs_doublebutterfly poly0, poly1, poly2, poly3, poly4, poly5, poly6, poly7, s16, s17, s18, s19, twiddle1, q, qa, tmp, tmp2	//1-layer 계수 8개에 대한 GS-butterfly


		//2-layer 감산 a_(4*i), i=[0,127]
		vmov barrettconst1, s0
		vmov barrettconst2, s1
		half_barrett poly0, poly2, poly4, poly6, barrettconst1, barrettconst2, tmp, tmp3, q
		movw qa, #24578		//barrett에서 r0 레지스터를 tmp3으로 사용했으므로 값을 다시 할당

		//3-layer
		_3_6_9_layer_four_inv_gs_doublebutterfly poly0, poly1, poly2, poly3, poly4, poly5, poly6, poly7, s20, s21, twiddle1, q, qa, tmp, tmp2		//tmp2=twiddle2=r11

		//4-layer
		_4_7_10_layer_four_inv_gs_doublebutterfly poly0, poly1, poly2, poly3, poly4, poly5, poly6, poly7, s22, twiddle1, q, qa, tmp, tmp2			//tmp2=twiddle2=r11

		//4-layer 감산 a_(4*i), i=[0,127]
		vmov barrettconst1, s0
		vmov barrettconst2, s1
		doublebarrett_fast poly0, tmp, tmp3, q, barrettconst1, barrettconst2
		doublebarrett_fast poly1, tmp, tmp3, q, barrettconst1, barrettconst2
		movw qa, #24578		//barrett에서 r0 레지스터를 tmp3으로 사용했으므로 값을 다시 할당

		//store
		vmov poly, s3

		store_update poly, poly0, poly1, poly2, poly3
		store_update poly, poly4, poly5, poly6, poly7

		vmov tmp, s2
		cmp.w poly, tmp
	bne.w 1b

	sub.w poly, #64*16*2	//poly 포인터 처음으로 돌리기

	//5-7 layer=========================================================================================================================================================================
	.equ distance, 128
	add tmp, poly, #8*128*2		//8개 block, block당 계수 128개, 계수당 2byte
	vmov s2, tmp				//loop 종료조건 s2에 저장
	1:
		vldm twiddle_ptr!, {s8-s14}	//계수 7개 읽어오기, layer-5 4개, layer-6 2개, layer-7 1개
		//a0-a1 시작================================================================================
		load poly, poly0, poly1, poly2, poly3, #0, #distance/4, #2*distance/4, #3*distance/4
		load poly, poly4, poly5, poly6, poly7, #distance, #5*distance/4, #6*distance/4, #7*distance/4

		vmov s3, poly		//poly값 저장, butterfly에서 qa가 사용되는데 qa, poly모두 r0 레지스터 사용
		movw qa, #24578		//r0에 2*q값 저장

		//5-layer
		_2_5_8_layer_four_inv_gs_doublebutterfly poly0, poly1, poly2, poly3, poly4, poly5, poly6, poly7, s8, s9, s10, s11, twiddle1, q, qa, tmp, tmp2	//tmp2=twiddle2=r11

		//6-layer
		_3_6_9_layer_four_inv_gs_doublebutterfly poly0, poly1, poly2, poly3, poly4, poly5, poly6, poly7, s12, s13, twiddle1, q, qa, tmp, tmp2		//tmp2=twiddle2=r11

		//6-layer 감산 (a0-a3, a8-a15, 64만큼 반복)
		vmov barrettconst1, s0
		vmov barrettconst2, s1
		doublebarrett_fast poly0, tmp, tmp3, q, barrettconst1, barrettconst2
		doublebarrett_fast poly4, tmp, tmp3, q, barrettconst1, barrettconst2
		movw qa, #24578		//barrett에서 r0 레지스터를 tmp3으로 사용했으므로 값을 다시 할당

		//7-layer
		_4_7_10_layer_four_inv_gs_doublebutterfly poly0, poly1, poly2, poly3, poly4, poly5, poly6, poly7, s14, twiddle1, q, qa, tmp, tmp2			//tmp2=twiddle2=r11

		//7-layer 감산 (a4-a7, a16-a31, 128만큼 반복)
		vmov barrettconst1, s0
		vmov barrettconst2, s1
		doublebarrett_fast poly1, tmp, tmp3, q, barrettconst1, barrettconst2

		//store
		vmov poly, s3
		store poly, poly4, poly5, poly6, poly7, #distance, #5*distance/4, #6*distance/4, #7*distance/4
		str.w poly1, [poly, #distance/4]
		str.w poly2, [poly, #2*distance/4]
		str.w poly3, [poly, #3*distance/4]
		str.w poly0, [poly], #4

		//a2-a3 시작================================================================================
		load poly, poly0, poly1, poly2, poly3, #0, #distance/4, #2*distance/4, #3*distance/4
		load poly, poly4, poly5, poly6, poly7, #distance, #5*distance/4, #6*distance/4, #7*distance/4

		vmov s3, poly
		movw qa, #24578		//r0에 2*q값 저장

		//5-layer
		_2_5_8_layer_four_inv_gs_doublebutterfly poly0, poly1, poly2, poly3, poly4, poly5, poly6, poly7, s8, s9, s10, s11, twiddle1, q, qa, tmp, tmp2	//tmp2=twiddle2=r11

		//6-layer
		_3_6_9_layer_four_inv_gs_doublebutterfly poly0, poly1, poly2, poly3, poly4, poly5, poly6, poly7, s12, s13, twiddle1, q, qa, tmp, tmp2		//tmp2=twiddle2=r11

		//6-layer 감산 (a0-a3, a8-a15, 64만큼 반복)
		vmov barrettconst1, s0
		vmov barrettconst2, s1
		doublebarrett_fast poly0, tmp, tmp3, q, barrettconst1, barrettconst2
		doublebarrett_fast poly4, tmp, tmp3, q, barrettconst1, barrettconst2
		movw qa, #24578		//barrett에서 r0 레지스터를 tmp3으로 사용했으므로 값을 다시 할당

		//7-layer
		_4_7_10_layer_four_inv_gs_doublebutterfly poly0, poly1, poly2, poly3, poly4, poly5, poly6, poly7, s14, twiddle1, q, qa, tmp, tmp2			//tmp2=twiddle2=r11

		//7-layer 감산 (a4-a7, a16-a31, 128만큼 반복)
		vmov barrettconst1, s0
		vmov barrettconst2, s1
		doublebarrett_fast poly1, tmp, tmp3, q, barrettconst1, barrettconst2

		//store
		vmov poly, s3
		store poly, poly4, poly5, poly6, poly7, #distance, #5*distance/4, #6*distance/4, #7*distance/4
		str.w poly1, [poly, #distance/4]
		str.w poly2, [poly, #2*distance/4]
		str.w poly3, [poly, #3*distance/4]
		str.w poly0, [poly], #4

		//a4-a5 시작(a6-a7과 동일)================================================================================
		load poly, poly0, poly1, poly2, poly3, #0, #distance/4, #2*distance/4, #3*distance/4
		load poly, poly4, poly5, poly6, poly7, #distance, #5*distance/4, #6*distance/4, #7*distance/4

		vmov s3, poly		//poly값 저장, butterfly에서 qa가 사용되는데 qa, poly모두 r0 레지스터 사용
		movw qa, #24578		//r0에 2*q값 저장

		//5-layer
		_2_5_8_layer_four_inv_gs_doublebutterfly poly0, poly1, poly2, poly3, poly4, poly5, poly6, poly7, s8, s9, s10, s11, twiddle1, q, qa, tmp, tmp2	//tmp2=twiddle2=r11

		//5-layer 감산 (a4-a7, 32만큼 반복)
		vmov barrettconst1, s0
		vmov barrettconst2, s1
		doublebarrett_fast poly0, tmp, tmp3, q, barrettconst1, barrettconst2
		doublebarrett_fast poly2, tmp, tmp3, q, barrettconst1, barrettconst2
		doublebarrett_fast poly4, tmp, tmp3, q, barrettconst1, barrettconst2
		doublebarrett_fast poly6, tmp, tmp3, q, barrettconst1, barrettconst2
		movw qa, #24578		//barrett에서 r0 레지스터를 tmp3으로 사용했으므로 값을 다시 할당

		//6-layer
		_3_6_9_layer_four_inv_gs_doublebutterfly poly0, poly1, poly2, poly3, poly4, poly5, poly6, poly7, s12, s13, twiddle1, q, qa, tmp, tmp2		//tmp2=twiddle2=r11

		//7-layer
		_4_7_10_layer_four_inv_gs_doublebutterfly poly0, poly1, poly2, poly3, poly4, poly5, poly6, poly7, s14, twiddle1, q, qa, tmp, tmp2			//tmp2=twiddle2=r11

		//7-layer 감산 (a4-a7, a16-a31, 128만큼 반복)
		vmov barrettconst1, s0
		vmov barrettconst2, s1
		doublebarrett_fast poly0, tmp, tmp3, q, barrettconst1, barrettconst2
		doublebarrett_fast poly1, tmp, tmp3, q, barrettconst1, barrettconst2

		//store
		vmov poly, s3
		store poly, poly4, poly5, poly6, poly7, #distance, #5*distance/4, #6*distance/4, #7*distance/4
		str.w poly1, [poly, #distance/4]
		str.w poly2, [poly, #2*distance/4]
		str.w poly3, [poly, #3*distance/4]
		str.w poly0, [poly], #4

		//a6-a7 시작(a4-a5와 동일)================================================================================
		load poly, poly0, poly1, poly2, poly3, #0, #distance/4, #2*distance/4, #3*distance/4
		load poly, poly4, poly5, poly6, poly7, #distance, #5*distance/4, #6*distance/4, #7*distance/4

		vmov s3, poly		//poly값 저장, butterfly에서 qa가 사용되는데 qa, poly모두 r0 레지스터 사용
		movw qa, #24578		//r0에 2*q값 저장

		//5-layer
		_2_5_8_layer_four_inv_gs_doublebutterfly poly0, poly1, poly2, poly3, poly4, poly5, poly6, poly7, s8, s9, s10, s11, twiddle1, q, qa, tmp, tmp2	//tmp2=twiddle2=r11

		//5-layer 감산 (a4-a7, 32만큼 반복)
		vmov barrettconst1, s0
		vmov barrettconst2, s1
		doublebarrett_fast poly0, tmp, tmp3, q, barrettconst1, barrettconst2
		doublebarrett_fast poly2, tmp, tmp3, q, barrettconst1, barrettconst2
		doublebarrett_fast poly4, tmp, tmp3, q, barrettconst1, barrettconst2
		doublebarrett_fast poly6, tmp, tmp3, q, barrettconst1, barrettconst2
		movw qa, #24578		//barrett에서 r0 레지스터를 tmp3으로 사용했으므로 값을 다시 할당

		//6-layer
		_3_6_9_layer_four_inv_gs_doublebutterfly poly0, poly1, poly2, poly3, poly4, poly5, poly6, poly7, s12, s13, twiddle1, q, qa, tmp, tmp2		//tmp2=twiddle2=r11

		//7-layer
		_4_7_10_layer_four_inv_gs_doublebutterfly poly0, poly1, poly2, poly3, poly4, poly5, poly6, poly7, s14, twiddle1, q, qa, tmp, tmp2			//tmp2=twiddle2=r11

		//7-layer 감산 (a4-a7, a16-a31, 128만큼 반복)
		vmov barrettconst1, s0
		vmov barrettconst2, s1
		doublebarrett_fast poly0, tmp, tmp3, q, barrettconst1, barrettconst2
		doublebarrett_fast poly1, tmp, tmp3, q, barrettconst1, barrettconst2

		//store
		vmov poly, s3
		store poly, poly4, poly5, poly6, poly7, #distance, #5*distance/4, #6*distance/4, #7*distance/4
		str.w poly1, [poly, #distance/4]
		str.w poly2, [poly, #2*distance/4]
		str.w poly3, [poly, #3*distance/4]
		str.w poly0, [poly], #4

		//a8-a15는 동일하게 동작함 loop로 처리해도 될듯?================================================================================
		add tmp, poly, #16		//loop 4번만 반복할거임, loop 1번에 poly는 4씩 증가함
		vmov s4, tmp			//종료조건 저장
		2:
			//a8-a9 시작================================================================================
			load poly, poly0, poly1, poly2, poly3, #0, #distance/4, #2*distance/4, #3*distance/4
			load poly, poly4, poly5, poly6, poly7, #distance, #5*distance/4, #6*distance/4, #7*distance/4

			vmov s3, poly		//poly값 저장, butterfly에서 qa가 사용되는데 qa, poly모두 r0 레지스터 사용
			movw qa, #24578		//r0에 2*q값 저장

			//5-layer
			_2_5_8_layer_four_inv_gs_doublebutterfly poly0, poly1, poly2, poly3, poly4, poly5, poly6, poly7, s8, s9, s10, s11, twiddle1, q, qa, tmp, tmp2	//tmp2=twiddle2=r11

			//6-layer
			_3_6_9_layer_four_inv_gs_doublebutterfly poly0, poly1, poly2, poly3, poly4, poly5, poly6, poly7, s12, s13, twiddle1, q, qa, tmp, tmp2		//tmp2=twiddle2=r11

			//6-layer 감산 (a0-a3, a8-a15, 64만큼 반복)
			vmov barrettconst1, s0
			vmov barrettconst2, s1
			doublebarrett_fast poly0, tmp, tmp3, q, barrettconst1, barrettconst2
			doublebarrett_fast poly4, tmp, tmp3, q, barrettconst1, barrettconst2
			movw qa, #24578		//barrett에서 r0 레지스터를 tmp3으로 사용했으므로 값을 다시 할당

			//7-layer
			_4_7_10_layer_four_inv_gs_doublebutterfly poly0, poly1, poly2, poly3, poly4, poly5, poly6, poly7, s14, twiddle1, q, qa, tmp, tmp2			//tmp2=twiddle2=r11

			//7-layer 감산 (a4-a7, a16-a31, 128만큼 반복)
			vmov barrettconst1, s0
			vmov barrettconst2, s1
			doublebarrett_fast poly1, tmp, tmp3, q, barrettconst1, barrettconst2

			//store
			vmov poly, s3
			store poly, poly4, poly5, poly6, poly7, #distance, #5*distance/4, #6*distance/4, #7*distance/4
			str.w poly1, [poly, #distance/4]
			str.w poly2, [poly, #2*distance/4]
			str.w poly3, [poly, #3*distance/4]
			str.w poly0, [poly], #4

			vmov tmp, s4
			cmp.w poly, tmp
		bne.w 2b

		add poly, poly, #224	//다음 블록까지 이동, 원래 256이지만 이전 내부loop에서 32(계수 16개)만큼은 증가하였으니 224만 더해줌
		vmov tmp, s2
		cmp.w poly, tmp
	bne.w 1b

	sub.w poly, #8*128*2	//poly 포인터 처음으로 돌리기

	//8~10 layer=================================================================================================================================================================================================================
	.equ distance, 1024

	vldm twiddle_ptr!, {s8-s14}	//계수 7개 읽어오기, layer-8 4개, layer-9 2개, layer-10 1개
	//a0-a3 시작================================================================================
	//a0a1, a2a3 두번
	.rept 2
	load poly, poly0, poly1, poly2, poly3, #0, #distance/4, #2*distance/4, #3*distance/4
	load poly, poly4, poly5, poly6, poly7, #distance, #5*distance/4, #6*distance/4, #7*distance/4

	vmov s3, poly		//poly값 저장, butterfly에서 qa가 사용되는데 qa, poly모두 r0 레지스터 사용
	movw qa, #24578		//r0에 2*q값 저장

	//8-layer
	_2_5_8_layer_four_inv_gs_doublebutterfly poly0, poly1, poly2, poly3, poly4, poly5, poly6, poly7, s8, s9, s10, s11, twiddle1, q, qa, tmp, tmp2		//tmp2=twiddle2=r11

	//8-layer 감산 (a0-a3, a8-a15, a32-63, 256만큼 반복)
	vmov barrettconst1, s0
	vmov barrettconst2, s1
	doublebarrett_fast poly0, tmp, tmp3, q, barrettconst1, barrettconst2
	doublebarrett_fast poly2, tmp, tmp3, q, barrettconst1, barrettconst2
	doublebarrett_fast poly4, tmp, tmp3, q, barrettconst1, barrettconst2
	doublebarrett_fast poly6, tmp, tmp3, q, barrettconst1, barrettconst2
	movw qa, #24578		//barrett에서 r0 레지스터를 tmp3으로 사용했으므로 값을 다시 할당

	//9-layer
	_3_6_9_layer_four_inv_gs_doublebutterfly poly0, poly1, poly2, poly3, poly4, poly5, poly6, poly7, s12, s13, twiddle1, q, qa, tmp, tmp2			//tmp2=twiddle2=r11

	//10-layer
	_4_7_10_layer_four_inv_gs_doublebutterfly poly0, poly1, poly2, poly3, poly4, poly5, poly6, poly7, s14, twiddle1, q, qa, tmp, tmp2			//tmp2=twiddle2=r11

	//1/N = 0xB1C6 F686
	movw twiddle1, 0xf686
	movt twiddle1, 0xb1c6
	_8_mul_twiddle_plant poly0, poly1, poly2, poly3, poly4, poly5, poly6, poly7, twiddle1, tmp, q, qa

	//store
	vmov poly, s3
	store poly, poly4, poly5, poly6, poly7, #distance, #5*distance/4, #6*distance/4, #7*distance/4
	str.w poly1, [poly, #distance/4]
	str.w poly2, [poly, #2*distance/4]
	str.w poly3, [poly, #3*distance/4]
	str.w poly0, [poly], #4
	.endr

	//a4-a7 시작========================================================================================================================================================================
	.rept 2
	load poly, poly0, poly1, poly2, poly3, #0, #distance/4, #2*distance/4, #3*distance/4
	load poly, poly4, poly5, poly6, poly7, #distance, #5*distance/4, #6*distance/4, #7*distance/4

	vmov s3, poly		//poly값 저장, butterfly에서 qa가 사용되는데 qa, poly모두 r0 레지스터 사용
	movw qa, #24578		//r0에 2*q값 저장

	//8-layer
	_2_5_8_layer_four_inv_gs_doublebutterfly poly0, poly1, poly2, poly3, poly4, poly5, poly6, poly7, s8, s9, s10, s11, twiddle1, q, qa, tmp, tmp2		//tmp2=twiddle2=r11

	//9-layer
	_3_6_9_layer_four_inv_gs_doublebutterfly poly0, poly1, poly2, poly3, poly4, poly5, poly6, poly7, s12, s13, twiddle1, q, qa, tmp, tmp2			//tmp2=twiddle2=r11

	vmov barrettconst1, s0
	vmov barrettconst2, s1
	doublebarrett_fast poly0, tmp, tmp3, q, barrettconst1, barrettconst2
	doublebarrett_fast poly4, tmp, tmp3, q, barrettconst1, barrettconst2
	movw qa, #24578		//barrett에서 r0 레지스터를 tmp3으로 사용했으므로 값을 다시 할당

	//10-layer
	_4_7_10_layer_four_inv_gs_doublebutterfly poly0, poly1, poly2, poly3, poly4, poly5, poly6, poly7, s14, twiddle1, q, qa, tmp, tmp2			//tmp2=twiddle2=r11

	//1/N = 0xB1C6 F686
	movw twiddle1, 0xf686
	movt twiddle1, 0xb1c6
	_8_mul_twiddle_plant poly0, poly1, poly2, poly3, poly4, poly5, poly6, poly7, twiddle1, tmp, q, qa

	//store
	vmov poly, s3
	store poly, poly4, poly5, poly6, poly7, #distance, #5*distance/4, #6*distance/4, #7*distance/4
	str.w poly1, [poly, #distance/4]
	str.w poly2, [poly, #2*distance/4]
	str.w poly3, [poly, #3*distance/4]
	str.w poly0, [poly], #4
	.endr

	//a8--a15========================================================================================================================================================================
	.rept 4
	load poly, poly0, poly1, poly2, poly3, #0, #distance/4, #2*distance/4, #3*distance/4
	load poly, poly4, poly5, poly6, poly7, #distance, #5*distance/4, #6*distance/4, #7*distance/4

	vmov s3, poly		//poly값 저장, butterfly에서 qa가 사용되는데 qa, poly모두 r0 레지스터 사용
	movw qa, #24578		//r0에 2*q값 저장

	//8-layer
	_2_5_8_layer_four_inv_gs_doublebutterfly poly0, poly1, poly2, poly3, poly4, poly5, poly6, poly7, s8, s9, s10, s11, twiddle1, q, qa, tmp, tmp2		//tmp2=twiddle2=r11

	//8-layer 감산 (a0-a3, a8-a15, a32-63, 256만큼 반복)
	vmov barrettconst1, s0
	vmov barrettconst2, s1
	doublebarrett_fast poly0, tmp, tmp3, q, barrettconst1, barrettconst2
	doublebarrett_fast poly2, tmp, tmp3, q, barrettconst1, barrettconst2
	doublebarrett_fast poly4, tmp, tmp3, q, barrettconst1, barrettconst2
	doublebarrett_fast poly6, tmp, tmp3, q, barrettconst1, barrettconst2
	movw qa, #24578		//barrett에서 r0 레지스터를 tmp3으로 사용했으므로 값을 다시 할당

	//9-layer
	_3_6_9_layer_four_inv_gs_doublebutterfly poly0, poly1, poly2, poly3, poly4, poly5, poly6, poly7, s12, s13, twiddle1, q, qa, tmp, tmp2			//tmp2=twiddle2=r11

	//10-layer
	_4_7_10_layer_four_inv_gs_doublebutterfly poly0, poly1, poly2, poly3, poly4, poly5, poly6, poly7, s14, twiddle1, q, qa, tmp, tmp2			//tmp2=twiddle2=r11

	//1/N = 0xB1C6 F686
	movw twiddle1, 0xf686
	movt twiddle1, 0xb1c6
	_8_mul_twiddle_plant poly0, poly1, poly2, poly3, poly4, poly5, poly6, poly7, twiddle1, tmp, q, qa

	//store
	vmov poly, s3
	store poly, poly4, poly5, poly6, poly7, #distance, #5*distance/4, #6*distance/4, #7*distance/4
	str.w poly1, [poly, #distance/4]
	str.w poly2, [poly, #2*distance/4]
	str.w poly3, [poly, #3*distance/4]
	str.w poly0, [poly], #4
	.endr

	//a16-a31는 동일하게 동작함 loop로 처리=============================================================================================================================================
	.rept 8
	load poly, poly0, poly1, poly2, poly3, #0, #distance/4, #2*distance/4, #3*distance/4
	load poly, poly4, poly5, poly6, poly7, #distance, #5*distance/4, #6*distance/4, #7*distance/4

	vmov s3, poly		//poly값 저장, butterfly에서 qa가 사용되는데 qa, poly모두 r0 레지스터 사용
	movw qa, #24578		//r0에 2*q값 저장

	//8-layer
	_2_5_8_layer_four_inv_gs_doublebutterfly poly0, poly1, poly2, poly3, poly4, poly5, poly6, poly7, s8, s9, s10, s11, twiddle1, q, qa, tmp, tmp2		//tmp2=twiddle2=r11

	//9-layer
	_3_6_9_layer_four_inv_gs_doublebutterfly poly0, poly1, poly2, poly3, poly4, poly5, poly6, poly7, s12, s13, twiddle1, q, qa, tmp, tmp2			//tmp2=twiddle2=r11

	vmov barrettconst1, s0
	vmov barrettconst2, s1
	doublebarrett_fast poly0, tmp, tmp3, q, barrettconst1, barrettconst2
	doublebarrett_fast poly4, tmp, tmp3, q, barrettconst1, barrettconst2
	movw qa, #24578		//barrett에서 r0 레지스터를 tmp3으로 사용했으므로 값을 다시 할당

	//10-layer
	_4_7_10_layer_four_inv_gs_doublebutterfly poly0, poly1, poly2, poly3, poly4, poly5, poly6, poly7, s14, twiddle1, q, qa, tmp, tmp2			//tmp2=twiddle2=r11

	//1/N = 0xB1C6 F686
	movw twiddle1, 0xf686
	movt twiddle1, 0xb1c6
	movw qa, #24578
	_8_mul_twiddle_plant poly0, poly1, poly2, poly3, poly4, poly5, poly6, poly7, twiddle1, tmp, q, qa

	//store
	vmov poly, s3
	store poly, poly4, poly5, poly6, poly7, #distance, #5*distance/4, #6*distance/4, #7*distance/4
	str.w poly1, [poly, #distance/4]
	str.w poly2, [poly, #2*distance/4]
	str.w poly3, [poly, #3*distance/4]
	str.w poly0, [poly], #4
	.endr

	//a32-a63은 동일하게 동작함 loop로 처리=============================================================================================================================================
	.rept 16
	load poly, poly0, poly1, poly2, poly3, #0, #distance/4, #2*distance/4, #3*distance/4
	load poly, poly4, poly5, poly6, poly7, #distance, #5*distance/4, #6*distance/4, #7*distance/4

	vmov s3, poly		//poly값 저장, butterfly에서 qa가 사용되는데 qa, poly모두 r0 레지스터 사용
	movw qa, #24578		//r0에 2*q값 저장

	//8-layer
	_2_5_8_layer_four_inv_gs_doublebutterfly poly0, poly1, poly2, poly3, poly4, poly5, poly6, poly7, s8, s9, s10, s11, twiddle1, q, qa, tmp, tmp2		//tmp2=twiddle2=r11

	//8-layer 감산 (a0-a3, a8-a15, a32-63, 256만큼 반복)
	vmov barrettconst1, s0
	vmov barrettconst2, s1
	doublebarrett_fast poly0, tmp, tmp3, q, barrettconst1, barrettconst2
	doublebarrett_fast poly2, tmp, tmp3, q, barrettconst1, barrettconst2
	doublebarrett_fast poly4, tmp, tmp3, q, barrettconst1, barrettconst2
	doublebarrett_fast poly6, tmp, tmp3, q, barrettconst1, barrettconst2
	movw qa, #24578		//barrett에서 r0 레지스터를 tmp3으로 사용했으므로 값을 다시 할당

	//9-layer
	_3_6_9_layer_four_inv_gs_doublebutterfly poly0, poly1, poly2, poly3, poly4, poly5, poly6, poly7, s12, s13, twiddle1, q, qa, tmp, tmp2			//tmp2=twiddle2=r11

	//10-layer
	_4_7_10_layer_four_inv_gs_doublebutterfly poly0, poly1, poly2, poly3, poly4, poly5, poly6, poly7, s14, twiddle1, q, qa, tmp, tmp2			//tmp2=twiddle2=r11

	//1/N = 0xB1C6 F686
	movw twiddle1, 0xf686
	movt twiddle1, 0xb1c6
	_8_mul_twiddle_plant poly0, poly1, poly2, poly3, poly4, poly5, poly6, poly7, twiddle1, tmp, q, qa

	//store
	vmov poly, s3
	store poly, poly4, poly5, poly6, poly7, #distance, #5*distance/4, #6*distance/4, #7*distance/4
	str.w poly1, [poly, #distance/4]
	str.w poly2, [poly, #2*distance/4]
	str.w poly3, [poly, #3*distance/4]
	str.w poly0, [poly], #4
	.endr

	//a64-a127은 동일하게 동작함 loop로 처리=============================================================================================================================================
	.rept 32
	load poly, poly0, poly1, poly2, poly3, #0, #distance/4, #2*distance/4, #3*distance/4
	load poly, poly4, poly5, poly6, poly7, #distance, #5*distance/4, #6*distance/4, #7*distance/4

	vmov s3, poly		//poly값 저장, butterfly에서 qa가 사용되는데 qa, poly모두 r0 레지스터 사용
	movw qa, #24578		//r0에 2*q값 저장

	//8-layer
	_2_5_8_layer_four_inv_gs_doublebutterfly poly0, poly1, poly2, poly3, poly4, poly5, poly6, poly7, s8, s9, s10, s11, twiddle1, q, qa, tmp, tmp2		//tmp2=twiddle2=r11

	//9-layer
	_3_6_9_layer_four_inv_gs_doublebutterfly poly0, poly1, poly2, poly3, poly4, poly5, poly6, poly7, s12, s13, twiddle1, q, qa, tmp, tmp2			//tmp2=twiddle2=r11

	vmov barrettconst1, s0
	vmov barrettconst2, s1
	doublebarrett_fast poly0, tmp, tmp3, q, barrettconst1, barrettconst2
	doublebarrett_fast poly4, tmp, tmp3, q, barrettconst1, barrettconst2
	movw qa, #24578		//barrett에서 r0 레지스터를 tmp3으로 사용했으므로 값을 다시 할당

	//10-layer
	_4_7_10_layer_four_inv_gs_doublebutterfly poly0, poly1, poly2, poly3, poly4, poly5, poly6, poly7, s14, twiddle1, q, qa, tmp, tmp2			//tmp2=twiddle2=r11

	//1/N = 0xB1C6 F686
	movw twiddle1, 0xf686
	movt twiddle1, 0xb1c6
	_8_mul_twiddle_plant poly0, poly1, poly2, poly3, poly4, poly5, poly6, poly7, twiddle1, tmp, q, qa

	//store
	vmov poly, s3
	store poly, poly4, poly5, poly6, poly7, #distance, #5*distance/4, #6*distance/4, #7*distance/4
	str.w poly1, [poly, #distance/4]
	str.w poly2, [poly, #2*distance/4]
	str.w poly3, [poly, #3*distance/4]
	str.w poly0, [poly], #4
	.endr

	vpop.w	{s0-s24}
	pop		{r0-r11, pc}
