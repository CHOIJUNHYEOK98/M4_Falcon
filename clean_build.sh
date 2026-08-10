#!/usr/bin/env bash
# clean_build.sh — 빌드 산출물 일괄 정리 (커밋/푸시 직전 1회 실행)
#
# 사용법:
#   ./clean_build.sh            # 실제 정리
#   ./clean_build.sh --dry-run  # 실행 예정 명령만 표시
#
# 규칙(글로벌 가이드 준수):
#   - work/ 하위 빌드 산출물만 정리. reference/(외부 기준선)·archive/ 는 건드리지 않는다.
#   - Makefile 있는 폴더는 'make clean' 호출, 없는 폴더는 공통 빌드 디렉토리 패턴만 수동 제거.
#   - 실제 빌드 타겟이 생기면 아래 PLACEHOLDER 구역을 프로젝트에 맞게 채운다.
set -euo pipefail

DRY=0
[ "${1:-}" = "--dry-run" ] && DRY=1
run() { echo "+ $*"; [ "$DRY" -eq 1 ] || eval "$*"; }

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

# --- PLACEHOLDER: work/ 하위 빌드 디렉토리별 make clean ---
# 예)
#   for d in work/impl work/bench; do
#     [ -f "$d/Makefile" ] && run "make -C $d clean"
#   done

# --- Makefile 없는 폴더: 공통 빌드 산출물 패턴 수동 제거 (work/ 한정) ---
if [ -d work ]; then
  run "find work -type d \\( -name build -o -name 'obj*' -o -name 'bin-*' \\) -exec rm -rf {} + 2>/dev/null || true"
  run "find work -type f \\( -name '*.o' -o -name '*.d' -o -name '*.su' \\) -delete 2>/dev/null || true"
fi

# .md cross-reference 경로 검증 (실패해도 clean 자체는 막지 않음)
if [[ -x "$ROOT/scripts/check_md_paths.py" ]]; then
  python3 "$ROOT/scripts/check_md_paths.py" || echo "[WARN] 깨진 문서 경로 감지 — 커밋 전 수정 권장"
fi

echo "clean_build: done (dry-run=$DRY)"
