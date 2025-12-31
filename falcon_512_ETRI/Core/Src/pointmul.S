#include "macros.i"

.syntax unified
.cpu cortex-m4
.thumb

.global plantard_pointmul
.type plantard_pointmul, %function
.align 2
plantard_pointmul:
	push {r4-r11, r14}
	f_ptr		.req r0
	g_ptr		.req r1
	poly1		.req r2
	poly2		.req r3
	poly3		.req r4
	poly4		.req r5
	poly5		.req r6
	poly6		.req r7
	qprime		.req r8
	q			.req r9
	qa			.req r10
	tmp			.req r11
	tmp2		.req r12
	loop		.req r14

	movw q, #12289
	movw qa, #24578
	movw qprime, #0xd001
	movt qprime, #0x8ff

	#계수 6개씩 처리하므로 512/6=85.xx, 나머지 2개는 loop밖에서 처리
	movw loop, 85
	1:
		load3 f_ptr, poly1, poly2, poly3, #0, #4, #8
		load3_update g_ptr, poly4, poly5, poly6, #4, #4, #4

		doubleplantardmul poly1, poly4, tmp, tmp2, qprime, q, qa
		doubleplantardmul poly2, poly5, tmp, tmp2, qprime, q, qa
		doubleplantardmul poly3, poly6, tmp, tmp2, qprime, q, qa

		store3_update f_ptr, poly1, poly2, poly3, #4, #4, #4

		subs.w loop, #1
	bne.w 1b
	//남은 계수 2개
	//여기서 hard_fault 발생
	ldr.w poly1, [f_ptr, #0]
	ldr.w poly4, [g_ptr, #0]
	doubleplantardmul poly1, poly4, tmp, tmp2, qprime, q, qa
	str.w poly1, [f_ptr]

	pop {r4-r11, pc}
