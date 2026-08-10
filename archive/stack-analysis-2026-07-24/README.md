# Falcon Verify 스택 사용량 분석 — 재현 패키지

ARM Cortex-M4F 상에서 Falcon(NIST 표준 후보 격자 기반 서명)의 **스택 사용량**을 4개 구현에 대해 실보드로 측정하고, 그 차이가 나는 이유를 프레임(함수 호출 프레임) 수준에서 규명한 분석 자료의 재현 패키지다.

핵심 결론: 사용자의 Verify NTT (Number Theoretic Transform, 수론 변환) 어셈블리 최적화(Plantard 곱셈·2계수 packing)는 Verify 사이클을 줄이는 대신, 최적화 어셈블리가 레지스터를 프롤로그(함수 진입부)에서 대량 저장하기 때문에 **Verify 스택을 48바이트 더 쓴다**(Falcon-512 기준 376B → 424B). 단 절대값은 40KB급 작업 버퍼에 비하면 무시할 수준이다.

상세 분석은 [`docs/STACK_ANALYSIS.md`](docs/STACK_ANALYSIS.md), 측정 환경·전체 수치는 [`docs/BENCHMARK.md`](docs/BENCHMARK.md) 참조.

---

## 1. 폴더 구조

```
stack-analysis-2026-07-24/
├── README.md                 이 파일 (사용법)
├── docs/
│   ├── STACK_ANALYSIS.md     프레임 수준 분석 (왜 B가 +48B인가)
│   └── BENCHMARK.md          측정 환경·정책·전체 실측 결과
├── scripts/
│   ├── measure_stack.py      스택 측정 스크립트 (플래시 + 반복 실행 + 집계)
│   ├── make_ref_scheme.py    NIST 레퍼런스를 pqm4 스킴으로 포팅 (C1/C2 생성용)
│   └── st_nucleo_l4r5.cfg     openocd 보드 설정 (Nucleo-L4R5ZI)
├── src/                       측정에 쓴 구현 소스 (pqm4 crypto_sign 스킴 형식)
│   ├── falcon-512/{m4-ct, opt-plantard, ref-r3, ref-r3-static}/
│   └── falcon-1024/{m4-ct, opt-plantard, ref-r3, ref-r3-static}/
└── prebuilt/                  미리 빌드된 산출물 (보드만 있으면 바로 측정 가능)
    ├── bin/  *_stack.hex      플래시용 hex (8개)
    └── elf/  *_stack.elf      프레임 분석용 elf (8개)
```

## 2. 4개 구현

| 표기 | 스킴 디렉토리 | 설명 |
|------|------|------|
| **A** | `m4-ct` | pqm4가 제공한 Cortex-M4 최적화 Falcon (Pornin 레퍼런스 + M4 부동소수점 어셈블리). 임시 버퍼를 정적 `.bss`에 배치 |
| **B** | `opt-plantard` | A와 동일 코어 + 사용자의 Verify 정수 NTT 어셈블리 최적화(`ntt.S`/`intt.S`/`pointmul.S`, Plantard 곱셈·2계수 packing) |
| **C1** | `ref-r3` | NIST Round3 레퍼런스 (순수 C). 임시 버퍼를 **스택에** 할당 (out-of-the-box 상태) |
| **C2** | `ref-r3-static` | C1과 동일 코드, 임시 버퍼만 `.bss`로 이동 (A·B와 동등 조건) |

각 스킴 디렉토리의 `pqm4.c`가 pqm4 스택 하네스와 붙는 래퍼다. B(`opt-plantard`)에는 원저자 설명 `README.txt`가 함께 들어 있다.

## 3. 측정 환경

- 보드: **Nucleo-L4R5ZI** (STM32L4R5ZI, Cortex-M4F, SRAM 640KB), ST-LINK V2.1
- 툴체인: `arm-none-eabi-gcc` 10.3.1
- 컴파일: `-O3 -g3`, `-mthumb -mfloat-abi=hard -mfpu=fpv4-sp-d16`
- 프레임워크: pqm4 (Falcon 보유 마지막 커밋 `9443518`), 스택 하네스 `mupq/crypto_sign/stack.c`
- 호스트 도구: `openocd`, Python 3 + `pyserial`

측정 원리: 실행 전 스택을 카나리(canary, 표식값)로 칠하고 연산 후 덮어쓰인 최대 깊이(high-water mark)를 잰다. **정적·전역 버퍼(.bss)는 스택 측정에 포함되지 않는다.**

---

## 4. 재현 방법

### 4-A. (가장 간단) 미리 빌드된 hex로 바로 측정

pqm4 프레임워크를 빌드할 필요 없이, `prebuilt/bin`의 hex를 보드에 플래시하고 스택을 측정한다. `measure_stack.py`는 `openocd` + `pyserial`만 있으면 독립 실행된다.

```sh
# 사전 준비: openocd, python3, pyserial 설치. 보드를 USB로 연결.
#   pip install pyserial
cd scripts        # st_nucleo_l4r5.cfg 를 openocd가 찾도록 이 디렉토리에서 실행

# 사용자 최적화 구현(B), Falcon-512, 20회 측정
python3 measure_stack.py --hex ../prebuilt/bin/crypto_sign_falcon-512_opt-plantard_stack.hex \
        --iters 20 --label B -u /dev/ttyACM0

# pqm4 m4-ct(A)와 비교
python3 measure_stack.py --hex ../prebuilt/bin/crypto_sign_falcon-512_m4-ct_stack.hex \
        --iters 20 --label A -u /dev/ttyACM0
```

옵션: `--hex`(필수, 플래시할 hex), `--iters`(반복 횟수, 기본 10), `--label`(출력 표식), `-u`(시리얼 포트, 기본 `/dev/ttyACM0`). 출력은 op(keypair/sign/verify)별 min·max·median과 표본 전체다. `BENCHMARK.md §1`의 표와 대조하면 된다.

측정 대상 hex 파일명 규칙: `crypto_sign_falcon-{512,1024}_{m4-ct,opt-plantard,ref-r3,ref-r3-static}_stack.hex`

### 4-B. 프레임 분해 재현 (보드 불필요)

`STACK_ANALYSIS.md`의 프레임 수준 근거(누가 몇 바이트 프롤로그에서 저장하는가)는 `prebuilt/elf`의 elf만으로 재현한다.

```sh
# B의 verify 스택을 결정하는 intt_fast, crypto_sign_open 프롤로그 확인
arm-none-eabi-objdump -d prebuilt/elf/crypto_sign_falcon-512_opt-plantard_stack.elf

# 작업 버퍼 tmp 가 스택이 아니라 .bss 에 상주함을 확인
arm-none-eabi-nm -S prebuilt/elf/crypto_sign_falcon-512_opt-plantard_stack.elf | grep tmp
```

### 4-C. 소스에서 직접 빌드

`src/`의 스킴을 pqm4 트리에 넣고 빌드한다. pqm4 프레임워크가 필요하다.

```sh
git clone https://github.com/mupq/pqm4 && cd pqm4
git checkout 9443518                       # Falcon 보유 마지막 커밋
git submodule update --init

# 이 패키지의 스킴 소스를 pqm4 crypto_sign 아래로 복사
cp -r <이 패키지>/src/falcon-512/*  crypto_sign/falcon-512/
cp -r <이 패키지>/src/falcon-1024/* crypto_sign/falcon-1024/

# 스택 하네스 바이너리 빌드 (PLATFORM 은 보드에 맞게)
python3 build_everything.py --platform nucleo-l4r5zi -o stack \
        --scheme crypto_sign/falcon-512/opt-plantard
# → elf/, bin/ 아래에 *_stack.elf / *_stack.hex 생성
```

C1·C2(레퍼런스 스택 vs 정적) 스킴은 `make_ref_scheme.py`로 NIST Round3 레퍼런스에서 생성했다. 사용법은 스크립트 상단 주석 참조(`<ref_int_dir> <m4ct_dir> <dst_dir> <stack|static>`).

---

## 5. 핵심 결과 요약 (Falcon-512, verify 스택, bytes)

| 구현 | verify (max / median) | 비고 |
|------|------|------|
| A `m4-ct` | 376 / 376 | C NTT는 리프 프레임이 얕아 공통 해싱 경로(376B)에 가려짐 |
| B `opt-plantard` | **424 / 424** | 최적화 NTT가 FPU 레지스터까지 저장(`intt_fast` 152B) → 해싱 천장을 넘어 직접 최댓값 |
| C1 `ref-r3` | 4836 / 4724 | 작업 버퍼를 스택에 둠 |
| C2 `ref-r3-static` | 420 / 420 | 버퍼 정적화 → A·B와 동급 |

전체 표(Falcon-1024 포함)·해석은 `docs/BENCHMARK.md`, "B가 왜 정확히 +48B인가"의 프레임 분해는 `docs/STACK_ANALYSIS.md` 참조.
