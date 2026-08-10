#!/usr/bin/env python3
"""verify_regression.py — pqm4 testvectors 바이너리를 nucleo-l4r5zi 보드에 플래시하고
출력 전체를 받아 baseline 과 비트 단위로 비교한다.

testvectors 하네스(`mupq/crypto_sign/testvectors.c`)는 결정론적 난수(DJB surf)를 쓰므로
같은 코드라면 출력이 항상 동일하다. 메시지 길이 0,1,2,...,1024 (12종) 각각에 대해
keypair/sign 을 수행하고 pk·sk·sm 을 16진수로 출력하며, crypto_sign_open 으로 검증하고
메시지 복원까지 확인한다. 검증이 실패하면 출력에 ERROR 가 포함된다.

따라서 "수정 전 출력 == 수정 후 출력" 이면 키 생성·서명·검증 전 경로가 동일하게 동작한다.

pqm4 루트(work/pqm4)에서 실행한다.

사용법:
  # 수정 전 baseline 저장
  python3 ../verify_regression.py --hex bin/..._testvectors.hex --save ../baseline/512.txt
  # 수정 후 비교
  python3 ../verify_regression.py --hex bin/..._testvectors.hex --compare ../baseline/512.txt
"""
import argparse
import hashlib
import os
import re
import subprocess
import sys

import serial

OCD_SCRIPT = "st_nucleo_l4r5.cfg"
START_RE = re.compile(rb'.*={4,}\n', re.DOTALL)


def openocd_flash(hexpath):
    subprocess.check_call(
        ["openocd", "-f", OCD_SCRIPT, "-c", f"program {hexpath} verify reset exit"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def _read_chunk(dev, retries=20):
    """USB CDC 가 일시적으로 끊겨도(WSL2 에서 간헐 발생) 재시도하며 읽는다."""
    fails = 0
    while True:
        try:
            return dev.read(max(1, dev.in_waiting))
        except serial.SerialException as e:
            fails += 1
            if fails > retries:
                raise
            print(f"  (시리얼 일시 오류 {fails}/{retries}: {e} — 재시도)", file=sys.stderr)
            time.sleep(0.3)


def read_one(dev):
    """보드 1회 실행 출력( ==== ~ # )을 읽어 반환."""
    dev.reset_input_buffer()
    if dev.read_until(b'=')[-1:] != b'=':
        raise RuntimeError('start(=) 대기 timeout')
    start = dev.read_until(b'\n')
    if START_RE.fullmatch(start) is None:
        raise RuntimeError(f'start 패턴 불일치: {start!r}')
    out = bytearray()
    while b'#' not in out:
        chunk = _read_chunk(dev)
        if not chunk:
            raise RuntimeError('end(#) 대기 timeout')
        out.extend(chunk)
    return out[:out.index(b'#')].decode('utf-8', 'ignore')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--hex", required=True)
    ap.add_argument("-u", "--uart", default="/dev/ttyACM0")
    ap.add_argument("--save", help="출력을 이 경로에 baseline 으로 저장")
    ap.add_argument("--compare", help="이 경로의 baseline 과 비교")
    ap.add_argument("--timeout", type=int, default=180)
    args = ap.parse_args()

    if not args.save and not args.compare:
        sys.exit("--save 또는 --compare 중 하나는 필요하다")

    dev = serial.Serial(args.uart, 38400, timeout=args.timeout)
    try:
        openocd_flash(args.hex)
        out = read_one(dev)
    finally:
        dev.close()

    digest = hashlib.sha3_256(out.strip().encode('utf-8')).hexdigest()
    nlines = len(out.strip().splitlines())
    print(f"hex     : {args.hex}")
    print(f"출력    : {len(out)} bytes, {nlines} lines")
    print(f"sha3-256: {digest}")

    if "ERROR" in out:
        print("실패: 출력에 ERROR 포함 (보드에서 검증/복원 실패)")
        sys.exit(1)
    # 12개 메시지 길이 × (pk, sk, sm) = 36 줄이 기대치
    if nlines != 36:
        print(f"경고: 출력 줄 수가 36 이 아니다 ({nlines}) — 실행이 중간에 끊겼을 수 있다")

    if args.save:
        os.makedirs(os.path.dirname(os.path.abspath(args.save)), exist_ok=True)
        with open(args.save, 'w') as f:
            f.write(out.strip() + "\n")
        print(f"baseline 저장: {args.save}")

    if args.compare:
        with open(args.compare) as f:
            ref = f.read().strip()
        if ref == out.strip():
            print(f"일치: baseline({args.compare}) 과 출력이 비트 단위로 동일하다")
            return
        print(f"불일치: baseline({args.compare}) 과 출력이 다르다")
        ref_lines, out_lines = ref.splitlines(), out.strip().splitlines()
        print(f"  baseline {len(ref_lines)} lines / 출력 {len(out_lines)} lines")
        for i, (a, b) in enumerate(zip(ref_lines, out_lines)):
            if a != b:
                print(f"  첫 불일치 line {i + 1}: baseline={a[:64]}... 출력={b[:64]}...")
                break
        sys.exit(1)


if __name__ == "__main__":
    main()
