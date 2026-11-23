#!/usr/bin/env python3
"""Turn the Yosys 'stat' outputs in results/synth/*_stat.txt into the area table.

Counting rules (Xilinx 7-series):
  logic LUTs = LUT1..LUT6 + INV (an INV is a LUT1)
  LUT-RAM    = 4 LUTs per RAM256X1S, RAM64M and RAM32M cell
  FFs        = FDRE + FDSE + FDCE + FDPE
Run from the repository root:  python3 tools/synth_table.py
"""
import re
import sys

DESIGNS = [("harvard", "Ideal Harvard: core + data side + counters (ROM separate)"),
           ("rom", "Ideal Harvard: instruction ROM 256x32"),
           ("vn", "Ideal shared memory (vn_top)"),
           ("mh", "Modified Harvard: core + I/D caches 8+8 lines + arbiter (main_mem separate)"),
           ("vnc", "VN + unified cache 16 lines (main_mem separate)"),
           ("mainmem", "Lower-level memory model 512x32, 4-word line port")]


def cells(path):
    c = {}
    for line in open(path):
        m = re.match(r"\s+(\d+)\s+([A-Z][A-Z0-9_]+)\s*$", line)
        if m:
            c[m.group(2)] = c.get(m.group(2), 0) + int(m.group(1))
    return c


def main():
    rows = []
    print("| Design | Logic LUTs | LUT-RAM LUTs | Total LUTs | Flip-flops | CARRY4 |")
    print("|---|---|---|---|---|---|")
    for key, name in DESIGNS:
        try:
            c = cells(f"results/synth/{key}_stat.txt")
        except FileNotFoundError:
            print(f"| {name} | (missing {key}_stat.txt) |", file=sys.stderr)
            continue
        logic = sum(v for k, v in c.items() if re.fullmatch(r"LUT[1-6]|INV", k))
        ram = 4 * sum(c.get(k, 0) for k in ("RAM256X1S", "RAM64M", "RAM32M"))
        ff = sum(c.get(k, 0) for k in ("FDRE", "FDSE", "FDCE", "FDPE"))
        rows.append((key, logic, ram, ff))
        print(f"| {name} | {logic} | {ram} | {logic + ram} | {ff} | {c.get('CARRY4', 0)} |")


if __name__ == "__main__":
    main()
