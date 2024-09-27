#include "macros.i"

.syntax unified
.cpu cortex-m4
.thumb

.global barrett_fast
.type barrett_fast, %function
barrett_fast:
	push	{r4-r11,r14}
	//감산을 원하는 a는 r0으로 들어왔다고 가정,  a = #0x7148 = 29000
	movw	r3,	#0xcca8		//barrett const 1
	movt	r3,	#0xfffc		//barrett const 1
	movw	r4,	#0x8000		//barrett const 2
	movw	r5, #0x3001		//falcon q

	smlawb	r1,r3,r0,r4
	smlabt	r0,r5,r1,r0
	pop		{r4-r11,pc}

//입력으로 a와 b가 들어와서 c=a+b를 출력하는 함수?
.global add_basic
.type add_basic, %function
add_basic:
	push	{r4-r11,r14}
	add 	r0,r0,r1
	pop		{r4-r11,pc}

.global instruction_test
.type instruction_test, %function
instruction_test:
	push	{r4-r11,r14}
	movw	r2, #0xaac8		//barrett const 1
	movt	r2, #0xfffa		//barrett const 1
	movw	r3,	0x8000		//barrett const 2
	movw	r4, 0x7148		//a_b
	movt	r4, 0x5fb4		//a_t
	movw	r5, 0x3001		//falcon q

	smlawb	r6, r2, r4, r3
	smlabt	r6, r5, r6, r4
	mov 	r0, r6
	//smlawt	r7, r2, r4, r3
	//smulbt	r7, r5, r7
	//add		r7, r4, r7, lsl#16
	//pkhbt	r0, r6, r7
	pop		{r4-r11,pc}


.global instruction_test2
.type instruction_test2, %function
instruction_test2:
	push	{r4-r11,r14}
	movw	r2, #0x5049		//barrett const 1
	movt	r2, #0xffec		//barrett const 1
	movw	r3,	0x8000		//barrett const 2
	movw	r4, 0x7148		//a_b
	movt	r4, 0x5fb4		//a_t
	movw	r5, 0xd01		//kyber q

	smlawb	r6, r2, r4, r3
	mov 	r0, r6
	//smlabt	r6, r5, r6, r4
	//smlawt	r7, r2, r4, r3
	//smulbt	r7, r5, r7
	//add		r7, r4, r7, lsl#16
	//pkhbt	r0, r6, r7
	pop		{r4-r11,pc}
//위에는 테스트 코드 아래가 메인 ntt.s 코드


//내가 만든 마지막 layer CT butterfly
/*
	@brief 16-bit 계수 2개가 packing된 32-bit를 받아서 해당 32-bit 내부에서 CT butterfly 연산
	@param a		16-bit 계수 2개가 packing되어 있는 32-bit register
	@param twiddle	16-bit의 상위 16-bit에 곱해지는 zetas(좌측 항은 LSB에 저장, 우측 항은 MSB에 저장)
	@param tmp		연산 과정에 필요한 tmp register
	@param q		plantard multiplication 과정에 사용되는 q
	@param qa		plantard multiplication 과정에 사용되는 q*q
*/
.macro last_layer_butterfly_plant a, twiddle, tmp, q, qa
	smulwt \tmp, \twiddle, \a		//a의 상위 16-bit에 우측항이 저장되어있으므로, smulwt을 활용하여 상위 16-bit와 zetas를 곱해줌
	smlabb \tmp, \tmp, \q, \qa
	//위의 연산까지 하고 tmp의 상위 16-bit를 가져와서 a의 LSB와는 더해주고, a의 MSB와는 뺄셈을 수행
.endm

.macro last_layer_doublebutterfly_plant a0, a1, twiddle0, twiddle1, tmp, tmp2, q, qa
	smulwt \tmp, \twiddle0, \a0		//a0의 상위 16-bit에 우측항이 저장되어있으므로, smulwt을 활용하여 상위 16-bit와 zetas를 곱해줌
	smlabb \tmp, \tmp, \q, \qa
	smulwt \tmp2, \twiddle1, \a1	//a1의 상위 16-bit에 우측항이 저장되어있으므로, smulwt을 활용하여 상위 16-bit와 zetas를 곱해줌
	smlabb \tmp2, \tmp2, \q, \qa
	pkhtb \tmp, \tmp2, \tmp, asr#16	//tmp의 상위 16-bit에 tmp2의 상위 16-bit를 하위 16-bit에 tmp의 상위 16-bit를 저장 tmp = tmp2 || tmp
	//pkhtb \tmp2, \a1, \a0, asr#16	//tmp2에 a0와 a1의 상위 16-bit를 저장, tmp2 = a1 || a0
	pkhbt \tmp2, \a0, \a1, lsl#16		//a0에 a0와 a1의 하위 16-bit를 저장, tmp2 = a1 || a0
	//uadd16 \a0, \tmp2, \tmp			//a0, a1의 하위 16-bit와 zetas 곱의 덧셈을 a에 저장
	uadd16.w \twiddle0, \tmp2, \tmp			//a0, a1의 하위 16-bit와 zetas 곱의 덧셈을 a에 저장
	usub16.w \tmp, \tmp2, \tmp		//a0, a1의 하위 16-bit와 zetas 곱의 차이를 tmp에 저장
	pkhbt \a0, \twiddle0, \tmp, lsl#16	//a0의 값 모으기, 하위 16-bit에는 더하기 값, 상위 16-bit에는 뺄셈 값
	pkhtb \a1, \tmp, \twiddle0, asr#16	//a1의 값 모으기, 하위 16-bit에는 더하기 값, 상위 16-bit에는 뺄셈 값
.endm

/**
	@brief 16-bit 계수 4개(16-bit 2개 packing된 a0, a1 / (a0,a1)이 쌍으로 CT butterfly)에 대해서 ct buttefly 2회 수행
	@param a0		ct butterfly의 좌측항에 해당하는 16-bit 계수 2개가 packing되어 있는 32-bit register
	@param a1		ct butterfly의 우측항에 해당하는 16-bit 계수 2개가 packing되어 있는 32-bit register
	@param twiddle	우측항의 packing된 16-bit 계수에 각각 곱해질 32-bit zetas register
	@param tmp		연산 과정에 필요한 tmp register
	@param q		plantard multiplication 과정에 사용되는 q
	@param qa		plantard multiplication 과정에 사용되는 q*q
*/
.macro doublebutterfly_plant a0, a1, twiddle, tmp, q, qa
	smulwb \tmp, \twiddle, \a1
	smulwt \a1, \twiddle, \a1
	smlabb \tmp, \tmp, \q, \qa
	smlabb \a1, \a1, \q, \qa
	pkhtb \tmp, \a1, \tmp, asr#16
	usub16 \a1, \a0, \tmp
	uadd16 \a0, \a0, \tmp
.endm

/**
	@brief 16-bit 계수 8개(16-bit 2개 packing된 a0, a1, a2, a3 / (a0,a1), (a2,a3)이 쌍)에 대해서 ct buttefly 4회 수행
	@brief a0-a1 ct-butterfly with twiddle0, a2-a3 ct butterfly with twiddle1
	@param a0a2	ct butterfly의 좌측항에 해당하는 16-bit 계수 2개가 packing되어 있는 32-bit register
	@param a1a3	ct butterfly의 우측항에 해당하는 16-bit 계수 2개가 packing되어 있는 32-bit register
	@param twiddle0	a0, a1의 butterfly 연산에 사용될 twiddle factor
	@param twiddle1	a2, a3의 butterfly 연산에 사용될 twiddle factor
	@param tmp		연산 과정에 필요한 tmp register
	@param q		plantard multiplication 과정에 사용되는 q
	@param qa		plantard multiplication 과정에 사용되는 q*q
*/
.macro two_doublebutterfly_plant a0, a1, a2, a3, twiddle0, twiddle1, tmp, q, qa
	doublebutterfly_plant \a0, \a1, \twiddle0, \tmp, \q, \qa
	doublebutterfly_plant \a2, \a3, \twiddle1, \tmp, \q, \qa
.endm

/*
	@brief 16-bit 계수 16개에 대해서 layer 3개 ct butterfly 연산 수행
	@detail zetas가 입력으로 들어오지 않고 streamlined되어있는 zetas 배열의 주소를 입력 받아 값을 뽑으며 진행
	@param c0-c7	16-bit 계수가 2개씩 packing되어있는 32-bit 값
	@param c0-c7	index가 오름차순으로 입력됨
	@param twiddle1,2	연산에 필요한 zetas를 저장하여 실제 연산에 사용할 레지스터
	@param twiddle_ptr	streamlined zetas의 주소를 가리키고 있는 레지스터
	@param q		plantard multiplication 과정에 사용되는 q
	@param qa		plantard multiplication 과정에 사용되는 q*q
	@param tmp		연산 과정에 필요한 tmp register
*/
.macro _3_layer_double_CT_16_plant c0, c1, c2, c3, c4, c5, c6, c7, twiddle1, twiddle2, twiddle_ptr, q, qa, tmp
	// layer 3
	ldr.w \twiddle1, [\twiddle_ptr], #4
	two_doublebutterfly_plant \c0, \c4, \c1, \c5, \twiddle1, \twiddle1, \tmp, \q, \qa
	two_doublebutterfly_plant \c2, \c6, \c3, \c7, \twiddle1, \twiddle1, \tmp, \q, \qa

	// layer 2
	ldrd \twiddle1, \twiddle2, [\twiddle_ptr], #8
	two_doublebutterfly_plant \c0, \c2, \c1, \c3, \twiddle1, \twiddle1, \tmp, \q, \qa

	two_doublebutterfly_plant \c4, \c6, \c5, \c7, \twiddle2, \twiddle2, \tmp, \q, \qa

	// layer 1
	ldrd \twiddle1, \twiddle2, [\twiddle_ptr], #8
	two_doublebutterfly_plant \c0, \c1, \c2, \c3, \twiddle1, \twiddle2, \tmp, \q, \qa

	ldrd \twiddle1, \twiddle2, [\twiddle_ptr], #8
	two_doublebutterfly_plant \c4, \c5, \c6, \c7, \twiddle1, \twiddle2, \tmp, \q, \qa
.endm

/**
	@brief 16-bit 계수 16개에 대해서 1,2,3-layer ct butterfly 연산 수행
	@detail zetas가 다 입력으로 들어오는 경우
	@param c0-c7	16-bit 계수가 2개씩 packing되어있는 32-bit 값
	@param c0-c7	index가 오름차순으로 입력됨
	@param xi0-xi6	1,2,3-layer ct butterfly에 사용될 zetas, 1,2,3 순서대로 들어옴
	@param twiddle1,2	연산에 필요한 zetas를 저장하여 실제 연산에 사용할 레지스터(zetas xi0-xi6이 FP register에 들어오기 때문에)
	@param q		plantard multiplication 과정에 사용되는 q
	@param qa		plantard multiplication 과정에 사용되는 q*q
	@param tmp		연산 과정에 필요한 tmp register
*/
.macro _3_layer_double_CT_16_plant_fp c0, c1, c2, c3, c4, c5, c6, c7, xi0, xi1, xi2, xi3, xi4, xi5, xi6, twiddle1, twiddle2, q, qa, tmp
	// layer 1
	vmov \twiddle1, \xi0
	two_doublebutterfly_plant \c0, \c4, \c1, \c5, \twiddle1, \twiddle1, \tmp, \q, \qa
	two_doublebutterfly_plant \c2, \c6, \c3, \c7, \twiddle1, \twiddle1, \tmp, \q, \qa

	// layer 2
	vmov \twiddle1, \xi1
	vmov \twiddle2, \xi2
	two_doublebutterfly_plant \c0, \c2, \c1, \c3, \twiddle1, \twiddle1, \tmp, \q, \qa
	two_doublebutterfly_plant \c4, \c6, \c5, \c7, \twiddle2, \twiddle2, \tmp, \q, \qa

	// layer 3
	vmov \twiddle1, \xi3
	vmov \twiddle2, \xi4
	two_doublebutterfly_plant \c0, \c1, \c2, \c3, \twiddle1, \twiddle2, \tmp, \q, \qa

	vmov \twiddle1, \xi5
	vmov \twiddle2, \xi6
	two_doublebutterfly_plant \c4, \c5, \c6, \c7, \twiddle1, \twiddle2, \tmp, \q, \qa
.endm

.macro _2_layer_double_CT_8_plant_fp c0, c1, c2, c3, xi0, xi1, xi2, twiddle1, twiddle2, q, qa, tmp
	// layer 1
	vmov \twiddle1, \xi0
	two_doublebutterfly_plant \c0, \c2, \c1, \c3, \twiddle1, \twiddle1, \tmp, \q, \qa

	// layer 2
	vmov \twiddle1, \xi1
	vmov \twiddle2, \xi2
	two_doublebutterfly_plant \c0, \c1, \c2, \c3, \twiddle1, \twiddle2, \tmp, \q, \qa
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

	// movw qa, #26632
	// r12에 q값 저장
	movw q, #12289	//0x3001

	//barrett reduction을 위한 값 설정
	//barrettconst1 = 0xfffaaac8 = -(2^32/q)
	movw barrettconst1, 0xaac8
	movt barrettconst1, 0xfffa
	vmov s3, barrettconst1		//추후에 계속 사용할거니까 저장
	//barrettconst2 = 2^15
	movw barrettconst2, #32768
	vmov s4, barrettconst2		//추후에 계속 사용할거니까 저장


	.equ strincr, 4			//읽어오는 계수 값 갱신, 2가 1개의 계수, 4이므로 2개의 계수, 처리하는 계수의 단위

	//1~3 layer========================================================================================================================================================================
	.equ distance, 1024		//한 블록의 수, 1~3 layer는 모두 한 블록으로 처리하므로 총 계수의 수
	// pre-load 15 twiddle factors to 15 FPU registers
	// s0-s7 used to temporary store 16 16-bit polys.
	vldm twiddle_ptr!, {s8-s14}	//s8-s15에 twiddle_ptr을 통해 1,2,3-layer zetas 7개 읽어오기, 읽어온 후 twiddle_ptr값 갱신

	//tmp에는 loop1의 종료 조건이 저장, poly register가 일정 부분에 도달하면 종료, layer-3의 distance가 64이므로 memory 기준 128을 이동하면 종료
	add tmp, poly, #strincr*64	//총 64번의 계수 읽기 과정 반복, 8개의 계수 저장 변수 존재, 각 레지스터가 128개의 계수를 처리해야함 즉, 64번의 계수 읽기 필요(1번에 2개씩 읽으므로)
	// s17: tmp
	vmov s17, tmp	//s24에 종료조건 저장

	1:
		// load a1, a3, ..., a15
		//vmov s15, poly	//s23에 계수 시작지점 저장, poly와 qa가 모두 r0를 사용하므로 값을 poly값을 s23에 저장해두어야함, falcon에선 재사용 안하니 안해도 될듯?
		//distance=64로 값을 8개 가져옴(16-bit 계수 2개씩 총 16개)(1,2,3-layer CT 수행할건데 3-layer가 distance가 64이므로)
		load poly, poly0, poly1, poly2, poly3, #0, #distance/4, #2*distance/4, #3*distance/4
		load poly, poly4, poly5, poly6, poly7, #distance, #5*distance/4, #6*distance/4, #7*distance/4

		vmov s2, poly		//poly값을 s2에 저장 후 다시 복구, butterfly 연산에서 qa=tmp2=poly=r0이므로

		movw qa, #24578		//qa=r0에 q*(2^1) 값 저장

		// 1,2,3-layer ct butterfly
		_3_layer_double_CT_16_plant_fp poly0, poly1, poly2, poly3, poly4, poly5, poly6, poly7, s8, s9, s10, s11, s12, s13, s14, twiddle1, twiddle2, q, qa, tmp

		//3-layer이후에 감산해주어야함
		vmov barrettconst1, s3
		vmov barrettconst2, s4
		half_barrett poly0, poly1, poly2, poly3, barrettconst1, barrettconst2, tmp, tmp2, q
		half_barrett poly4, poly5, poly6, poly7, barrettconst1, barrettconst2, tmp, tmp2, q
		vmov poly, s2				//poly값 복구

		store poly, poly4, poly5, poly6, poly7, #distance, #5*distance/4, #6*distance/4, #7*distance/4
		str.w poly1, [poly, #distance/4]
    	str.w poly2, [poly, #2*distance/4]
    	str.w poly3, [poly, #3*distance/4]
    	str.w poly0, [poly], #strincr			//poly0 값을 저장 후 poly값(주소값)을 4만큼 증가

		vmov tmp, s17
		cmp.w poly, tmp
	bne.w 1b
	//1~3 layer finished

	sub.w poly, #strincr*64		//poly 포인터를 처음으로 되돌려주기

	//4~6 layer========================================================================================================================================================================
	.equ distance, distance/8	//128, 해당 블록에 128개의 계수 존재

	add.w tmp, poly, #8*2*128	//바깥 loop의 종료조건, 총 8개의 큰 block 존재, 각 block에는 128개의 계수, 각 계수는 2의 주소 차지
	vmov s17, tmp				//바깥 loop의 종료조건 s17에 저장
	1:
		add tmp, poly, #8*strincr		//안쪽 loop의 종료조건 저장, 각 블록에서는 8번의 계수 읽기만 하면 됨. 하나의 polyk가 16개의 계수 처리
		vmov s18, tmp					//안쪽 loop의 종료조건 s18에 저장
		vldm twiddle_ptr!, {s8-s14}		//해당 블록을 처리할 zetas 7개 읽어오기
		2:
			.rept 8		//8개를 2개씩 처리하므로 4번 반복
			//8의 distance를 갖고 값을 읽어옴(계수 1개의 크기가 2이므로 실제 코드에서는 16씩 거리를 두고있음)
			load poly, poly0, poly1, poly2, poly3, #0, #distance/4, #2*distance/4, #3*distance/4
			load poly, poly4, poly5, poly6, poly7, #distance, #5*distance/4, #6*distance/4, #7*distance/4

			vmov s2, poly
			movw qa, #24578

			_3_layer_double_CT_16_plant_fp poly0, poly1, poly2, poly3, poly4, poly5, poly6, poly7, s8, s9, s10, s11, s12, s13, s14, twiddle1, twiddle2, q, qa, tmp

			vmov barrettconst1, s3
			vmov barrettconst2, s4
			half_barrett poly0, poly1, poly2, poly3, barrettconst1, barrettconst2, tmp, tmp2, q
			half_barrett poly4, poly5, poly6, poly7, barrettconst1, barrettconst2, tmp, tmp2, q
			vmov poly, s2				//poly값 복구

			store poly, poly4, poly5, poly6, poly7, #distance, #5*distance/4, #6*distance/4, #7*distance/4
			str.w poly1, [poly, #distance/4]
    		str.w poly2, [poly, #2*distance/4]
    		str.w poly3, [poly, #3*distance/4]
    		str.w poly0, [poly], #strincr			//poly0 값을 저장 후 poly값(주소값)을 4만큼 증가
    		.endr

    		vmov tmp, s18			//어차피 위의 코드들을 8번 반복할거면 이러한 loop2가 필요없지 않나?
    		cmp.w poly, tmp
    	bne.w 2b
    	add.w poly, #224		//다음 블록으로 이동, loop 2에서 이미 32만큼 증가한채로 나왔으니 224만 증가
    	vmov tmp, s17			//loop 1의 종료 조건 저장
    	cmp.w poly, tmp			//종료 조건 만족 여부 비교
    bne.w 1b					//만족안하면 종료
	//4~6 layer finished

	sub.w poly, #8*2*128			//poly의 포인터 처음으로 돌리기

	//layer 7~9, 10========================================================================================================================================================================
	.equ distance, distance/8	//16으로 변경, 한 블록의 크기 16(계수 8개)

	add.w tmp, poly, #64*16*2	//종료조건 설정, 총 64개의 블록, 각 블록에는 16개의 계수, 각 계수는 2의 주소 차지
	vmov s23, tmp				//종료조건 저장
	1:
		vldm twiddle_ptr!, {s8-s22}	//7,8,9-layer용 zetas 7개 s8-s14 + 10-layer용 zetas 8개 s15-s22 읽어오기
		//2개를 2개씩 처리하므로 1번 반복
		load poly, poly0, poly1, poly2, poly3, #0, #distance/4, #2*distance/4, #3*distance/4	//계수 2개씩 띄어서 값 읽어오기
		load poly, poly4, poly5, poly6, poly7, #distance, #5*distance/4, #6*distance/4, #7*distance/4

		vmov s2, poly
		movw qa, #24578

		//7,8,9-layer
		_3_layer_double_CT_16_plant_fp poly0, poly1, poly2, poly3, poly4, poly5, poly6, poly7, s8, s9, s10, s11, s12, s13, s14, twiddle1, twiddle2, q, qa, tmp

		//10-layer
		vmov s5, poly4		//poly4을 s5에 임시 저장 후 tmp register로 사용

		vmov twiddle1, s15
		vmov twiddle2, s16
		last_layer_doublebutterfly_plant poly0, poly1, twiddle1, twiddle2, tmp, poly4, q, qa		//poly4를 tmp2로 사용

		vmov twiddle1, s17
		vmov twiddle2, s18
		last_layer_doublebutterfly_plant poly2, poly3, twiddle1, twiddle2, tmp, poly4, q, qa		//poly4를 tmp2로 사용

		vmov poly4, s5
		vmov s5, poly0

		vmov twiddle1, s19
		vmov twiddle2, s20
		last_layer_doublebutterfly_plant poly4, poly5, twiddle1, twiddle2, tmp, poly0, q, qa		//poly0를 tmp2로 사용

		vmov twiddle1, s21
		vmov twiddle2, s22
		last_layer_doublebutterfly_plant poly6, poly7, twiddle1, twiddle2, tmp, poly0, q, qa		//poly0를 tmp2로 사용

		vmov poly0, s5		//값 복원
		vmov poly, s2

		store poly, poly4, poly5, poly6, poly7, #distance, #5*distance/4, #6*distance/4, #7*distance/4
		str.w poly1, [poly, #distance/4]
   		str.w poly2, [poly, #2*distance/4]
   		str.w poly3, [poly, #3*distance/4]
   		str.w poly0, [poly], #32			//poly0 값을 저장 후 poly값(주소값)을 32만큼 증가, 다음 블록으로 이동

    	vmov tmp, s23
    	cmp.w poly,tmp
    bne.w 1b


	vpop.w {s0-s26}
	pop {r0-r12, pc}
