# TODO

> 작업 관리의 단일 소스. 글로벌 가이드 "TODO.md 기반 작업 관리" 규칙 준수:
> 착수 전 계획 작성 → 사용자 승인 → 진행 중 완료 즉시 `[x]` 체크 → 기존 기록은 지우지 않고 아래에 추가.

## 진행 중

### 작업: pqm4 스택 사용량 3-way 비교 측정 (실보드)

**목표**: Nucleo-L4R5ZI 실보드에서 pqm4 스택 측정 하네스로 3개 Falcon 구현의 keygen·sign·verify 스택 사용량을 Falcon-512·1024에 대해 측정·비교.

**측정 조건(확정)**: 파라미터 {512, 1024} · 연산 {keygen, sign, verify} 전부 · 플랫폼 nucleo-l4r5zi · 시리얼 `/dev/ttyACM0` · 세 구현 동일 컴파일러(arm-none-eabi-gcc 10.3.1)·동일 최적화 플래그.

**비교 대상 3구현**:
- (A) 과거 pqm4 falcon `m4-ct` — 상위 mupq/pqm4 이력에서 falcon 제거 직전 커밋 회수
- (B) 사용자 M4_Falcon — `reference/M4_Falcon/` crypto core 포팅 (Verify 최적화 어셈블리 포함)
- (C) NIST Round3 reference — 공식 Falcon Round3 제출 패키지 Reference 구현 포팅

#### Phase 1 — pqm4 작업 트리 준비 [완료]
- [x] 작업용 pqm4를 `work/pqm4/`에 full clone + 서브모듈 init → **falcon 보유 마지막 커밋 `9443518`(dfc3a75~1, 2025-02)로 고정** (falcon m4-ct 네이티브 확보, 단일 하네스로 공정 비교)
- [x] nucleo-l4r5zi + `/dev/ttyACM0` 종단 파이프라인 검증: `work/measure_stack.py`(openocd 플래시 + 38400 시리얼 파싱) 작성, falcon-512 m4-ct 측정 성공 (impl A smoke test 겸 확보)
- [x] impl A 측정 완료 — 512 m4-ct: kp=1452/sign=2460/vrfy=376, 1024 m4-ct: kp=1476/sign=2548/vrfy=376 (bytes). m4-ct는 정적 union tmp 버퍼(.bss) 사용 확인 → B·C도 동일 래퍼 패턴으로 통합 필요

#### Phase 2 — 3개 Falcon 구현 확보·포팅 [완료]
- [x] (A) m4-ct 네이티브 확보 (커밋 고정으로 자동) — falcon-512/1024 `m4-ct`
- [x] (B) 사용자 최적화 포팅 — m4-ct 기반 + 사용자 vrfy.c/inner.h + ntt.S/intt.S/pointmul.S/macros.i, pqm4.c 한 줄(to_ntt_monty→to_ntt_plantard). 스킴 `opt-plantard` (512/1024). 사용자 코어가 m4-ct와 byte-identical이라 최적화만 격리됨
- [x] (C) Round3 Reference 확보(공식 falcon-round3.zip, `falconNNNint`) → pqm4 스킴 포팅. `make_ref_scheme.py`로 nist.c→pqm4.c 각색(size_t, pqm4 randombytes, TEMPALLOC). C1=`ref-r3`(스택), C2=`ref-r3-static`(정적 tmp), 512/1024
- [x] 기능 정확성: 8개 바이너리 모두 스택 하네스에서 "Signature valid!" 확인
- [x] 측정 무결성(`nm`/`size`): B는 asm 심볼 보유·A는 0, C2 .bss +62KB(정적 tmp), A/C fpr 심볼 상이 → 세 구현 실제 상이 확정

#### Phase 3 — 스택 측정 빌드·실행 [완료]
- [x] 8개 스택 바이너리(.hex) 빌드 (A/B/C1/C2 × 512/1024)
- [x] 측정 방법론 확립: keygen은 RNG 시드 기반 거부 샘플링으로 스택 변동 → 20회 반복 후 op별 min/max/median 집계, worst-case(max)를 프로비저닝 기준으로. openocd reset 재실행으로 가속(`work/measure_stack.py`)
- [x] 8개 바이너리 × 20회 최종 측정 완료 (전부 bad=0, Signature valid)

#### Phase 4 — 결과 정리·검증 [완료]
- [x] 측정 무결성 확인 (Phase 2에서 선행 완료)
- [x] `docs/BENCHMARK.md` §1에 스택 비교 표(3구현 × 2파라미터 × 3연산) + 해석 기록. 핵심 발견: (a) 레퍼런스가 큰 건 알고리즘 아닌 tmp 스택 배치(C1 vs C2로 증명), (b) 사용자 최적화는 verify 스택 +48~60B(asm 레지스터 스필 trade-off), (c) tmp는 정적 `.bss`(~40KB)
- [x] `docs/STACK_ANALYSIS.md` 작성 — 우리 구현(B) vs pqm4 구현(A) 프레임 수준 분석(crypto_sign_open 216B 동일, intt_fast 152B 리프, tmp `.bss` 근거). BENCHMARK.md와 상호 참조

## Phase 5 — Verify NTT 어셈블리 프롤로그 과잉 저장 수정

**배경**: `intt.S`·`ntt.S` 3개 파일이 ARM 호출 규약(AAPCS)상 저장 의무가 없는 caller-saved(호출한 쪽이 보존을 책임지는) 레지스터 `r0`–`r3`·`r12`·`s0`–`s15` 를 프롤로그에서 스택에 저장한다. 각 파일의 주석은 `r4-r11` · `s16-s24` 를 저장한다고 적혀 있어 **코드와 주석이 불일치**하며, 주석 처리된 `//push {r4-r11, r14}` 가 남아 있어 의도치 않은 코드로 보인다.

**영향**: verify 스택 80~84B 과잉. 이 때문에 NTT 경로가 공통 해싱 경로(376B)를 넘어서, `docs/BENCHMARK.md` §1 해석 2 의 "verify 스택 +48~60B trade-off" 라는 결론이 나왔다. 계산 결과는 정확하므로 정확성 결함은 아니다.

**실측 근거**: 512 verify 424B = `crypto_sign_open`(248) + `verify_raw`(24) + `intt_fast`(152) / 1024 verify 436B = 248 + 24 + `ntt_fast`(164). 둘 다 `docs/BENCHMARK.md` §1 실측값과 일치.

**대상 파일** (512 `ntt.S` 만 올바르므로 제외):

| 파일 | 현재 | 프레임 | 수정 후 | 프레임 |
|------|------|--------|---------|--------|
| `falcon_512_ETRI/Core/Src/intt.S` | `r0-r11,r14` / `s0-s24` | 152 B | `r4-r11,r14` / `s16-s24` | 72 B |
| `falcon_1024_ETRI/Core/Src/ntt.S` | `r0-r12,r14` / `s0-s26` | 164 B | `r4-r11,r14` / `s16-s26` | 80 B |
| `falcon_1024_ETRI/Core/Src/intt.S` | `r0-r11,r14` / `s0-s24` | 152 B | `r4-r11,r14` / `s16-s24` | 72 B |

**기대 결과**: 512·1024 모두 NTT 경로가 344·352B 로 공통 해싱 천장(376B) 아래로 내려가 verify 스택이 **376B**(pqm4 `m4-ct` 와 동일)가 된다. 즉 스택 trade-off 없이 속도 이득만 남는다.

### Phase 5-A — 회귀 검증 환경 구축 (수정 전 baseline 확보)
- [ ] pqm4 `testvectors` 하네스로 falcon-512·1024 `opt-plantard` 의 **수정 전 출력 해시** 확보 (결정론적 난수 → 비트 단위 재현 가능)
- [ ] 회귀 검증 스크립트 `work/verify_regression.py` 작성 (openocd 플래시 → 시리얼 파싱 → baseline 대비 자동 비교)
- [ ] 정적 baseline 기록: `objdump` 프레임 크기 3종, `nm` 어셈블리 심볼 존재 확인
- [ ] 스택 baseline 재확인 (512 verify 424 / 1024 verify 436)

### Phase 5-B — 어셈블리 수정 (`work/pqm4` 사본)
- [ ] 본문에서 `r0`–`r3`·`r12` 별칭 재사용 경로 확인 — 복원값에 의존하는 코드가 없는지 검토 (`[sp` 접근 0건은 확인 완료)
- [ ] 3개 파일 프롤로그·에필로그 대칭 수정 (`push`/`pop`, `vpush`/`vpop`)
- [ ] 주석을 실제 저장 범위와 일치시키고, 왜 `r0`–`r3`·`s0`–`s15` 저장이 불필요한지 근거 주석 추가
- [ ] 재빌드 후 `objdump` 로 프레임 감소 확인 (152→72 / 164→80 / 152→72)

### Phase 5-C — 동일 동작 검증 (실보드 Nucleo-L4R5ZI)
- [ ] `testvectors` 출력이 5-A baseline 과 **완전 일치**하는지 확인 (512·1024)
- [ ] 스택 하네스 `Signature valid!` 확인 + verify 스택 20회 재측정 (376B 예상)
- [ ] 불일치 시 즉시 롤백하고 원인 분석 — 통과 전에는 5-D 로 진행하지 않는다

### Phase 5-D — `reference/M4_Falcon` 반영
- [ ] 동일 수정 적용 (`reference/` read-only 규칙의 예외 — 사용자 지시로 원본 갱신)
- [ ] `work/pqm4` 사본과 `diff` 로 어셈블리 동일성 확인

### Phase 5-E — 원격 저장소 갱신
- [ ] `https://github.com/CHOIJUNHYEOK98/M4_Falcon.git` 을 별도 위치에 clone (기존 커밋 이력 보존)
- [ ] 수정 파일 반영 → `[YYMMDD] 수행 내용` 형식 커밋 → **푸시 직전 사용자 확인** 후 push

### Phase 5-F — 문서 갱신
- [ ] `docs/BENCHMARK.md` §1 해석 2 정정 — "trade-off" 서술을 제거하고 수정 후 실측값으로 교체
- [ ] `docs/STACK_ANALYSIS.md` 갱신 — 무효가 된 프레임 분해·결론 제거 후 재작성
- [ ] `docs/OPT.md` 에 반영할 항목이 있는지 검토

## 예정

- [ ] 최적화 기법 정리 (`docs/OPT.md` 의 향상률·효과·검증 항목을 소스·논문 근거로 채우기)
- [ ] 벤치마크 결과(사이클) 정리 (`docs/BENCHMARK.md` 의 Falcon-512/1024 Verify·NTT 실측값)
- [ ] 논문 각 절 ↔ 소스/결과 대응 매핑 (선택)

## 완료

- [x] 프로젝트 폴더 구조 세팅 (folder-structure-setup)
- [x] 프로젝트 init (subproject-init: 루트 CLAUDE.md + optimization-m4 모듈)
- [x] 원본 소스 스냅샷 확보 (`reference/M4_Falcon/`)
