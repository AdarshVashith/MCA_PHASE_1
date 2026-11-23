# Harvard vs shared-memory comparison

> Phase II results for the memory hierarchy (caches, latency, split vs unified, write buffer)
> are in [hier/summary.md](hier/summary.md); every run is listed in [hier/sweep.csv](hier/sweep.csv).

Numbers copied from `results/logs/compare.log`, produced by `make compare` (Icarus Verilog 13.0).
Each row is one program run on both `harvard_top` and `vn_top`; `tb_compare` checked that all 32
registers, all 256 data words and `out_port` are identical on both designs.

| Program | Instr | LW/SW % | Harvard cycles | Harvard CPI | Baseline cycles | Baseline CPI | Speed-up | Simultaneous cycles (Harvard) |
|---|---|---|---|---|---|---|---|---|
| basic       |  19 | 36.8% |  19 | 1.00 |   26 | 1.37 | 1.37x |   7 |
| array_sum   |  38 | 26.3% |  38 | 1.00 |   48 | 1.26 | 1.26x |  10 |
| memcopy     |  54 | 31.5% |  54 | 1.00 |   71 | 1.31 | 1.31x |  17 |
| count_loop  |  64 |  1.6% |  64 | 1.00 |   65 | 1.02 | 1.02x |   1 |
| isa_test    |  38 | 13.2% |  38 | 1.00 |   43 | 1.13 | 1.13x |   5 |
| bubble_sort | 826 | 44.7% | 826 | 1.00 | 1195 | 1.45 | 1.45x | 369 |
| func_call   | 268 |  4.1% | 268 | 1.00 |  279 | 1.04 | 1.04x |  11 |
| transpose   | 769 | 17.9% | 769 | 1.00 |  907 | 1.18 | 1.18x | 138 |

The last four programs were added in Phase II and use the extended instruction set
(25 RV32I instructions). The first four rows are unchanged from Phase I.

Baseline simultaneous cycles are 0 for every program (one memory port).

## How to read it

- Harvard CPI is exactly 1.00: the fetch uses the instruction memory and LW/SW use the data
  memory in the same cycle, so no instruction ever waits.
- Baseline cycles = Harvard cycles + number of LW/SW, for every program. Each load or store
  needs the single port twice (fetch, then data), so it costs one extra cycle.
- So baseline CPI = 1 + (LW/SW fraction), and the speed-up grows with the memory intensity of the
  program: 1.02x for the compute loop, 1.26x-1.37x for the memory-heavy programs.
- "Simultaneous cycles" on Harvard equals the number of data accesses: every data access overlapped
  with a fetch.

## Counting conventions

- EBREAK is counted as one retired instruction and its cycle is counted; counters freeze after it.
- Stores to `out_port` and accesses to invalid addresses count as data accesses on both designs
  (they still occupy the data path / the single bus for a cycle).

## Synthesis (Yosys, Xilinx 7-series)

Generic FPGA synthesis with Yosys 0.71 (`synth_xilinx -family xc7`, flattened), using the
scripts in `results/synth/`. Re-run in Phase II, because the processor now implements 25
instructions instead of 10 (both cores grew). Full logs are in `results/logs/synth_*.log`
and the raw cell counts in `results/synth/*_stat.txt`. To reproduce, from the repository root:

```sh
for d in harvard rom vn mh vnc mainmem; do
  yosys -q -l results/logs/synth_$d.log results/synth/synth_$d.ys
done
python3 tools/synth_table.py        # prints the table below
```

| Design | Logic LUTs | LUT-RAM LUTs | Total LUTs | Flip-flops | CARRY4 |
|---|---|---|---|---|---|
| harvard_top: core, data side, counters (ROM separate) | 761 | 176 | 937 | 194 | 69 |
| harvard_top: instruction ROM 256 x 32 | 128 | 0 | 128 | 0 | 0 |
| **harvard_top total** | **889** | **176** | **1065** | **194** | **69** |
| **vn_top total** | **1032** | **304** | **1336** | **227** | **69** |
| **mh_top**: core + I/D caches 8+8 lines + arbiter (main_mem separate) | **3864** | **56** | **3920** | **2520** | **123** |
| **vnc_top**: core + unified cache 16 lines (main_mem separate) | **4833** | **52** | **4885** | **2452** | **99** |
| main_mem model 512 x 32, 4-word line port (for reference) | 653 | 1408 | 2061 | 8 | 2 |

How the numbers were counted (`tools/synth_table.py`):

- Logic LUTs = LUT1-LUT6 plus INV cells (an INV is a LUT1 on 7-series).
- LUT-RAM = 4 LUTs per RAM256X1S, RAM64M and RAM32M cell.

Things to know before quoting these numbers:

1. **The Harvard instruction ROM is measured on its own** (`synth_rom.ys`, pseudo-random
   contents). Synthesized together with one program, Yosys would hard-wire that program into
   the core and delete logic for instructions it never uses; a writable memory does not allow
   that.
2. **main_mem is a black box in the Phase II tops.** It stands for the lower level of the
   hierarchy (block RAM or off-chip memory) and is identical in mh_top and vnc_top, so the
   table compares the core plus the level-1 hierarchy. `synth_mainmem.ys` measures the
   memory model alone.
3. **Cache data arrays are flip-flops.** A refill writes four words in one cycle, so Yosys
   cannot map the arrays to LUT-RAM: 2 x 32 x 32 bits (mh_top) or 64 x 32 bits (vnc_top) =
   2048 flip-flops in both. A refill of one word per cycle would fix this.
4. **Yosys initialisation workaround.** The memories zero-fill every word and then call
   `$readmemh` in the same `initial` block; Yosys 0.71 lets the zero-fill win. The scripts
   delete the one-word zero-fill init cells after `proc`. No RTL is changed.
5. **Logic loops.** vn_top and vnc_top have a structural false loop through the single bus
   (`m_addr` -> memory/cache -> `m_rdata`/`m_ready` -> `instr` -> ALU -> `m_addr`) that can
   never be active. harvard_top and mh_top have none (mh_top was designed to avoid it: no
   refill forwarding, registered-only memory ready and arbiter grant).
6. **Fmax is not measured.** Yosys has no timing model for 7-series; it needs Vivado.

**Result:** with ideal memories, the Harvard design uses about 20% fewer LUTs (1065 vs 1336)
and 33 fewer flip-flops than the shared-memory baseline (34% in Phase I, before the
instruction set grew). With caches, the split hierarchy again uses about 20% fewer LUTs
(3920 vs 4885) than the unified one, for practically the same number of flip-flops.
