# OPT — 적용된 최적화 기법

> 적용 완료된 최적화 기법의 카탈로그(ID · 설명 · 향상률). 미구현/기각 아이디어는 필요 시 `OPT_IDEA.md`로 분리한다.
>
> 근거 소스: `reference/M4_Falcon/` (README + `Core/Src/*.S`, `vrfy.c`).

## 기법 목록

| ID | 기법 | 대상 | 향상률 | 상태 |
|----|------|------|--------|------|
| OPT-001 | 레지스터당 16-bit 계수 2개 packing | NTT/iNTT | (TODO) | 적용 |
| OPT-002 | Plantard 곱셈 (Montgomery 대체) | NTT/iNTT/pointmul | (TODO) | 적용 |
| OPT-003 | layer-merging (512: NTT 3-3-3 / iNTT 4-3-2, 1024: NTT 3-3-4 / iNTT 4-3-3) | NTT/iNTT | (TODO) | 적용 |
| OPT-004 | lazy reduction (3·6-layer 후, loop unrolling) | NTT/iNTT | (TODO) | 적용 |

## 상세

### OPT-001 — 레지스터당 계수 2개 packing

- **동기**: Cortex-M4 의 32-bit 레지스터·SIMD 유사 명령(`smulwt`, `pkhtb`, `uadd16` 등)을 활용해 16-bit 계수 2개를 한 레지스터에서 병렬 처리.
- **방법**: 16-bit 계수 2개를 32-bit 에 packing 하고 상/하위 half-word 를 나눠 butterfly 연산 (`macros.i`, `ntt.S`).
- **효과**: (BENCHMARK.md 근거 TODO)
- **검증**: (정확성·회귀 테스트 TODO)

### OPT-002 — Plantard 곱셈

- **동기**: Montgomery 대비 감소(reduction) 비용이 낮은 modular multiplication.
- **방법**: signed Plantard multiplication 을 NTT/iNTT/pointmul 에 적용 (`plantard_pointmul`, butterfly 매크로의 `q`·`qa` 파라미터).
- **효과**: (TODO)
- **검증**: (TODO)

### OPT-003 — layer-merging

- **동기**: layer 간 load/store 왕복을 줄여 메모리 접근 비용 절감.
- **방법**: NTT/iNTT 를 차수별로 병합 (512: NTT 3-3-3, iNTT 4-3-2 / 1024: NTT 3-3-4, iNTT 4-3-3).
- **효과**: (TODO)
- **검증**: (TODO)

### OPT-004 — lazy reduction

- **동기**: 매 layer reduction 을 생략해 명령 수 절감.
- **방법**: NTT 진행 중 3-layer·6-layer 이후에만 reduction 수행, loop unrolling 으로 reduction 이 필요한 레지스터에만 적용.
- **효과**: (TODO)
- **검증**: (TODO)
