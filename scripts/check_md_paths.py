#!/usr/bin/env python3
"""check_md_paths.py — CLAUDE.md 등 문서의 백틱 인라인 경로 실존 검증 스크립트.

문서에 적힌 경로가 실제 레포 상태와 어긋나는 "문서 drift"를 조기에 잡아낸다.
표준 라이브러리만 사용한다.

사용법:
  python3 scripts/check_md_paths.py                  # 루트 CLAUDE.md만 검사
  python3 scripts/check_md_paths.py docs/OPT.md ...   # 추가 .md 문서 지정
"""
import re
import sys
from pathlib import Path

# scripts/ 바로 아래에 위치한다는 전제로 레포 루트를 고정한다 (cwd 무관).
REPO_ROOT = Path(__file__).resolve().parent.parent

GLOB_CHARS = set("*?{}[]")


def find_top_level_dirs(root: Path) -> set:
    """레포 루트의 실존 최상위 디렉터리명을 자동 탐지한다 (숨김 폴더 제외, 하드코딩 금지)."""
    return {p.name for p in root.iterdir() if p.is_dir() and not p.name.startswith(".")}


def extract_inline_code(text: str) -> list:
    """code fence 내부를 제외하고 백틱(`...`) 인라인 코드 조각만 추출한다."""
    text = re.sub(r"```.*?```", "", text, flags=re.DOTALL)
    return re.findall(r"`([^`\n]+)`", text)


def clean_candidate(raw: str) -> str:
    """` §3` 류 위치 참조 접미사와 후행 문장부호를 제거한다."""
    candidate = raw.split(" §", 1)[0].strip()
    return candidate.rstrip(".,;:)]}\"'")


def main() -> int:
    targets = [REPO_ROOT / "CLAUDE.md"]
    for extra in sys.argv[1:]:
        p = Path(extra)
        targets.append(p if p.is_absolute() else REPO_ROOT / extra)

    top_level_dirs = find_top_level_dirs(REPO_ROOT)

    broken = []
    checked = 0
    scanned_docs = 0

    for target in targets:
        if not target.exists():
            print(f"[SKIP] 대상 문서 없음: {target}")
            continue
        scanned_docs += 1
        text = target.read_text(encoding="utf-8", errors="ignore")

        for raw in extract_inline_code(text):
            if any(c in raw for c in GLOB_CHARS):
                continue
            candidate = clean_candidate(raw)
            if not candidate or "/" not in candidate:
                continue
            if "://" in candidate:
                continue

            if candidate.startswith("~/"):
                resolved = Path(candidate).expanduser()
            else:
                top = candidate.split("/", 1)[0]
                if top not in top_level_dirs:
                    # 레포 최상위 디렉터리로 시작하지 않는 문자열은 경로 후보에서 제외
                    continue
                resolved = REPO_ROOT / candidate

            checked += 1
            if not resolved.exists():
                try:
                    label = target.relative_to(REPO_ROOT)
                except ValueError:
                    label = target
                broken.append((label, candidate))

    if broken:
        print(f"[FAIL] 깨진 경로 {len(broken)}건 발견 (검사 {checked}건 중):")
        for label, candidate in broken:
            print(f"  - {label}: `{candidate}`")
        return 1

    print(f"[OK] 문서 {scanned_docs}개, 경로 {checked}건 검사 — 이상 없음")
    return 0


if __name__ == "__main__":
    sys.exit(main())
