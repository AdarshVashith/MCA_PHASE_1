# Project 9: Instruction and Data Memory Hierarchy

**Modern Computer Architecture, Phase I.** A Harvard-style memory organisation in Verilog (separate
instruction and data memories), driven by a small single-cycle RV32I-subset processor and compared
against a shared-memory (Von Neumann) baseline.

With separate memories, the processor fetches the next instruction and performs a load or store in
the **same clock cycle**, so every instruction takes one cycle (CPI = 1.00). In the baseline, code
and data share one memory port, so each load or store costs an extra cycle
(CPI = 1 + load/store fraction). We run the same programs on both and measure the difference.

## Team

| Member | Name / GitHub | Role | Owns |
|---|---|---|---|
| Member 1 | `@kanishksharma04` | Harvard memory core | `rtl/mem/` |
| Member 2 | Adarsh Vashistha (`@AdarshVashith`) | Processor and top-level integration | `rtl/core/`, `rtl/harvard_top.v` |
| Member 3 | `@deepanshu-sharma425` | Shared-memory baseline and metrics | `rtl/common/`, `rtl/baseline/`, `results/comparison.md` |
| Member 4 | `@emphor11` | Verification and programs | `tb/`, `programs/`, `tools/`, `sim/` |
| Member 5 | `@Adrenox20` | Report, video, repository lead | `report/`, `video/`, `docs/`, `README.md` |

## Block diagram

```
                Harvard (harvard_top)                          Baseline (vn_top)

             +-----------+   i_addr   +-----------+         +-------------+  m_addr  +------------+
             |           |----------->| instr_mem |         |             |--------->|            |
             |           |<-----------|  (ROM)    |         | cpu_core_vn |<---------| shared_mem |
             | cpu_core  |   i_rdata  +-----------+         | FETCH_EXEC/ | m_rdata  | code 0-255 |
             | (single   |                                  |    MEM FSM  |--------->| data 256-  |
             |  cycle)   |   d_addr   +-----------+         +-------------+  m_we    |       511  |
             |           |----------->| decoder + |                ^                 +------------+
             |           |<-----------| rw_ctrl + |--> out_port    |  one port: fetch OR data
             +-----------+   d_rdata  | data_mem  |                   access, never both
                   |                  +-----------+
                   v
             perf_counters (cycles, instructions, data accesses, simultaneous cycles)
```

Detailed figures (block diagram, datapath, FSM, waveform) are in the report, `report/main.pdf`.

## Memory map (data side, identical on both designs)

| Byte address | Region |
|---|---|
| `0x000`-`0x3FF` | Data RAM, 256 words |
| `0x400` | `out_port` register (write-only, reads 0) |
| anything else | invalid: write ignored, read returns 0, `d_fault` = 1 |

Instructions live in a separate 256-word ROM (Harvard) or in words 0-255 of the shared memory
(baseline, where data occupies words 256-511).

## Running the simulation

Requirements: Icarus Verilog (`iverilog`, `vvp`), Python 3, and a waveform viewer: GTKWave, or
[Surfer](https://surfer-project.org/) on macOS (`brew install surfer`; Homebrew no longer ships GTKWave).

```sh
cd sim
make asm       # assemble programs/*.s -> *.hex (and run the assembler self-test)
make unit      # unit tests: addr_decoder, instr_mem, data_mem, harvard_mem
make harvard   # every program on the Harvard system
make vn        # every program on the shared-memory baseline
make compare   # both designs side by side, prints the comparison table
make waves PROG=memcopy   # open the comparison waveform (GTKWave, or Surfer if no GTKWave)
make figure    # regenerate the report's waveform figure from the simulation
```

The report compiles with any LaTeX distribution or Overleaf (`report/main.tex`), or locally with
`tectonic report/main.tex`. All figures are TikZ sources in `report/figures/`.

Every testbench is self-checking and ends with `PASS` or `FAIL (n errors)`. Logs are written to
`results/logs/`.

## Repository layout

```
rtl/mem/        instr_mem, data_mem, addr_decoder, rw_ctrl, harvard_mem
rtl/core/       pc_reg, regfile, alu, imm_gen, control, cpu_core
rtl/harvard_top.v
rtl/common/     perf_counters
rtl/baseline/   shared_mem, cpu_core_vn, vn_top
tb/             unit, system and comparison testbenches
programs/       basic, array_sum, memcopy, count_loop (.s, .hex, _data.hex)
tools/asm.py    assembler for the instruction subset
sim/Makefile    build and run targets
results/        comparison table and simulation logs
report/         IEEE-format report (LaTeX)
video/          video script and link
```

## Results

Measured by `make compare`; full table and discussion in [results/comparison.md](results/comparison.md).

| Program | LW/SW % | Harvard CPI | Baseline CPI | Speed-up |
|---|---|---|---|---|
| basic      | 36.8% | 1.00 | 1.37 | 1.37x |
| array_sum  | 26.3% | 1.00 | 1.26 | 1.26x |
| memcopy    | 31.5% | 1.00 | 1.31 | 1.31x |
| count_loop |  1.6% | 1.00 | 1.02 | 1.02x |

## Report and video

- Report PDF: [report/main.pdf](report/main.pdf) (draft; names still to be filled in)
- Demo video: [Google Drive Link](https://drive.google.com/drive/folders/1SoN0jAJ3BcboLqRUhE7eCVd88pDHP2RP?usp=sharing)
