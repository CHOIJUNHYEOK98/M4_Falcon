# BENCHMARK — 성능 측정 결과

> 측정 환경·정책과 실측 결과의 단일 권위 소스. 모든 수치는 실측값 — 추정·과거값 복사 금지.

## 1. 스택 사용량 (pqm4 stack 하네스, 실보드)

### 측정 환경

- 보드: **Nucleo-L4R5ZI** (STM32L4R5ZI, Cortex-M4F, SRAM 640KB), ST-LINK V2.1
- 툴체인: `arm-none-eabi-gcc` 10.3.1
- 컴파일: `-O3 -g3`, `-mthumb -mfloat-abi=hard -mfpu=fpv4-sp-d16`, pqm4 AIO(All-In-One, 전체 단일 컴파일)
- 프레임워크: pqm4 (falcon 보유 마지막 커밋 `9443518`로 고정), 스택 하네스 `mupq/crypto_sign/stack.c`
- 측정 원리: 실행 전 스택을 카나리(canary, 표식값)로 칠하고(`hal_spraystack`), 연산 후 덮어쓰인 최대 깊이를 측정(`hal_checkstack`). keypair/sign/verify 각각 보고. **정적·전역 버퍼(.bss)는 스택 측정에 포함되지 않음.**
- 측정 스크립트: `work/measure_stack.py` (openocd 플래시 + reset 재실행 + 38400 시리얼 파싱·집계)

### 측정 정책

- 반복 횟수: 구현·파라미터당 **20회** (아래 표). verify 안정성은 A·B·C1·C2 각 **100회**로 추가 검증 — 바닥값 고정·상방 outlier만 확인(`docs/STACK_ANALYSIS.md` §3)
- 보고 지표: **max(worst-case)** 를 프로비저닝 기준으로 우선 보고, median·min 병기
- keygen(및 일부 sign/verify)은 RNG 시드 기반 거부 샘플링(rejection sampling)으로 실행마다 스택 깊이가 변동 → 반복 측정으로 worst-case 포착

### 비교 대상 3구현

| 표기 | 구현 | 설명 |
|------|------|------|
| **A** | pqm4 `m4-ct` | pqm4가 제공한 Cortex-M4 최적화 Falcon (Pornin 레퍼런스 + M4 부동소수점 어셈블리). tmp를 정적 `.bss`에 배치 |
| **B** | 사용자 `opt-plantard` | A와 동일 코어 + 사용자의 Verify 정수 NTT 어셈블리 최적화(`ntt_fast`/`intt_fast`/`plantard_pointmul`, Plantard 곱셈·2계수 packing). tmp 정적 배치 |
| **C1** | NIST Round3 레퍼런스 (기본) | 공식 Round3 제출 레퍼런스(`falconNNNint`, 순수 C 부동소수점 에뮬레이션). **임시 버퍼를 스택에 할당**(레퍼런스 기본 `TEMPALLOC` 빈 값) |
| **C2** | NIST Round3 레퍼런스 (정적화) | C1과 동일 코드, `TEMPALLOC=static`으로 임시 버퍼를 `.bss`로 이동 (A·B와 동등 조건) |

C(레퍼런스)를 C1·C2 두 방식으로 측정한 이유: 세 구현의 스택 차이 대부분은 알고리즘이 아니라 **임시 버퍼를 스택에 두느냐 정적 영역에 두느냐**(메모리 배치 전략)에서 나온다. C1은 레퍼런스의 실제(out-of-the-box) 스택 부하를, C2는 A·B와 동등 조건에서의 순수 알고리즘 스택을 보여준다.

### 결과 — Falcon-512 (bytes, 20회)

| 구현 | keypair (max / median) | sign (max / median) | verify (max / median) |
|------|------|------|------|
| A pqm4 m4-ct | 1476 / 1412 | 2460 / 2460 | **376 / 376** |
| B 사용자 opt-plantard | 1476 / 1448 | 2572 / 2460 | **424 / 424** |
| C1 레퍼런스 (스택) | 18364 / 18308 | 43220 / 43112 | 4836 / 4724 |
| C2 레퍼런스 (정적) | 1220 / 1152 | 2340 / 2232 | 420 / 420 |

### 결과 — Falcon-1024 (bytes, 20회)

| 구현 | keypair (max / median) | sign (max / median) | verify (max / median) |
|------|------|------|------|
| A pqm4 m4-ct | 1476 / 1452 | 2548 / 2548 | **460 / 376** |
| B 사용자 opt-plantard | 1476 / 1456 | 2660 / 2548 | **436 / 436** |
| C1 레퍼런스 (스택) | 35260 / 35232 | 83892 / 83784 | 8820 / 8820 |
| C2 레퍼런스 (정적) | 1212 / 1196 | 2436 / 2328 | 532 / 420 |

### 해석

1. **레퍼런스(C1)가 압도적으로 큰 이유는 알고리즘이 아니라 메모리 배치.** 같은 레퍼런스 코드를 임시 버퍼만 스택→정적으로 옮긴 C2는 verify 4724→420(512)로 약 4300B가 사라진다. 이 차이가 곧 스택에 올려둔 작업 버퍼(`h`,`hm`,`sig`,`tmp.b`,SHAKE 컨텍스트)다. A·B는 pqm4 관례대로 이 버퍼들을 정적 `.bss`에 두므로 C2와 같은 수백 바이트 영역에 위치한다. (검증: `tmp` 심볼이 `.bss`에 약 40KB로 상주.)

2. **사용자 최적화(B)는 Verify 스택을 오히려 늘린다** — 512에서 A 376→B 424(+48B). 1024에서는 A가 대부분 376(20회 중 1회 460 outlier)인 반면 B는 436으로 안정, 대표값 기준 +60B. 원인은 사용자의 Verify NTT 어셈블리가 리프에서 레지스터를 대량 저장하기 때문이다. B의 verify 스택 424B는 `crypto_sign_open`(248B) + `verify_raw`(24B) + `intt_fast`(152B: 정수 13개 52B + FPU `s0-s24` 25개 100B)로 정확히 분해된다. 프레임 수준 상세와 "A는 왜 376B에 머무는가(해싱 경로가 천장)"는 `docs/STACK_ANALYSIS.md` 참조. 즉 **속도를 얻는 대가로 verify 스택이 수십 바이트 깊어지는 trade-off**이나 절대값(424~436B)은 여전히 매우 작다.

3. **keygen·sign은 세 구현이 유사**(A·B·C2 모두 keypair ~1.2~1.5KB, sign ~2.2~2.7KB). 사용자 최적화는 Verify에만 적용되므로 keygen/sign 코어가 A와 동일하고, 정적 tmp 설계도 공유하기 때문. keypair는 RNG 거부 샘플링으로 실행마다 변동(예: A-512 1372~1476).

4. **Verify 스택 최소는 A(376B).** 순수 C NTT(`mq_NTT`/`mq_iNTT`)가 `-O3`에서 얕은 리프 프레임을 갖는다. 스택만 보면 A가 가장 작지만, 이는 속도(사이클)와의 trade-off이며 사이클 비교는 §2에서 다룬다.

원자료: `work/measure_stack.py` 재실행으로 재현. 20회 표본 전체는 커밋 이력의 측정 로그 참조.

우리 구현(B) vs pqm4 구현(A)의 프레임 수준 상세 분석(왜 B가 verify에서 +48B인지, tmp의 `.bss` 상주 근거)은 `docs/STACK_ANALYSIS.md` 참조.

## 2. 사이클 (Verify·NTT/iNTT)

> Falcon-512/1024 Verify 함수·NTT 사이클. 사용자 논문 설정(pqm4 20MHz, `-O3`). (측정 예정 — `docs/TODO.md` 예정 항목)

| 항목 | 대상 | 측정값 | 단위 | 비고 |
|------|------|--------|------|------|
| (예정) | | | cycles | |

<!-- 측정 결과 기록은 benchmark 스킬을 사용하면 일관된 형식으로 갱신된다. -->
