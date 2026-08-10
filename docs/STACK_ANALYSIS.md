# STACK_ANALYSIS — 우리 구현(B) vs pqm4 구현(A) 스택 분석

> 대상: pqm4 `m4-ct`(A)와 사용자 `opt-plantard`(B)의 스택 사용량 차이를 프레임 수준에서 규명한다.
> 측정 수치의 권위는 `docs/BENCHMARK.md` §1이며, 이 문서는 **그 수치가 나오는 이유(메커니즘)** 만 다룬다.
> 근거는 `work/pqm4`에서 빌드한 Falcon-512 스택 바이너리의 `objdump`/`nm` 실측(재현 가능).

## 1. 요약

| 연산 | A pqm4 m4-ct | B 사용자 opt-plantard | 차이 |
|------|------|------|------|
| keypair | 1476 | 1476 | ≈0 |
| sign | 2460 | 2572 | +112 (worst), median 동일 |
| verify | **376** | **424** | **+48** |

(Falcon-512, bytes, 20회 중 max 기준. 전체 표는 `docs/BENCHMARK.md` §1.)

**결론**: A와 B는 코어(keygen/sign/verify의 상위 로직)와 임시 버퍼 배치 전략이 동일해 keygen·sign 스택이 사실상 같다. 유일하게 유의미한 차이는 **Verify에서 B가 A보다 48B 더 쓴다**는 점이며, 이는 사용자 Verify NTT 어셈블리의 레지스터 저장 때문이다. 절대값은 둘 다 수백 바이트로 매우 작다.

## 2. 왜 둘 다 작은가 — 임시 버퍼가 스택이 아닌 `.bss`

두 구현 모두 pqm4 래퍼(`pqm4.c`)가 큰 작업 버퍼를 **파일 스코프 `static` union**으로 선언한다:

```c
static union { uint8_t b[54 * N]; uint64_t ...; fpr ...; } tmp;
```

`static`이므로 스택이 아니라 `.bss`(0으로 초기화되는 정적 RAM 영역)에 상주한다. A·B 바이너리에서 동일하게 확인된다:

```
20000bb8  00009c00  b  tmp     ← 주소 0x2000_0bb8(SRAM), 크기 0x9c00 = 39936B(≈40KB), 섹션 b=.bss
```

Falcon의 NTT 계수·다항식·복호 버퍼는 전부 이 40KB `tmp` 안에 포인터로 배치된다. pqm4 스택 하네스는 **호출 스택만** 측정하므로 이 40KB는 스택 수치에 잡히지 않는다. (레퍼런스 C1이 verify에 4724B를 쓰는 것과 대비 — 레퍼런스는 이 버퍼들을 스택에 두기 때문. `docs/BENCHMARK.md` §1 해석 1 참조.)

따라서 A·B의 스택 수치는 **버퍼를 뺀 순수 함수 호출 프레임**만을 나타낸다.

## 3. Verify 스택 분해 — 왜 B가 424B이고 A보다 48B 큰가

Verify(`crypto_sign_open`)에서 NTT를 호출하는 경로는 `crypto_sign_open → verify_raw → (NTT 리프)`의 3단이며, 세 프레임이 동시에 스택에 살아 있다. 각 프레임을 `objdump`로 실측했다(Falcon-512).

| 프레임 | A (m4-ct) | B (opt-plantard) | 프롤로그 근거 |
|--------|-----------|------------------|------|
| `crypto_sign_open` | **248 B** | **248 B** | `stmdb {r4,r5,r6,r7,r8,r9,sl,lr}`(레지스터 8개=32B) + `sub sp, #216`(216B). A·B 동일 |
| `verify_raw` | 40 B | **24 B** | A: `stmdb`(10개=40B) / B: `stmdb {r4-r8,lr}`(6개=24B). B가 더 단순(memcpy+asm 호출) |
| 리프 NTT | `mq_NTT`/`mq_iNTT` = **64 B** | `intt_fast` = **152 B** | A: `stmdb`(9개=36B)+`sub sp,#28`. B: `stmdb {r0-r9,sl,fp,lr}`(13개=52B)+`vpush {s0-s24}`(FPU 25개=100B) |
| **NTT 경로 합** | 248+40+64 = **352 B** | 248+24+152 = **424 B** | — |
| **verify 실측(max)** | **376 B** | **424 B** | `docs/BENCHMARK.md` §1 |

**B는 정확히 일치한다**: 248 + 24 + 152 = 424 = 실측. B의 Verify 스택은 이 세 프레임이 전부다.

**A는 NTT 경로가 천장이 아니다**: A의 NTT 경로 합은 352B인데 A 실측은 376B다. 즉 A의 verify 최대 스택은 NTT가 아니라 **A·B가 동일하게 실행하는 메시지 해싱(SHAKE) 경로**(`crypto_sign_open → hash_to_point_vartime → Keccak 순열`)에서 결정된다. 이 해싱 경로(≈376B)는 A·B 코드가 byte 단위로 같아 양쪽 모두 존재한다.

정리하면:
- **B**: 최적화 어셈블리 `intt_fast`가 정수 13개 + FPU 25개 레지스터를 프롤로그에 저장(152B)해 NTT 경로가 424B로 깊어지고, 이것이 공통 해싱 천장(376B)을 넘어서 **B의 verify = 424B**.
- **A**: C NTT(`mq_NTT`/`mq_iNTT`, 64B)는 얕아 NTT 경로가 352B에 그치므로 공통 해싱 천장(376B) 아래에 "숨는다". 따라서 **A의 verify = 376B**(해싱이 결정).
- 관측되는 **+48B = B의 NTT 경로(424) − 공통 해싱 천장(376)**. 리프만 보면 B가 A보다 88B 깊지만(152 vs 64), A는 어차피 해싱에 막혀 376이라 가시적 증가는 48B다.

핵심 원인은 **사용자 최적화(Plantard 곱셈·2계수 packing)가 성능을 위해 FPU 레지스터(`s0-s24`)까지 스크래치(scratch, 임시 연산용)로 동원**하고, ARM 호출 규약상 callee-saved 레지스터를 프롤로그에서 스택에 저장하기 때문이다. 참고로 B의 다른 asm 리프는 `ntt_fast` 72B(`stmdb`(9개=36B)+`vpush {s16-s24}`(36B)), `plantard_pointmul` 36B로, `intt_fast`(152B)가 최심이라 이것이 B의 verify 스택을 결정한다.

### 실증 — 100회 측정으로 모델 검증

카나리 측정은 verify 1회 **전체의 최대 스택(high-water mark)** 이므로, 각 구현의 "가장 깊은 상시 경로"가 바닥값을 정하고, 변동은 위쪽(드문 더 깊은 경로)으로만 생긴다. Falcon-512 verify를 구현별 **100회** 측정한 분포:

| 구현 | 바닥값 | 분포 (값×횟수) | 해석 |
|------|--------|----------------|------|
| A m4-ct | 376 | 376×98, 396×1, 460×1 | NTT 경로(352)가 해싱 천장(376)에 가려짐 |
| B opt-plantard | 424 | 424×98, 484×1, 532×1 | NTT 경로(424)가 해싱 천장을 넘어 직접 최댓값 |
| C1 레퍼런스(스택) | 4724 | 4724×98, 4836×2 | tmp가 스택 → 대형 |
| C2 레퍼런스(정적) | 420 | 420×100 (완전 고정) | tmp 정적화 → 소형 |

**핵심 검증 두 가지**:
1. **A의 352는 한 번도 나오지 않는다**(바닥 376 고정). NTT 하위 경로(352)는 어느 실행에서도 공통 해싱 천장(376) 아래라 최댓값이 되지 못한다 — 352는 "측정값"이 아니라 "프레임 분해로만 드러나는 하위 경로 깊이"다.
2. **B의 424는 바닥으로 고정된다.** A와 정반대로, B는 최적화 NTT(424)가 천장을 넘으므로 NTT가 직접 verify 스택을 결정한다. 이것이 A(376)와 B(424)의 +48B 차이가 실측에서 안정적으로 재현되는 이유다.

네 구현 모두 바닥값이 고정되고 변동은 위쪽 outlier뿐(서명 내용에 따라 가끔 더 깊어지는 비-NTT 경로)이며, 아래로는 내려가지 않는다.

## 4. 해석 — 속도 ↔ 스택 trade-off

- 사용자 최적화는 **Verify 사이클을 줄이는 대가로 Verify 스택을 48B 늘린다**(512 기준). 이는 어셈블리가 레지스터를 적극 활용하고 그만큼 프롤로그에서 저장하기 때문에 발생하는 구조적 결과다.
- 다만 절대값(A 376B, B 424B)은 40KB급 `.bss` 작업 버퍼에 비하면 무시할 수준이며, 전체 RAM 예산(SRAM 640KB) 관점에서 실질적 부담이 아니다.
- keygen·sign은 사용자 최적화가 적용되지 않아 코어 코드가 A와 동일하고 정적 tmp 설계도 공유하므로 스택이 사실상 같다. (sign의 worst-case 차이 +112B는 sign 내부 RNG 기반 거부 샘플링의 실행별 변동 범위 안이다 — median은 동일.)

## 5. 재현

```
cd work/pqm4
# 프레임 확인
arm-none-eabi-objdump -d elf/crypto_sign_falcon-512_opt-plantard_stack.elf   # intt_fast, crypto_sign_open 프롤로그
arm-none-eabi-nm -S elf/crypto_sign_falcon-512_opt-plantard_stack.elf | grep tmp  # .bss 상주 확인
# 스택 측정 (실보드)
python3 ../measure_stack.py --hex bin/crypto_sign_falcon-512_m4-ct_stack.hex --iters 20 --label A
python3 ../measure_stack.py --hex bin/crypto_sign_falcon-512_opt-plantard_stack.hex --iters 20 --label B
```
