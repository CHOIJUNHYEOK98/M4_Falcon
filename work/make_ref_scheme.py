#!/usr/bin/env python3
"""make_ref_scheme.py — NIST Round3 Falcon 레퍼런스를 pqm4 스킴으로 포팅한다.

레퍼런스 코어 파일 복사 + nist.c → pqm4.c 각색:
  - crypto_sign/*의 unsigned long long → size_t (pqm4 하네스 size_t API 정합)
  - 지역 randombytes 선언 제거 → pqm4의 randombytes.h 사용
  - TEMPALLOC 매크로: 빈 값(스택 할당) 또는 'static'(.bss 할당)

사용법:
  python3 make_ref_scheme.py <ref_int_dir> <m4ct_dir> <dst_dir> <stack|static>
"""
import re
import shutil
import sys
from pathlib import Path

CORE = ["codec.c", "common.c", "fft.c", "fpr.c", "fpr.h",
        "inner.h", "keygen.c", "rng.c", "shake.c", "sign.c", "vrfy.c"]


def main():
    ref_dir, m4ct_dir, dst_dir, mode = sys.argv[1:5]
    ref, m4ct, dst = Path(ref_dir), Path(m4ct_dir), Path(dst_dir)
    dst.mkdir(parents=True, exist_ok=True)

    # 코어 파일 (순수 레퍼런스)
    for f in CORE:
        shutil.copy(ref / f, dst / f)

    # api.h 는 m4-ct 것(size_t 선언 + pqm4 정합, 사이즈 동일) 사용
    shutil.copy(m4ct / "api.h", dst / "api.h")

    # nist.c → pqm4.c 각색
    src = (ref / "nist.c").read_text()

    # 1) 지역 randombytes 선언 블록 제거
    src = re.sub(
        r'void randombytes_init\([^;]*\);\s*int randombytes\([^;]*\);\s*',
        '', src, flags=re.DOTALL)

    # 2) inner.h include 뒤에 randombytes.h 추가
    src = src.replace('#include "inner.h"',
                      '#include "inner.h"\n#include "randombytes.h"', 1)

    # 3) unsigned long long → size_t (남은 것은 crypto_sign 시그니처뿐)
    src = src.replace('unsigned long long', 'size_t')

    # 4) TEMPALLOC 정의
    tempalloc = 'static' if mode == 'static' else ''
    src = re.sub(r'#define TEMPALLOC\b.*', f'#define TEMPALLOC {tempalloc}'.rstrip(), src, count=1)

    (dst / "pqm4.c").write_text(src)
    print(f"[OK] {dst} 생성 (mode={mode}, TEMPALLOC='{tempalloc}')")


if __name__ == "__main__":
    main()
