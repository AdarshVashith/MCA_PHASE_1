# Harvard vs shared-memory comparison

Numbers copied from `results/logs/compare.log`, produced by `make compare` (Icarus Verilog 13.0).
Each row is one program run on both `harvard_top` and `vn_top`; `tb_compare` checked that all 32
registers, all 256 data words and `out_port` are identical on both designs.

| Program | Instr | LW/SW % | Harvard cycles | Harvard CPI | Baseline cycles | Baseline CPI | Speed-up | Simultaneous cycles (Harvard) |
|---|---|---|---|---|---|---|---|---|
| basic      | 19 | 36.8% | 19 | 1.00 | 26 | 1.37 | 1.37x |  7 |
| array_sum  | 38 | 26.3% | 38 | 1.00 | 48 | 1.26 | 1.26x | 10 |
| memcopy    | 54 | 31.5% | 54 | 1.00 | 71 | 1.31 | 1.31x | 17 |
| count_loop | 64 |  1.6% | 64 | 1.00 | 65 | 1.02 | 1.02x |  1 |

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

## Synthesis (optional, not yet run)

| Design | LUTs | Flip-flops | Fmax |
|---|---|---|---|
| harvard_top | TODO | TODO | TODO |
| vn_top      | TODO | TODO | TODO |
