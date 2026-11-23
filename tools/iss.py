#!/usr/bin/env python3
"""Instruction-set simulator (golden model) for the Project 9 RV32I subset.

It runs a program image (.hex) with a data image (_data.hex) exactly as the
RTL does (same memory map, same EBREAK rule) and reports:

  * final registers, changed data words, out_port
  * dynamic instruction count and number of LW/SW (Phase I cycle model)
  * expected cache misses for the Phase II hierarchy, from a model of a
    direct-mapped, write-through, no-write-allocate cache:
        split   : I-cache and D-cache of LINES lines each
        unified : one cache of 2*LINES lines for fetches and data

The RTL testbench tb_hier prints the same numbers, and tools/sweep.py checks
that they agree for every configuration.

Usage:
    python3 tools/iss.py programs/memcopy.hex programs/memcopy_data.hex
    python3 tools/iss.py prog.hex data.hex --lines 4 --line-words 4 --json
"""
import argparse
import json
import sys

MASK = 0xFFFFFFFF
IO_ADDR = 0x400
DATA_BASE = 0x400            # physical byte address of data word 0 (unified memory)


def sx(v, bits):
    v &= (1 << bits) - 1
    return v - (1 << bits) if v >> (bits - 1) else v


def signed(v):
    return v - (1 << 32) if v & 0x80000000 else v


def load_hex(path, n):
    words = []
    with open(path) as f:
        for line in f:
            line = line.split("//")[0].strip()
            if line:
                words.append(int(line, 16))
    return (words + [0] * n)[:n]


class DMCache:
    """Direct-mapped, write-through, no-write-allocate: only read misses fill."""

    def __init__(self, lines, line_words):
        self.lines, self.lw = lines, line_words
        self.tags = [None] * lines
        self.misses = 0

    def read(self, byte_addr):
        line = (byte_addr >> 2) // self.lw
        idx, tag = line % self.lines, line // self.lines
        if self.tags[idx] != tag:
            self.misses += 1
            self.tags[idx] = tag

    def write(self, byte_addr):
        pass                    # write hit updates data only; miss does not allocate


def run(prog, data, max_steps=200000, lines=8, line_words=4):
    imem = load_hex(prog, 256)
    dmem = load_hex(data, 256) if data else [0] * 256
    dmem0 = list(dmem)
    x = [0] * 32
    pc, out_port, n_instr, n_ls = 0, 0, 0, 0
    icache, dcache = DMCache(lines, line_words), DMCache(lines, line_words)
    ucache = DMCache(2 * lines, line_words)

    for _ in range(max_steps):
        ins = imem[(pc >> 2) & 0xFF]
        icache.read(pc)
        ucache.read(pc)
        n_instr += 1
        if ins == 0x00100073:                         # EBREAK
            break
        op, rd, f3 = ins & 0x7F, (ins >> 7) & 0x1F, (ins >> 12) & 7
        rs1, rs2, f7 = (ins >> 15) & 0x1F, (ins >> 20) & 0x1F, ins >> 25
        a, b = x[rs1], x[rs2]
        imm_i = sx(ins >> 20, 12)
        nxt, res = (pc + 4) & MASK, None

        if op == 0b0110011:                           # R-type
            r = {(0, 0): a + b, (0x20, 0): a - b, (0, 7): a & b, (0, 6): a | b,
                 (0, 4): a ^ b, (0, 2): int(signed(a) < signed(b)),
                 (0, 1): a << (b & 31), (0, 5): a >> (b & 31)}
            res = r.get((f7, f3))
        elif op == 0b0010011:                         # I-type ALU
            sh = (ins >> 20) & 31
            r = {0: a + imm_i, 7: a & (imm_i & MASK), 6: a | (imm_i & MASK),
                 4: a ^ (imm_i & MASK), 2: int(signed(a) < imm_i)}
            if f3 in r:
                res = r[f3]
            elif f3 == 1 and f7 == 0:
                res = a << sh
            elif f3 == 5 and f7 == 0:
                res = a >> sh
        elif op == 0b0000011 and f3 == 2:             # LW
            addr = (a + imm_i) & MASK
            n_ls += 1
            if addr < 0x400:
                dcache.read(addr)
                ucache.read(addr + DATA_BASE)
                res = dmem[addr >> 2]
            else:
                res = 0                               # out_port / invalid read as 0
        elif op == 0b0100011 and f3 == 2:             # SW
            addr = (a + sx(((ins >> 25) << 5) | ((ins >> 7) & 0x1F), 12)) & MASK
            n_ls += 1
            if addr < 0x400:
                dcache.write(addr)
                ucache.write(addr + DATA_BASE)
                dmem[addr >> 2] = b
            elif addr == IO_ADDR:
                out_port = b
        elif op == 0b1100011:                         # branches
            imm_b = sx((((ins >> 31) & 1) << 12) | (((ins >> 7) & 1) << 11)
                       | (((ins >> 25) & 0x3F) << 5) | (((ins >> 8) & 0xF) << 1), 13)
            take = {0: a == b, 1: a != b, 4: signed(a) < signed(b),
                    5: signed(a) >= signed(b)}.get(f3, False)
            if take:
                nxt = (pc + imm_b) & MASK
        elif op == 0b1101111:                         # JAL
            imm_j = sx((((ins >> 31) & 1) << 20) | (((ins >> 12) & 0xFF) << 12)
                       | (((ins >> 20) & 1) << 11) | (((ins >> 21) & 0x3FF) << 1), 21)
            res, nxt = pc + 4, (pc + imm_j) & MASK
        elif op == 0b1100111 and f3 == 0:             # JALR
            res, nxt = pc + 4, (a + imm_i) & MASK & ~1
        elif op == 0b0110111:                         # LUI
            res = ins & 0xFFFFF000

        if res is not None and rd != 0:
            x[rd] = res & MASK
        pc = nxt
    else:
        raise RuntimeError("no EBREAK within max_steps")

    return {
        "instr": n_instr, "ls": n_ls, "regs": x, "out_port": out_port,
        "dmem": dmem, "changed": {i: dmem[i] for i in range(256) if dmem[i] != dmem0[i]},
        "i_miss": icache.misses, "d_miss": dcache.misses, "u_miss": ucache.misses,
    }


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("prog")
    ap.add_argument("data", nargs="?")
    ap.add_argument("--lines", type=int, default=8, help="lines per split cache (unified = 2x)")
    ap.add_argument("--line-words", type=int, default=4)
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()
    r = run(a.prog, a.data, lines=a.lines, line_words=a.line_words)
    if a.json:
        r = dict(r)
        r.pop("dmem")
        json.dump(r, sys.stdout)
        print()
        return
    print(f"instructions {r['instr']}  LW/SW {r['ls']}  out_port {r['out_port']}")
    print("registers   " + " ".join(f"x{i}={v}" for i, v in enumerate(r["regs"]) if v))
    print("changed data " + " ".join(f"[{k}]={v}" for k, v in r["changed"].items()))
    print(f"misses (lines={a.lines}, line_words={a.line_words}): "
          f"split I={r['i_miss']} D={r['d_miss']}  unified({2 * a.lines})={r['u_miss']}")


if __name__ == "__main__":
    main()
