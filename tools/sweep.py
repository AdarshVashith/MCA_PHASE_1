#!/usr/bin/env python3
"""Phase II parameter sweep for the memory-hierarchy study.

For every (program, LATENCY, LINES, WBUF) configuration it compiles and runs
tb_hier with Icarus Verilog, which simulates four organisations side by side
(ideal Harvard, modified Harvard with split caches, von Neumann with a unified
cache of the same total size, von Neumann without a cache) and self-checks the
architectural state. Then it cross-checks the miss counts reported by the RTL
against tools/iss.py (independent Python model of the same caches).

Outputs (in results/hier/):
    sweep.csv        every run, every counter, plus the ISS prediction
    summary.md       the tables used in the report
    latency.dat      geometric-mean CPI vs memory latency   (pgfplots data)
    size.dat         geometric-mean CPI vs cache size        (pgfplots data)
and copies of the two .dat files in report/data/ for the report figures.

Run from sim/:  make sweep      (or: python3 ../tools/sweep.py --rtl "<files>")
"""
import argparse
import concurrent.futures as cf
import csv
import math
import os
import shlex
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import iss  # noqa: E402

PROGRAMS = ["basic", "array_sum", "memcopy", "count_loop",
            "isa_test", "bubble_sort", "func_call", "transpose"]
LATENCIES = [1, 2, 4, 8, 16]
SIZES = [1, 2, 4, 8, 16, 32]           # lines per split cache (unified = 2x)
BASE_L, BASE_LINES = 4, 8

FIELDS = ["prog", "L", "lines", "line_words", "wbuf", "instr", "ls", "ideal_h", "ideal_vn",
          "mh_cyc", "mh_imiss", "mh_dmiss", "mh_istall", "mh_dstall", "mh_conflict",
          "mh_wbstall", "mh_simul", "uc_cyc", "uc_miss", "uc_stall", "uc_wbstall", "nc_cyc"]


def configs():
    seen, out = set(), []
    for p in PROGRAMS:
        for L in LATENCIES:                       # latency sweep
            out.append((p, L, BASE_LINES, 1))
        for n in SIZES:                           # size sweep
            out.append((p, BASE_L, n, 1))
        for L in (BASE_L, 8, 16):                 # write-buffer ablation
            out.append((p, L, BASE_LINES, 0))
    return [c for c in out if not (c in seen or seen.add(c))]


def run_one(cfg, rtl, build):
    p, L, n, wb = cfg
    exe = os.path.join(build, f"sweep_{p}_L{L}_n{n}_w{wb}.vvp")
    cmd = (["iverilog", "-g2005", "-I", "../tb", "-s", "tb_hier",
            f'-Ptb_hier.PROG_NAME="{p}"', f'-Ptb_hier.PROG_FILE="../programs/{p}.hex"',
            f'-Ptb_hier.DATA_FILE="../programs/{p}_data.hex"',
            f"-Ptb_hier.LATENCY={L}", f"-Ptb_hier.LINES={n}", f"-Ptb_hier.WBUF={wb}",
            "-o", exe, "../tb/tb_hier.v"] + shlex.split(rtl))
    subprocess.run(cmd, check=True, capture_output=True, text=True)
    out = subprocess.run(["vvp", "-n", exe], check=True, capture_output=True, text=True).stdout
    os.remove(exe)
    rows = [l for l in out.splitlines() if l.startswith("ROW,")]
    passed = any(l.startswith("tb_hier(") and l.endswith("PASS") for l in out.splitlines())
    if not rows:
        raise RuntimeError(f"{cfg}: no ROW line\n{out}")
    vals = rows[0].split(",")[1:]
    row = {k: (v if k == "prog" else int(v)) for k, v in zip(FIELDS, vals)}
    row["rtl_pass"] = passed
    if not passed:
        row["log"] = out
    return row


def gmean(xs):
    return math.exp(sum(math.log(x) for x in xs) / len(xs))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--rtl", required=True, help="space-separated RTL file list (from the Makefile)")
    ap.add_argument("--out", default="../results/hier")
    ap.add_argument("-j", type=int, default=os.cpu_count() or 4)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    os.makedirs("build", exist_ok=True)

    cfgs = configs()
    print(f"running {len(cfgs)} configurations on {a.j} workers ...", flush=True)
    with cf.ThreadPoolExecutor(a.j) as ex:
        rows = list(ex.map(lambda c: run_one(c, a.rtl, "build"), cfgs))

    # ---- cross-check against the ISS cache model ----
    bad = 0
    for r in rows:
        m = iss.run(f"../programs/{r['prog']}.hex", f"../programs/{r['prog']}_data.hex",
                    lines=r["lines"], line_words=r["line_words"])
        r.update(iss_instr=m["instr"], iss_ls=m["ls"], iss_imiss=m["i_miss"],
                 iss_dmiss=m["d_miss"], iss_umiss=m["u_miss"])
        ok = (r["rtl_pass"] and r["instr"] == m["instr"] and r["ls"] == m["ls"]
              and r["mh_imiss"] == m["i_miss"] and r["mh_dmiss"] == m["d_miss"]
              and r["uc_miss"] == m["u_miss"])
        r["check"] = "PASS" if ok else "FAIL"
        if not ok:
            bad += 1
            print("MISMATCH", {k: r[k] for k in r if k != "log"})
            if "log" in r:
                print(r["log"])

    rows.sort(key=lambda r: (PROGRAMS.index(r["prog"]), r["wbuf"], r["L"], r["lines"]))
    cols = FIELDS + ["iss_instr", "iss_ls", "iss_imiss", "iss_dmiss", "iss_umiss", "check"]
    with open(os.path.join(a.out, "sweep.csv"), "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=cols, extrasaction="ignore")
        w.writeheader()
        w.writerows(rows)

    def sel(L=None, n=None, wb=1):
        return [r for r in rows if (L is None or r["L"] == L) and (n is None or r["lines"] == n)
                and r["wbuf"] == wb]

    cpi = lambda r, k: r[k] / r["instr"]
    md = ["# Phase II memory-hierarchy results",
          "",
          "Generated by `make sweep` (tools/sweep.py) from tb_hier simulations (Icarus Verilog).",
          f"{len(rows)} configurations, {len(rows) - bad} passed all RTL self-checks and matched",
          "the miss counts predicted by the ISS cache model (tools/iss.py).",
          "",
          "Systems: **H** ideal Harvard (Phase I), **VN** ideal shared memory (Phase I),",
          "**MH** modified Harvard (split I/D caches, shared memory), **UC** von Neumann with",
          "one unified cache of the same total size, **NC** von Neumann without a cache.",
          "Cache: direct-mapped, 4-word lines, write-through, no-write-allocate, 1-entry",
          "write buffer. Miss penalty = LATENCY cycles.",
          ""]

    # Table A: base configuration per program
    md += [f"## A. Per program, LATENCY = {BASE_L}, {BASE_LINES}+{BASE_LINES} split lines vs "
           f"{2 * BASE_LINES} unified lines", "",
           "| Program | Instr | LW/SW % | H CPI | VN CPI | MH CPI | UC CPI | NC CPI | I-miss | D-miss | U-miss | MH speed-up over UC |",
           "|---|---|---|---|---|---|---|---|---|---|---|---|"]
    for r in sel(BASE_L, BASE_LINES):
        md.append(f"| {r['prog']} | {r['instr']} | {100 * r['ls'] / r['instr']:.1f} | "
                  f"{cpi(r, 'ideal_h'):.2f} | {cpi(r, 'ideal_vn'):.2f} | {cpi(r, 'mh_cyc'):.2f} | "
                  f"{cpi(r, 'uc_cyc'):.2f} | {cpi(r, 'nc_cyc'):.2f} | {r['mh_imiss']} | {r['mh_dmiss']} | "
                  f"{r['uc_miss']} | {r['uc_cyc'] / r['mh_cyc']:.2f}x |")

    # Table B / latency.dat: geomean CPI vs latency
    md += ["", f"## B. Geometric-mean CPI over the 8 programs vs memory latency ({BASE_LINES}+{BASE_LINES} lines)", "",
           "| LATENCY | H | VN | MH | UC | NC |", "|---|---|---|---|---|---|"]
    lat_lines = ["L H VN MH UC NC"]
    for L in LATENCIES:
        rs = sel(L, BASE_LINES)
        g = [gmean([cpi(r, k) for r in rs]) for k in ("ideal_h", "ideal_vn", "mh_cyc", "uc_cyc", "nc_cyc")]
        md.append(f"| {L} | " + " | ".join(f"{x:.2f}" for x in g) + " |")
        lat_lines.append(f"{L} " + " ".join(f"{x:.4f}" for x in g))
    with open(os.path.join(a.out, "latency.dat"), "w") as f:
        f.write("\n".join(lat_lines) + "\n")

    # Table C / size.dat: geomean CPI and total misses vs size
    md += ["", f"## C. Cache size at LATENCY = {BASE_L} (split n+n lines vs unified 2n lines)", "",
           "| Lines per split cache | Total capacity (words) | MH CPI | UC CPI | MH misses (all programs) | UC misses (all programs) |",
           "|---|---|---|---|---|---|"]
    size_lines = ["n words MH UC MHmiss UCmiss"]
    for n in SIZES:
        rs = sel(BASE_L, n)
        gm, gu = gmean([cpi(r, "mh_cyc") for r in rs]), gmean([cpi(r, "uc_cyc") for r in rs])
        mm = sum(r["mh_imiss"] + r["mh_dmiss"] for r in rs)
        um = sum(r["uc_miss"] for r in rs)
        md.append(f"| {n} | {2 * n * 4} | {gm:.2f} | {gu:.2f} | {mm} | {um} |")
        size_lines.append(f"{n} {2 * n * 4} {gm:.4f} {gu:.4f} {mm} {um}")
    with open(os.path.join(a.out, "size.dat"), "w") as f:
        f.write("\n".join(size_lines) + "\n")

    # Table D: write buffer ablation
    md += ["", f"## D. Write buffer on/off (MH, {BASE_LINES}+{BASE_LINES} lines)", "",
           "| Program | LW/SW % | MH CPI L=4 no buffer | with buffer | MH CPI L=16 no buffer | with buffer | gain at L=16 |",
           "|---|---|---|---|---|---|---|"]
    for p in PROGRAMS:
        def g(L, wb):
            return next(r for r in rows if r["prog"] == p and r["L"] == L and r["lines"] == BASE_LINES
                        and r["wbuf"] == wb)
        r40, r41, r160, r161 = g(4, 0), g(4, 1), g(16, 0), g(16, 1)
        md.append(f"| {p} | {100 * r41['ls'] / r41['instr']:.1f} | {cpi(r40, 'mh_cyc'):.2f} | "
                  f"{cpi(r41, 'mh_cyc'):.2f} | {cpi(r160, 'mh_cyc'):.2f} | {cpi(r161, 'mh_cyc'):.2f} | "
                  f"{r160['mh_cyc'] / r161['mh_cyc']:.2f}x |")

    # Table E: where MH stall cycles come from at the base config
    md += ["", f"## E. Modified Harvard stall breakdown (LATENCY = {BASE_L}, {BASE_LINES}+{BASE_LINES} lines)", "",
           "| Program | cycles | instr | I-stall | D-stall | of which write-buffer | arbiter conflict cycles | simultaneous fetch+data cycles |",
           "|---|---|---|---|---|---|---|---|"]
    for r in sel(BASE_L, BASE_LINES):
        md.append(f"| {r['prog']} | {r['mh_cyc']} | {r['instr']} | {r['mh_istall']} | {r['mh_dstall']} | "
                  f"{r['mh_wbstall']} | {r['mh_conflict']} | {r['mh_simul']} |")

    # copies of the plot data for the report (report/figures/*.tex read them)
    rep = os.path.join(a.out, "..", "..", "report", "data")
    os.makedirs(rep, exist_ok=True)
    for name, lines in (("latency.dat", lat_lines), ("size.dat", size_lines)):
        with open(os.path.join(rep, name), "w") as f:
            f.write("\n".join(lines) + "\n")

    with open(os.path.join(a.out, "summary.md"), "w") as f:
        f.write("\n".join(md) + "\n")

    print("\n".join(md))
    print(f"\nsweep: {len(rows)} configurations, {bad} failures")
    print("SWEEP", "PASS" if bad == 0 else f"FAIL ({bad})")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
