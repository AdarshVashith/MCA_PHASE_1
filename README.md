# Project 9: Instruction and Data Memory Hierarchy

**Modern Computer Architecture, Phase I + Phase II.** A Harvard-style memory organisation in
Verilog, driven by a small single-cycle RV32I-subset processor and compared against a
shared-memory (von Neumann) baseline. In Phase II both are extended into a realistic memory
hierarchy: split I/D caches over one shared, slow memory (modified Harvard) versus a single
unified cache of the same size.

- **Phase I (ideal memories).** With separate memories, the processor fetches the next
  instruction and performs a load or store in the **same clock cycle**, so CPI = 1.00. With one
  shared port, each load or store costs an extra cycle (CPI = 1 + load/store fraction).
- **Phase II (memory hierarchy).** Behind level-1 caches, both organisations share one memory
  with a latency of L cycles. At L = 4, split caches reach a geometric-mean CPI of **1.47**,
  a unified cache of the same capacity **2.03**, and no cache **4.74**, over eight programs and
  104 configurations, all checked against an independent golden model.

## Team

| Member | Name / GitHub | Role | Phase I | Phase II |
|---|---|---|---|---|
| Member 1 | Kanishk (`@kanishksharma04`) | Memory subsystem | `rtl/mem/` | `rtl/hier/cache.v`, `rtl/hier/main_mem.v`, `tb/tb_cache.v` |
| Member 2 | Adarsh (`@AdarshVashith`) | Processor and integration | `rtl/core/`, `rtl/harvard_top.v` | ISA extension, core stall support, `rtl/hier/mh_top.v` |
| Member 3 | Deepanshu (`@deepanshu-sharma425`) | Baseline, metrics, synthesis | `rtl/common/`, `rtl/baseline/` | `mem_arbiter.v`, `event_counter.v`, `vnc_top.v`, `results/synth/` |
| Member 4 | Daksh (`@emphor11`) | Verification and programs | `tb/`, `programs/`, `tools/`, `sim/` | `tools/iss.py`, `tools/sweep.py`, `tb/tb_hier.v`, new programs |
| Member 5 | Ram (`@Adrenox20`) | Report and repository lead | `report/`, `video/` | final report, figures, `README.md`, `docs/` |

## Block diagrams

```
  Phase I: Harvard (harvard_top)                  Phase I: Baseline (vn_top)

  +-----------+  i_addr  +-----------+            +-------------+  m_addr  +------------+
  |           |--------->| instr_mem |            |             |--------->|            |
  | cpu_core  |<---------|  (ROM)    |            | cpu_core_vn |<---------| shared_mem |
  | (single   |  i_rdata +-----------+            | FETCH_EXEC/ | m_rdata  | code 0-255 |
  |  cycle)   |  d_addr  +-----------+            |  MEM FSM    |--------->| data 256-  |
  |           |--------->| decoder + |--> out     +-------------+          |       511  |
  |           |<---------| data_mem  |              one port: fetch OR data +------------+
  +-----------+  d_rdata +-----------+

  Phase II: Modified Harvard (mh_top)             Phase II: Unified cache (vnc_top)

  +----------+     +---------+                    +-------------+   +-----------+
  |          |---->| I-cache |--+  +---------+    | cpu_core_vn |-->| unified   |   +----------+
  | cpu_core |<----+---------+  +->| arbiter |    | + stall     |<--| cache     |-->| main_mem |
  | + stall  |     +---------+  +->| I first |->  +-------------+   | + wbuf    |<--| latency L|
  |          |---->| D-cache |--+  +---------+                      +-----------+   +----------+
  |          |<----| + wbuf  |        |    +----------+
  +----------+     +---------+        +--->| main_mem | code + data, latency L
                                           +----------+
```

Detailed figures (block diagrams, datapath, FSM, waveforms, plots) are in the report, `report/main.pdf`.

## Memory map (data side, identical on all designs)

| Byte address | Region |
|---|---|
| `0x000`-`0x3FF` | Data RAM, 256 words |
| `0x400` | `out_port` register (write-only, reads 0, never cached) |
| anything else | invalid: write ignored, read returns 0, `d_fault` = 1 |

Instructions live in a separate 256-word ROM (Harvard) or in words 0-255 of a shared memory
(all other designs, where data occupies words 256-511, i.e. physical byte address `0x400`+).

## Instruction set (25 RV32I instructions)

| Phase | Instructions |
|---|---|
| I  | `add sub and or addi lw sw beq bne ebreak` |
| II | `xor slt sll srl andi ori xori slti slli srli blt bge jal jalr lui` |

The assembler also accepts the pseudo-ops `nop`, `li`, `mv`, `j` and `ret`.

## Phase II cache design

- Direct-mapped, 4-word lines, size set by parameter (1 to 32 lines tested).
- Write-through, no-write-allocate, optional one-entry write buffer.
- Read miss: the line is fetched from memory in one transfer; the access completes on the next
  cycle as a hit, so **miss penalty = L cycles**. No refill forwarding (it would create a
  combinational loop through the shared memory).
- `main_mem`: 512 words, request/ready handshake, `ready` in the L-th cycle (L = 1 = ideal).
- `mem_arbiter`: I-cache first, no pre-emption, counts conflict cycles.
- Both cores take a stall input and hold all state while it is low.

## Running the simulation

Requirements: Icarus Verilog (`iverilog`, `vvp`), Python 3, and a waveform viewer: GTKWave, or
[Surfer](https://surfer-project.org/) on macOS (`brew install surfer`).

```sh
cd sim
make asm       # assemble programs/*.s -> *.hex (and run the assembler self-test)
make unit      # unit tests: addr_decoder, instr_mem, data_mem, harvard_mem, cache
make harvard   # every program on the Harvard system
make vn        # every program on the shared-memory baseline
make compare   # Phase I: both designs side by side, prints the comparison table
make hier      # Phase II: every program on H, MH, UC and NC at once (L=4, 8+8 lines)
make hier L=16 LINES=2 WBUF=0      # ... or any other configuration
make sweep     # Phase II: 104 configurations, cross-checked against the ISS (~3 s)
make iss       # golden model (tools/iss.py) on every program
make all       # asm + unit + harvard + vn + compare + hier
make waves PROG=memcopy   # open the Phase I comparison waveform
make figure figure-hier   # regenerate the report's waveform figures from simulation
```

Every testbench is self-checking and ends with `PASS` or `FAIL (n errors)`. Logs are written to
`results/logs/`; the sweep writes `results/hier/sweep.csv`, `results/hier/summary.md` and the
plot data in `report/data/`.

The report compiles with pdfLaTeX + BibTeX (Overleaf, TeX Live, MiKTeX), or locally with
`cd report && tectonic main.tex`. All figures are TikZ/pgfplots sources in `report/figures/`.

## Verification

1. **Assembler self-test**: 29 encodings against hand-worked and reference values.
2. **Golden model**: `tools/iss.py` executes the same images and predicts final state,
   instruction and load/store counts, and the misses of split and unified caches.
3. **Unit tests**: decoder, memories, `harvard_mem`, and `tb_cache` (miss timing, hits, write
   buffer, no-write-allocate, conflict eviction, uncached mode).
4. **System tests**: `tb_compare` (H vs VN, VN cycles = H cycles + loads/stores) and `tb_hier`
   (H, MH, UC, NC on one program: identical registers, memory and output; every cycle accounted
   for; NC with L = 1 equal to Phase I VN cycle for cycle).
5. **Sweep**: 104 configurations, every RTL miss count equal to the ISS prediction.

## Repository layout

```
rtl/mem/        instr_mem, data_mem, addr_decoder, rw_ctrl, harvard_mem         (Phase I)
rtl/core/       pc_reg, regfile, alu, imm_gen, control, cpu_core
rtl/harvard_top.v
rtl/common/     perf_counters, event_counter
rtl/baseline/   shared_mem, cpu_core_vn, vn_top
rtl/hier/       cache, main_mem, mem_arbiter, mh_top, vnc_top                   (Phase II)
tb/             unit, system, comparison and hierarchy testbenches
programs/       8 programs (.s, .hex, _data.hex)
tools/          asm.py (assembler), iss.py (golden model), sweep.py, synth_table.py,
                vcd2tikz.py / vcd2tikz_hier.py (waveform figures)
sim/Makefile    build and run targets
results/        comparison.md, hier/ (Phase II sweep), synth/ (Yosys), logs/
report/         IEEE-format final report (LaTeX, TikZ/pgfplots figures, PDF)
docs/           Phase II work split and interview preparation
video/          Phase I video script and link
```

## Results

### Phase I: ideal memories (`make compare`)

| Program | LW/SW % | Harvard CPI | Baseline CPI | Speed-up |
|---|---|---|---|---|
| basic       | 36.8% | 1.00 | 1.37 | 1.37x |
| array_sum   | 26.3% | 1.00 | 1.26 | 1.26x |
| memcopy     | 31.5% | 1.00 | 1.31 | 1.31x |
| count_loop  |  1.6% | 1.00 | 1.02 | 1.02x |
| isa_test    | 13.2% | 1.00 | 1.13 | 1.13x |
| bubble_sort | 44.7% | 1.00 | 1.45 | 1.45x |
| func_call   |  4.1% | 1.00 | 1.04 | 1.04x |
| transpose   | 17.9% | 1.00 | 1.18 | 1.18x |

### Phase II: memory hierarchy (`make sweep`, geometric-mean CPI over 8 programs)

| Memory latency L | Ideal Harvard | Ideal shared | Split caches 8+8 | Unified cache 16 | No cache |
|---|---|---|---|---|---|
| 1  | 1.00 | 1.21 | 1.11 | 1.42 | 1.21 |
| 4  | 1.00 | 1.21 | 1.47 | 2.03 | 4.74 |
| 16 | 1.00 | 1.21 | 3.03 | 4.45 | 18.83 |

Split caches beat the unified cache because they keep two ports and because code (at `0x000`)
and data (at `0x400`) map to the same lines of a direct-mapped unified cache (e.g. `bubble_sort`:
10 misses split vs 252 unified). The write buffer is worth up to 1.41x. Full tables:
[results/hier/summary.md](results/hier/summary.md); area: [results/comparison.md](results/comparison.md).

## Report and video

- Final report (Phase II): [report/main.pdf](report/main.pdf)
- Phase I video demonstration: [Google Drive](https://drive.google.com/drive/folders/1SoN0jAJ3BcboLqRUhE7eCVd88pDHP2RP?usp=sharing)
