# m4_falcon — Cortex-M4 Falcon Verify 최적화 연구 기록

## 개요

ARM Cortex-M4 상에서 Falcon(NIST 표준 후보 격자 기반 서명) 의 **Verify(서명 검증)** 연산을 최적화한 과거 연구를 기록·정리하는 프로젝트다. 논문 "Optimized Falcon Verify on Cortex-M4 for Post-Quantum Secure UAV Communications" 의 구현·측정·기법을 코드와 연결해 재현 가능한 형태로 남기는 것이 목적이다.

이 저장소는 **기록용**이다 — 원본 소스는 [`reference/M4_Falcon/`](reference/M4_Falcon/) 에 스냅샷으로 보관하며(원본 git 이력 제외), 주요 산출물은 최적화 기법 정리와 벤치마크 결과 문서다.

- 원본 소스: https://github.com/CHOIJUNHYEOK98/M4_Falcon
- 논문: https://www.sciencedirect.com/science/article/pii/S2405959524001401

## 적용된 최적화 규칙

<!-- project-optimization-module: auto-generated, do not edit manually -->
@~/.claude/modules/optimization-m4.md
<!-- /project-optimization-module -->

## 프로젝트 목적

- **최적화 기법 정리**: Falcon Verify 내부 NTT/iNTT 에 적용한 최적화 기법을 실제 소스와 연결해 상세 기록한다.
- **벤치마크 결과**: Verify 함수·NTT 사이클 측정 결과를 정리한다 (pqm4 / STM32CubeIDE, 20MHz, `-O3`).

## 핵심 최적화 요약

`reference/M4_Falcon/README.md` 및 소스 기준. Falcon Verify 의 NTT 에 **signed Plantard multiplication** 을 적용한다.

- 레지스터당 16-bit 계수 2개 packing (32-bit 레지스터 내 병렬 연산)
- Montgomery 곱셈 대신 Plantard 곱셈 사용
- NTT/iNTT layer-merging: Falcon-512/1024 NTT 에 **3-3-3 / 3-3-4**, iNTT 에 **4-3-2 / 4-3-3** 병합
- NTT/iNTT lazy reduction: NTT 중 **3-layer·6-layer 후** reduction, loop unrolling 으로 reduction 이 필요한 레지스터에만 수행

## 디렉터리 구조

```
m4_falcon/
├─ docs/         프로젝트 문서 (BENCHMARK / OPT / TODO 등)
├─ work/         작업·분석 산출물
├─ reference/    참조 자료
│  └─ M4_Falcon/ 원본 소스 스냅샷 (상세 분석은 reference/M4_Falcon/CLAUDE.md 참조)
└─ archive/      보관 자료
```

## 참고 사항

- 최적화된 어셈블리 심볼: `ntt_fast`, `intt_fast`, `plantard_pointmul` (`reference/M4_Falcon/falcon_512_ETRI/Core/Src/*.S`). `vrfy.c` 가 `extern` 선언으로 호출한다.
- Falcon-512 와 Falcon-1024 는 별도 STM32CubeIDE 프로젝트(`falcon_512_ETRI/`, `falcon_1024_ETRI/`)로 분리되어 있으며, layer-merging 파라미터가 차수(512/1024)에 따라 다르다.
- 원본은 STM32L4 타깃 CubeIDE 프로젝트라 HAL·startup 등 보드 코드가 포함된다. 최적화 연구의 핵심은 NTT/iNTT/pointmul 어셈블리와 `vrfy.c` 다.
