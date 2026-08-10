# M4_Falcon — 원본 소스 스냅샷

## 개요

논문 "Optimized Falcon Verify on Cortex-M4 for Post-Quantum Secure UAV Communications" 의 구현 원본이다. ARM Cortex-M4(STM32L4) 타깃의 STM32CubeIDE 프로젝트 2개로 구성되며, Falcon Verify 내부 NTT/iNTT 를 어셈블리로 최적화했다. 원본 저장소(https://github.com/CHOIJUNHYEOK98/M4_Falcon)의 스냅샷이며 원본 git 이력은 제외했다.

## 디렉터리 구조

```
M4_Falcon/
├─ README.md              최적화 전략·벤치마크 설정 요약
├─ falcon_512_ETRI/       Falcon-512 CubeIDE 프로젝트
│  └─ Core/{Inc,Src,Startup}
└─ falcon_1024_ETRI/      Falcon-1024 CubeIDE 프로젝트
   └─ Core/{Inc,Src,Startup}
```

`Core/Src` 의 주요 파일:

- **`ntt.S` / `intt.S`** — 최적화된 NTT/iNTT 어셈블리. 심볼 `ntt_fast`, `intt_fast`. Plantard 곱셈·layer-merging·lazy reduction·2계수 packing 적용.
- **`pointmul.S`** — 점별 곱셈 어셈블리. 심볼 `plantard_pointmul`.
- **`macros.i`** — 어셈블리 공용 매크로(load/store/butterfly 등).
- **`vrfy.c`** — Falcon Verify 참조 C 코드. `mq_NTT`/`mq_iNTT`/`mq_poly_montymul_ntt` 등을 통해 위 어셈블리를 `extern` 호출.
- **`keccakf1600.S` / `fips202.c`** — SHAKE(Keccak) 해시.
- **`codec.c`, `common.c`, `fft.c`, `fpr.c`, `keygen.c`, `sign.c`** — Falcon 참조 구현 구성 요소.
- **`main.c`, `pqm4.c`, `stm32l4xx_*`, `system_stm32l4xx.c`, `syscalls.c`, `sysmem.c`** — CubeIDE·보드·pqm4 하네스 코드.

512/1024 차이: `falcon_512_ETRI` 에는 `katrng.c/h`, `profile.h` 가 추가로 포함된다.

## 핵심 구성 요소

최적화 대상은 NTT/iNTT 와 점별 곱셈이다. layer-merging 파라미터가 차수별로 다르다:

- NTT: Falcon-512 **3-3-3**, Falcon-1024 **3-3-4** 병합
- iNTT: Falcon-512 **4-3-2**, Falcon-1024 **4-3-3** 병합

lazy reduction 은 NTT 진행 중 3-layer·6-layer 이후 수행하며, loop unrolling 으로 reduction 이 필요한 레지스터에만 적용한다.

## 벤치마크 설정 (원본 README 기준)

- Verify 함수 성능: **pqm4** 프레임워크로 측정.
- NTT 성능: **STM32CubeIDE** 로 측정.
- 공통: 주파수 20MHz, 컴파일 옵션 `-O3`.

## 참고 사항

- 이 폴더는 참조용 스냅샷이다. 최적화 기법·측정 결과의 정리 문서는 프로젝트 루트의 `docs/` 에 작성한다.
- 어셈블리 주석은 원저자가 한글로 달아 두었다 — 기법 정리 시 1차 근거로 활용한다.
