#!/usr/bin/env python3
"""measure_stack.py — pqm4 스택 바이너리를 nucleo-l4r5zi 보드에 플래시하고
keypair/sign/verify 스택 사용량(bytes)을 N회 반복 측정·집계한다.

Falcon keygen 은 RNG 시드 기반 거부 샘플링이라 keypair 스택이 실행마다 변한다.
따라서 N회 반복해 op 별 min/max/median 을 보고한다(worst-case = max 가 프로비저닝 기준).

pqm4 루트(work/pqm4)에서 실행한다 (mupq 패키지 import 필요).

사용법:
  python3 ../measure_stack.py --hex bin/..._stack.hex [-u /dev/ttyACM0] [--iters 10] [--label name]
"""
import argparse
import os
import re
import statistics
import subprocess
import sys

sys.path.insert(0, os.getcwd())  # pqm4 루트에서 실행 → mupq 패키지 탐색
import serial  # noqa: E402

OCD_SCRIPT = "st_nucleo_l4r5.cfg"
START_RE = re.compile(rb'.*={4,}\n', re.DOTALL)


def openocd_flash(hexpath):
    subprocess.check_call(
        ["openocd", "-f", OCD_SCRIPT, "-c", f"program {hexpath} verify reset exit"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def openocd_reset():
    subprocess.check_call(
        ["openocd", "-f", OCD_SCRIPT, "-c", "init; reset run; exit"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def read_one(dev):
    """보드 1회 실행 출력( ==== ~ # )을 읽어 반환."""
    dev.reset_input_buffer()
    if dev.read_until(b'=')[-1:] != b'=':
        raise RuntimeError('start(=) 대기 timeout')
    start = dev.read_until(b'\n')
    if START_RE.fullmatch(start) is None:
        raise RuntimeError(f'start 패턴 불일치: {start!r}')
    out = bytearray()
    while len(out) == 0 or out[-1] != b'#'[0]:
        chunk = dev.read_until(b'#', 256)
        if not chunk:
            raise RuntimeError('end(#) 대기 timeout')
        out.extend(chunk)
    return out[:-1].decode('utf-8', 'ignore')


def parse(out):
    r = {}
    for key, pat in (("keypair", r"keypair stack usage:\s*(\d+)"),
                     ("sign", r"sign stack usage:\s*(\d+)"),
                     ("verify", r"verify stack usage:\s*(\d+)")):
        m = re.search(pat, out)
        r[key] = int(m.group(1)) if m else None
    r["valid"] = "Signature valid!" in out
    r["error"] = "ERROR" in out
    return r


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--hex", required=True)
    ap.add_argument("-u", "--uart", default="/dev/ttyACM0")
    ap.add_argument("--iters", type=int, default=10)
    ap.add_argument("--label", default="")
    args = ap.parse_args()

    dev = serial.Serial(args.uart, 38400, timeout=60)
    samples = {"keypair": [], "sign": [], "verify": []}
    bad = 0
    try:
        for i in range(args.iters):
            if i == 0:
                openocd_flash(args.hex)
            else:
                openocd_reset()
            out = read_one(dev)
            r = parse(out)
            if r["error"] or not r["valid"] or any(r[k] is None for k in samples):
                bad += 1
                print(f"[{args.label}] iter{i} 비정상: valid={r['valid']} error={r['error']} raw={out!r}")
                continue
            for k in samples:
                samples[k].append(r[k])
    finally:
        dev.close()

    print(f"\n[{args.label}] iters={args.iters} bad={bad}")
    print(f"{'op':10} {'min':>7} {'max':>7} {'median':>7}  samples")
    for k in ("keypair", "sign", "verify"):
        s = samples[k]
        if s:
            print(f"{k:10} {min(s):7d} {max(s):7d} {int(statistics.median(s)):7d}  {s}")
        else:
            print(f"{k:10}   (no valid samples)")
    if bad:
        sys.exit(1)


if __name__ == "__main__":
    main()
