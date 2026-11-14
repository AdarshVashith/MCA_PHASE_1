# Project 9 – Phase I Team Workflow and IDE Prompts

**Instruction and Data Memory Hierarchy (Harvard vs shared memory)** · Modern Computer Architecture · Deadline: Monday 16 November 2026, 11:59 PM IST

## 1. How to use this document

1. **Tonight (Fri 13 Nov):** Member 5 creates the GitHub repo, adds the master prompt as `AGENTS.md` in the repo root, and invites the other four. Everyone clones and creates their own branch.
2. **Every IDE session:** make sure the master prompt is loaded first. Cursor, Copilot agent mode, Claude Code, Windsurf and similar tools read `AGENTS.md` from the repo root automatically; if yours does not, paste the whole file as the first message.
3. **Then paste your own member prompt** from section 4. Each prompt is written to be pasted as-is.
4. Follow your workflow steps, commit after each step from your own GitHub account, and open a pull request when your part compiles.

Three things to keep in mind:

- **The interfaces in the master prompt are the contract.** If one person changes a port name, nothing integrates on Sunday. Raise changes in the group chat and update `AGENTS.md` in one commit that everyone pulls.
- **Commit history is graded.** Each member commits their own work from their own account, in small steps. One giant commit on Monday night, or one person pushing everything, will cost marks.
- **You have to explain your part in the video and the demo.** Ask the IDE to explain anything you could not explain yourself, and check your course's policy on AI tool use and whether it must be acknowledged in the report.

Assumed toolchain: Icarus Verilog and GTKWave for simulation (free, works on every OS), with Vivado or Yosys for the optional synthesis numbers. If your lab uses ModelSim or Vivado's simulator, the RTL is unchanged; only Member 4's Makefile differs.

## 2. Design in one page

A small single-cycle processor (RV32I subset: ADD, SUB, AND, OR, ADDI, LW, SW, BEQ, BNE, EBREAK) is connected to two memory organisations:

| | Harvard (the project) | Shared memory (the baseline) |
|---|---|---|
| Memories | Separate instruction ROM and data RAM | One 512-word memory holding code and data |
| Ports | Two: fetch and data access in the same cycle | One: fetch and data access take turns |
| Cycles per instruction | 1 for everything | 1 for ALU and branches, 2 for LW and SW |
| Expected CPI | 1.0 | 1 + (fraction of load/store instructions) |

The same program hex file runs on both. The testbench checks that both finish with identical registers and data memory, then prints cycles, CPI and the number of simultaneous fetch-plus-data cycles. That table is the quantitative result for the report and the video.

## 3. Master prompt (save as `AGENTS.md` in the repo root)

`````markdown
# Project context (read this before doing anything)

You are helping one member of a 5-person B.Tech team build **Project 9: Instruction and Data Memory Hierarchy** for a Modern Computer Architecture course. The team is implementing a simplified Harvard-style memory organisation in Verilog (separate instruction and data memories), driving it with a tiny single-cycle RV32I-subset processor, and comparing it against a shared-memory (Von Neumann) baseline. Phase I is graded on an IEEE-format report, a 5-minute prototype video, and a GitHub repository whose commit history shows each member's contribution.

Five people are working in parallel in separate branches, each with their own AI-assisted IDE session. Their code only integrates if everyone follows the same contract, so **the interfaces, names, and memory map below are fixed**. If something in this spec looks wrong or blocks you, stop and tell the user so they can raise it with the team; do not quietly change a port name, width, or address. Inside your own modules you are free to choose the implementation.

The person you are working with has to explain this code in a live demo and will be assessed on it. Keep the code small and readable, comment the non-obvious parts, and when you finish a piece, explain in plain words how it works.

## What the project must show

1. Independent instruction and data paths (Harvard): an instruction fetch and a data access happen in the same clock cycle.
2. Address decoding and read/write control on the data side.
3. Programs running that mix instruction fetches with data accesses.
4. A measured comparison against a shared-memory organisation where fetch and data access compete for one memory port.

Headline metric: **cycles and CPI for the same program on both designs**, plus the number of cycles in which Harvard performs a fetch and a data access simultaneously.

## Coding rules

- Verilog-2001 only (no SystemVerilog), synthesizable RTL in `rtl/`, testbench-only constructs in `tb/`.
- Every file starts with `` `default_nettype none `` and ends with `` `default_nettype wire ``.
- One module per file, file name = module name.
- Single clock `clk`, rising edge. Reset `rst` is synchronous and active high.
- Non-blocking assignments in clocked blocks, blocking in combinational blocks, no latches.
- 32-bit data and addresses. Addresses are byte addresses; memories are word-addressed internally using `addr[N:2]`. Only aligned word accesses are supported.
- Simulator: Icarus Verilog (`iverilog -g2005`) with GTKWave. Keep code portable so it also runs in Vivado or ModelSim.

## Repository layout

```
README.md
AGENTS.md                 this file
docs/                     workflow doc, diagrams
rtl/mem/                  instr_mem.v data_mem.v addr_decoder.v rw_ctrl.v harvard_mem.v      (Member 1)
rtl/core/                 pc_reg.v regfile.v alu.v imm_gen.v control.v cpu_core.v           (Member 2)
rtl/harvard_top.v                                                                           (Member 2)
rtl/common/perf_counters.v                                                                  (Member 3)
rtl/baseline/             shared_mem.v cpu_core_vn.v vn_top.v                               (Member 3)
tb/                       all testbenches                                                   (Member 4)
programs/                 *.s assembly, *.hex machine code, *_data.hex data images          (Member 4)
tools/asm.py              tiny assembler for the subset                                     (Member 4)
sim/Makefile              build and run targets                                             (Member 4)
results/                  logs, waveform screenshots, comparison table                      (Members 3, 4)
report/                   IEEEtran LaTeX source, figures, PDF                               (Member 5)
video/                    script.md and the video link                                      (Member 5)
```

Only edit files in the folders owned by the member you are helping. If a change is needed elsewhere, describe it so the user can ask the owner.

## Instruction subset (RV32I encodings)

| Instr | Opcode | funct3 | funct7 | Operation |
|---|---|---|---|---|
| ADD | 0110011 | 000 | 0000000 | rd = rs1 + rs2 |
| SUB | 0110011 | 000 | 0100000 | rd = rs1 - rs2 |
| AND | 0110011 | 111 | 0000000 | rd = rs1 & rs2 |
| OR | 0110011 | 110 | 0000000 | rd = rs1 \| rs2 |
| ADDI | 0010011 | 000 | - | rd = rs1 + imm |
| LW | 0000011 | 010 | - | rd = MEM[rs1 + imm] |
| SW | 0100011 | 010 | - | MEM[rs1 + imm] = rs2 |
| BEQ | 1100011 | 000 | - | if rs1 == rs2, PC += imm |
| BNE | 1100011 | 001 | - | if rs1 != rs2, PC += imm |
| EBREAK | `32'h00100073` | | | halt: PC stops, `halt` goes high and stays high |

Register x0 always reads zero. PC resets to 0. Any other encoding is treated as a NOP.

## Memory map

Instruction address space (Harvard): 256 words, byte addresses `0x000`–`0x3FF`, read-only, loaded from a hex file.

Data address space (what programs see, identical on both designs):

| Byte address | Region |
|---|---|
| `0x0000_0000`–`0x0000_03FF` | Data RAM, 256 words |
| `0x0000_0400` | `out_port` register, write-only, reads as 0 |
| anything else | invalid: write ignored, read returns 0, `d_fault` = 1 |

Shared-memory baseline: one 512-word memory. Code occupies physical words 0–255, data occupies physical words 256–511. `vn_top` adds `0x400` to data-space RAM addresses, so **the same program and data hex files run unmodified on both designs**. `out_port` decoding happens before that translation.

## Module interfaces (fixed)

```verilog
// ---------- Member 1: rtl/mem ----------
module instr_mem #(parameter DEPTH_WORDS = 256, parameter INIT_FILE = "")
  (input  wire [31:0] addr, output wire [31:0] rdata);          // combinational read, array name: mem

module data_mem #(parameter DEPTH_WORDS = 256, parameter INIT_FILE = "")
  (input  wire clk, input wire we,
   input  wire [31:0] addr, input wire [31:0] wdata,
   output wire [31:0] rdata);                                    // sync write, combinational read, array name: mem

module addr_decoder
  (input  wire [31:0] addr,
   output wire sel_ram, output wire sel_io, output wire addr_fault);

module rw_ctrl
  (input  wire d_we, input wire d_re, input wire sel_ram, input wire sel_io,
   input  wire [31:0] ram_rdata,
   output wire ram_we, output wire io_we, output wire [31:0] d_rdata);

module harvard_mem #(parameter PROG_FILE = "", parameter DATA_FILE = "")
  (input  wire clk, input wire rst,
   input  wire [31:0] i_addr,  output wire [31:0] i_rdata,       // instruction port
   input  wire [31:0] d_addr,  input  wire [31:0] d_wdata,       // data port
   input  wire d_we, input wire d_re,
   output wire [31:0] d_rdata, output wire d_fault,
   output reg  [31:0] out_port);
   // instances: u_imem (instr_mem), u_dmem (data_mem), u_dec (addr_decoder), u_rw (rw_ctrl)

// ---------- Member 2: rtl/core ----------
module regfile (input wire clk, input wire we,
   input wire [4:0] ra1, input wire [4:0] ra2, input wire [4:0] wa, input wire [31:0] wd,
   output wire [31:0] rd1, output wire [31:0] rd2);              // array name: regs, x0 reads 0

module alu (input wire [31:0] a, input wire [31:0] b, input wire [2:0] op,
   output reg [31:0] y, output wire zero);                       // op: 000 ADD, 001 SUB, 010 AND, 011 OR

module imm_gen (input wire [31:0] instr, output reg [31:0] imm);

module control (input wire [31:0] instr,
   output reg reg_we, output reg alu_src, output reg [2:0] alu_op,
   output reg mem_re, output reg mem_we, output reg mem_to_reg,
   output reg is_beq, output reg is_bne, output reg is_halt);

module cpu_core
  (input  wire clk, input wire rst,
   output wire [31:0] i_addr, input  wire [31:0] i_rdata,
   output wire [31:0] d_addr, output wire [31:0] d_wdata,
   output wire d_we, output wire d_re, input wire [31:0] d_rdata,
   output wire halt, output wire instr_done);
   // single cycle; instr_done = 1 in every cycle an instruction retires; instance: u_regfile

module harvard_top #(parameter PROG_FILE = "", parameter DATA_FILE = "")
  (input  wire clk, input wire rst,
   output wire halt, output wire [31:0] out_port,
   output wire [31:0] cycle_count, output wire [31:0] instr_count,
   output wire [31:0] d_access_count, output wire [31:0] simul_count);
   // instances: u_core (cpu_core), u_mem (harvard_mem), u_perf (perf_counters)

// ---------- Member 3: rtl/common, rtl/baseline ----------
module perf_counters
  (input  wire clk, input wire rst, input wire halt,
   input  wire instr_done, input wire i_access, input wire d_access,
   output reg [31:0] cycle_count, output reg [31:0] instr_count,
   output reg [31:0] d_access_count, output reg [31:0] simul_count);
   // all counters freeze once halt is high; simul_count counts cycles with i_access && d_access

module shared_mem #(parameter DEPTH_WORDS = 512, parameter PROG_FILE = "", parameter DATA_FILE = "")
  (input  wire clk, input wire we,
   input  wire [31:0] addr, input wire [31:0] wdata,
   output wire [31:0] rdata);                                    // ONE port; program at word 0, data at word 256

module cpu_core_vn
  (input  wire clk, input wire rst,
   output wire [31:0] m_addr, output wire [31:0] m_wdata,
   output wire m_we, output wire m_re, output wire m_is_data,    // m_is_data = 1 when the access is a data access
   input  wire [31:0] m_rdata,
   output wire halt, output wire instr_done);
   // reuses regfile, alu, imm_gen, control; instance: u_regfile

module vn_top #(parameter PROG_FILE = "", parameter DATA_FILE = "")
  ( /* exactly the same port list as harvard_top */ );
   // instances: u_core (cpu_core_vn), u_mem (shared_mem), u_perf (perf_counters)
```

Testbenches read state through these hierarchical names, so keep them: `dut.u_core.u_regfile.regs[n]`, `dut.u_mem.u_dmem.mem[n]` (Harvard), `dut.u_mem.mem[256 + n]` (baseline).

## Expected timing behaviour

- **Harvard:** every instruction takes 1 cycle, including LW and SW, because fetch and data access use different memories. CPI = 1.0.
- **Baseline:** one memory port, so a fetch and a data access cannot share a cycle. Non-memory instructions take 1 cycle (fetch and execute), LW and SW take 2 (fetch, then data access). CPI = 1 + (fraction of LW/SW instructions).
- Cross-check used by the testbench: baseline cycles should equal Harvard cycles plus Harvard `d_access_count`, and final register and data-memory contents must be identical on both designs.

## Git rules

Graders read the commit history to judge individual contribution.

- Work on your own branch (`m1-memory`, `m2-core`, `m3-baseline`, `m4-verification`, `m5-report`) and merge to `main` through pull requests.
- Commit from your own GitHub account, in small steps, one logical change per commit, with messages like `mem: add addr_decoder with fault flag`.
- Never commit simulator output (`*.vcd`, `*.vvp`, `sim/build/`). Do commit logs and screenshots placed in `results/`.
- Do not write commit messages for the user that claim work they did not do, and do not commit on behalf of another member.

## How to work with the user

- Before writing code, restate in 3–4 lines what you are about to build and which files you will create.
- Build one module at a time, compile it with `iverilog` straight away, and fix warnings before moving on.
- After each module, give a short plain-language explanation the user could repeat in a viva, and suggest the commit message.
- When you report results, report what the simulation actually printed. If something fails or is not yet tested, say so.
`````

## 4. Team split

| Member | Role | Owns | Depends on |
|---|---|---|---|
| 1 | Harvard memory core | `rtl/mem/` | nothing |
| 2 | Processor and top-level integration | `rtl/core/`, `rtl/harvard_top.v` | M1 `harvard_mem`, M3 `perf_counters` (at integration) |
| 3 | Shared-memory baseline and metrics | `rtl/common/`, `rtl/baseline/`, comparison table | M2 `regfile`, `alu`, `imm_gen`, `control` |
| 4 | Verification and programs | `tb/`, `programs/`, `tools/`, `sim/` | spec only at first, everyone's RTL by Sunday |
| 5 | Report, video, repository | `report/`, `video/`, `README.md`, `docs/` | diagrams and results from everyone |

Replace the numbers with names before sharing. Give Members 2 and 3 to whoever is most comfortable with Verilog; Member 5 suits whoever writes best.

---

### Member 1 – Harvard memory core

**What you are building:** the heart of the project: instruction memory, data memory, the address decoder, read/write control, and the `harvard_mem` wrapper that ties them together.

**Workflow**

1. Create branch `m1-memory`.
2. Build `instr_mem` and `data_mem`, compile each, commit each.
3. Build `addr_decoder` and `rw_ctrl`, commit.
4. Build `harvard_mem`, write a quick throwaway test that fetches an instruction and writes data in the same cycle, and save a waveform screenshot to `results/`.
5. Open a pull request by **Saturday evening** so Member 2 can integrate.
6. Draw the memory-subsystem block diagram (draw.io or by hand, exported as PNG) and give it to Member 5, along with a 150-word description of your modules for the report.
7. Video: you narrate the memory architecture segment (about 45 seconds).

**Prompt to paste**

```text
I am Member 1. I own rtl/mem/ and I am building the Harvard memory core defined in AGENTS.md: instr_mem, data_mem, addr_decoder, rw_ctrl and the harvard_mem wrapper. Use the exact port lists, parameter names, instance names and memory map from AGENTS.md.

Build them in this order, one file at a time, compiling each with iverilog before moving on:

1. instr_mem: read-only, combinational read, loaded with $readmemh when INIT_FILE is not empty. Word index is addr[9:2].
2. data_mem: synchronous write, combinational read, optional $readmemh initialisation, otherwise initialised to zero in an initial block.
3. addr_decoder: purely combinational, implements the data memory map (RAM, out_port at 0x400, fault for everything else).
4. rw_ctrl: turns the processor's d_we/d_re plus the decoder selects into ram_we and io_we, and chooses what d_rdata returns (RAM data, or zero for out_port and invalid addresses).
5. harvard_mem: instantiates the four modules, holds the out_port register (cleared on rst, written when io_we is high), and drives d_fault only when an access is actually being made.

The point this module has to demonstrate is that the instruction port and the data port are fully independent, so a fetch and a data read or write happen in the same clock cycle. After harvard_mem compiles, write a small scratch testbench in sim/scratch/ (not in tb/, which belongs to Member 4) that: reads two instructions from a small hex file, writes then reads back a data word in the same cycles as those fetches, writes to out_port, and attempts one access to an invalid address. Dump a VCD and tell me which signals to add in GTKWave to show the simultaneous access clearly.

Keep each module short and commented. After each one, explain it to me in a few sentences as I would say it in a viva, and suggest a commit message. At the end, give me a text description of the block diagram (boxes and arrows) so I can draw it for the report.
```

---

### Member 2 – Processor and top-level integration

**What you are building:** the small single-cycle processor that exercises the memories, and `harvard_top`, the complete Harvard system.

**Workflow**

1. Create branch `m2-core`.
2. Build `regfile`, `alu`, `imm_gen`, `control`, committing each. **Push these four by Saturday afternoon** since Member 3 reuses them.
3. Build `pc_reg` and `cpu_core`.
4. When Member 1's pull request is merged, build `harvard_top` and run a five-instruction smoke program.
5. Add Member 3's `perf_counters` to `harvard_top` once it is merged (until then, tie the counter outputs to zero and mark it with a TODO).
6. Hand Member 5 the datapath diagram and a 150-word description of the processor.
7. Video: you narrate the datapath and how one LW instruction uses both memories in a single cycle (about 45 seconds).

**Prompt to paste**

```text
I am Member 2. I own rtl/core/ and rtl/harvard_top.v. I am building the single-cycle RV32I-subset processor and the Harvard top level defined in AGENTS.md. Use the exact port lists, ALU op codes, instruction encodings and instance names from AGENTS.md.

Build in this order, one file at a time, compiling each with iverilog:

1. regfile: 32 x 32-bit, two combinational read ports, one synchronous write port, x0 hard-wired to zero, array named regs, initialised to zero for simulation.
2. alu: ADD, SUB, AND, OR with a zero flag.
3. imm_gen: sign-extended I, S and B immediates selected from the opcode.
4. control: decodes the ten instructions in AGENTS.md into the listed control signals; unknown encodings behave as a NOP.
5. pc_reg and cpu_core: PC resets to 0, advances by 4, takes the branch target on a taken BEQ or BNE, and freezes once EBREAK is decoded. halt is high from the EBREAK cycle onward; instr_done is high in every cycle that retires an instruction (count EBREAK itself as retired once). The core must not contain any memory: it only talks to the i_* and d_* ports.
6. harvard_top: connects cpu_core to Member 1's harvard_mem and Member 3's perf_counters, with i_access = !halt and d_access = d_we | d_re. If those modules are not in the repo yet, write the instantiation against the AGENTS.md port lists and tell me exactly what is still missing rather than creating stand-in versions in other members' folders.

Other members reuse regfile, alu, imm_gen and control in the shared-memory baseline, so keep those four free of anything specific to the single-cycle core.

For a smoke test, put a scratch testbench in sim/scratch/ that runs this program and checks the results: addi x1,x0,5; addi x2,x0,7; add x3,x1,x2; sw x3,0(x0); lw x4,0(x0); ebreak. Expect x3 = x4 = 12 and data word 0 = 12 after six cycles. Hand-assemble it and show me the hex with the field breakdown so I can verify one encoding myself.

After each module, explain it in a few sentences as I would say it in a viva, and suggest a commit message. At the end, describe the datapath diagram (blocks and connections) so I can draw it, and walk me through what every signal does during the LW instruction.
```

---

### Member 3 – Shared-memory baseline and metrics

**What you are building:** the comparison half of the project: performance counters used by both designs, a Von Neumann style system with one shared memory, and the results table.

**Workflow**

1. Create branch `m3-baseline`.
2. Build `perf_counters` first and open a small pull request for it straight away, since Member 2 needs it.
3. Build `shared_mem`.
4. Once Member 2's four reusable modules are pushed, build `cpu_core_vn` (two-state FSM) and `vn_top`.
5. On Sunday, with Member 4, run every program on both designs and fill in `results/comparison.md`.
6. Optional but worth marks under the common requirements: synthesize both tops in Vivado (or Yosys) and record LUTs, flip-flops and maximum frequency.
7. Give Member 5 the FSM state diagram, the results table and a 150-word analysis.
8. Video: you present the comparison table (about 50 seconds).

**Prompt to paste**

```text
I am Member 3. I own rtl/common/ and rtl/baseline/. I am building the performance counters and the shared-memory (Von Neumann) baseline defined in AGENTS.md, and producing the Harvard vs shared-memory comparison. Use the exact port lists, instance names and memory map from AGENTS.md.

Build in this order, compiling each file with iverilog:

1. perf_counters: four 32-bit counters as specified, cleared on rst, frozen once halt is high.
2. shared_mem: a single-port 512-word memory, combinational read, synchronous write. PROG_FILE loads at word 0 and DATA_FILE loads at word 256 using the start-address form of $readmemh.
3. cpu_core_vn: the same instruction behaviour as the single-cycle core, but with only one memory bus. Use a two-state FSM. In FETCH_EXEC the bus carries the PC; ALU, branch and EBREAK instructions complete in that cycle. For LW and SW, latch the instruction and the values needed, move to MEM, and in that second cycle put the data address on the bus (m_is_data = 1), do the read or write, then advance the PC. Reuse Member 2's regfile, alu, imm_gen and control from rtl/core/ without modifying them. instr_done pulses once per retired instruction.
4. vn_top: same port list as harvard_top. It reuses Member 1's addr_decoder on data accesses so out_port and invalid addresses behave identically to the Harvard design, and adds 0x400 to data-space RAM addresses so the same hex files run unmodified. i_access is high in FETCH_EXEC cycles and d_access in MEM cycles, so simul_count stays at zero by construction, which is exactly the point of the comparison.

If rtl/core/ or rtl/mem/addr_decoder.v is not in the repo yet, write against the AGENTS.md interfaces and tell me what is missing; do not create copies of other members' modules.

The claim this baseline has to support: with one memory port, every load or store costs an extra cycle, so baseline cycles = Harvard cycles + number of data accesses. Explain to me why that follows from the FSM, and what would change if the shared memory had synchronous read instead.

Then create results/comparison.md with a table template: program, instructions, load/store fraction, Harvard cycles, Harvard CPI, baseline cycles, baseline CPI, speed-up, simultaneous-access cycles. Leave the cells empty; I will fill them from Member 4's simulation logs, and I do not want estimated numbers in it. Also give me a short Vivado (and alternatively Yosys) command sequence to synthesize harvard_top and vn_top and where to read LUT, flip-flop and timing figures.

After each module, explain it as I would say it in a viva, describe the FSM state diagram so I can draw it, and suggest commit messages.
```

---

### Member 4 – Verification and programs

**What you are building:** everything that proves the design works: a tiny assembler, test programs, self-checking testbenches, the Makefile, and the waveforms shown in the video.

**Workflow**

1. Create branch `m4-verification`.
2. Saturday morning, before any RTL exists: write `tools/asm.py`, the four test programs, and the unit testbenches for Member 1's modules straight from the spec.
3. As pull requests land, run the unit testbenches and report failures to the owner as GitHub issues (this also shows up as contribution).
4. Sunday: `tb_harvard_top`, `tb_vn_top`, `tb_compare`; save logs to `results/logs/` and waveform screenshots to `results/waves/`.
5. Give Member 3 the numbers and Member 5 the screenshots plus a 150-word verification description.
6. Video: you run `make compare` live on screen and show the simultaneous-access waveform (about 60 seconds).

**Prompt to paste**

```text
I am Member 4. I own tb/, programs/, tools/ and sim/. I am responsible for verifying the design defined in AGENTS.md. Other members are writing the RTL in parallel, so some of it may not exist yet: write testbenches against the AGENTS.md interfaces and hierarchical names, and tell me which ones cannot run yet rather than creating stand-in RTL.

Build in this order:

1. tools/asm.py: a small Python 3 assembler (standard library only) for the ten instructions in AGENTS.md, supporting labels, comments, x0-x31 register names and the offset(reg) syntax. It outputs one 32-bit hex word per line for $readmemh. Include a self-test that assembles a few instructions and compares against encodings worked out by hand in comments, because a wrong assembler would silently invalidate every other test.

2. programs/, each as a .s file plus generated .hex and, where needed, a _data.hex initial data image. Each program ends with EBREAK and writes its final answer to out_port (address 0x400):
   - basic.s: uses every instruction at least once with easily predictable results.
   - array_sum.s: sums an 8-element array from data memory (memory-heavy loop).
   - memcopy.s: copies 8 words from one region to another (load and store every iteration).
   - count_loop.s: counts down in registers with almost no memory access (compute-heavy).
   The last three are chosen to give different load/store fractions so the Harvard vs shared-memory comparison shows a trend.

3. Unit testbenches: tb_instr_mem, tb_data_mem, tb_addr_decoder (including both edges of each region and an invalid address), tb_harvard_mem (must include a case where a fetch and a data write happen in the same cycle and both are checked).

4. System testbenches: tb_harvard_top and tb_vn_top take the program name as a plusarg or parameter, run until halt with a timeout, check out_port, selected registers and data words against expected values, and print the counters.

5. tb_compare: instantiates harvard_top and vn_top side by side on the same program, waits for both to halt, then checks that all 32 registers and all 256 data words match between them, that the Harvard cycle count equals its instruction count, and that baseline cycles equal Harvard cycles plus Harvard d_access_count. It prints one line per program in a fixed format that can be pasted into results/comparison.md, with CPI to two decimals.

6. sim/Makefile with targets: asm, unit, harvard, vn, compare, waves (opens GTKWave), clean. Build products go to sim/build/, which is git-ignored.

Every testbench is self-checking: it counts errors, prints PASS or FAIL with the count at the end, and dumps a VCD. No testbench should rely on me reading waveforms to decide whether it passed.

When tests fail, show me the actual failing output and help me work out whether the bug is in the testbench, the program or the RTL. If it is in someone else's RTL, draft a short GitHub issue for the owner instead of patching their file.

Finally, give me a GTKWave signal list and save file for the one waveform that best shows the project idea: an LW or SW on harvard_top where i_addr and d_addr are both active in the same cycle, next to the same instruction on vn_top taking two cycles.
```

---

### Member 5 – IEEE report, video and repository

**What you are building:** the three things that are actually marked: the IEEE report (10), the video (15) and the repository (5). You also coordinate.

**Workflow**

1. **Tonight:** create the repo (public or shared with the evaluators), add `AGENTS.md`, `.gitignore`, the folder skeleton and a first `README.md`; invite all four members as collaborators; create branch `m5-report` for your own work.
2. Saturday: IEEEtran skeleton in `report/`, then draft the Introduction and Literature Review. Find and verify the references yourself (see the prompt).
3. Sunday: collect diagrams, the 150-word descriptions and the results table from Members 1–4; write Proposed Solution; fill in the Individual Contributions table from what each person actually committed.
4. Sunday evening: finalise `video/script.md` and send each member their lines and time slot.
5. Monday: each member records their own segment (screen capture plus voice); you stitch, keep it under 5:00, upload (unlisted YouTube or Drive with link access), and put the link in `README.md` and `video/`.
6. Monday by 8 PM: final PDF committed to `report/`, README complete, repo link submitted through the form. Leave the last hours as a buffer.

**Prompt to paste**

```text
I am Member 5. I own report/, video/, docs/ and README.md. I am responsible for the IEEE-format report, the script for the 5-minute prototype video, and keeping the repository in order for the project defined in AGENTS.md. I do not write RTL; when you need technical detail, read the code and results that are actually in the repo rather than guessing.

Task 1, repository setup. Create the folder skeleton from AGENTS.md with a .gitkeep where needed, a .gitignore for Icarus, Vivado, LaTeX and OS files, and a README.md containing: project title and one-paragraph idea, the five member names and roles (I will fill in names), a block-diagram placeholder, how to run the simulation (Member 4's make targets), the repository layout, a results section that links to results/comparison.md, and clearly marked places for the report PDF and the demo video link.

Task 2, report. In report/, set up a LaTeX project using the IEEEtran conference class (main.tex, refs.bib, figures/), two-column, that compiles on Overleaf. The evaluation requires these sections: Abstract, Literature Review, Proposed Solution, Individual Contributions, References. Use this structure:
   - Abstract (150-200 words)
   - I. Introduction: the stored-program concept, why memory organisation matters, what this project builds
   - II. Literature Review: Von Neumann vs Harvard organisation, modified Harvard in modern microcontrollers and in split instruction/data caches, RISC-V as a teaching ISA, related student or FPGA implementations
   - III. Proposed Solution: architecture overview with block diagram, memory map table, module descriptions, the shared-memory baseline, verification approach, preliminary results
   - IV. Individual Contributions: a table of member, role, modules or artefacts, plus one or two sentences each
   - V. Conclusion and Phase II plan
   - References in IEEE style

Write Sections I and II now as full prose. For Section III, write what can be derived from AGENTS.md and the code currently in the repo, and leave clearly marked TODO comments where a figure, a result or a member's description is still to come. Do not fill in results, cycle counts, resource figures or contributions that are not in the repo yet.

References need particular care, because invented citations are easy to produce and easy for an evaluator to catch. Only cite sources you are confident exist, such as the standard textbooks (Patterson and Hennessy, Computer Organization and Design RISC-V Edition; Hennessy and Patterson, Computer Architecture: A Quantitative Approach; Harris and Harris, Digital Design and Computer Architecture RISC-V Edition), von Neumann's First Draft of a Report on the EDVAC, the RISC-V Instruction Set Manual Volume I, and IEEE Std 1364 for Verilog. For anything else, give me search terms for IEEE Xplore and Google Scholar instead of a citation, and mark every bib entry with a comment saying whether I still need to verify it. I will check each one before submission.

Task 3, video script. Write video/script.md for a video of at most 5 minutes; aim for 4:40 of narration so there is margin. It must state the project idea clearly, introduce all five members by name, and show the prototype working. Use this plan and write the narration word for word, with what is on screen beside each part, so that each member speaks about their own work:
   - 0:00-0:30 title, project idea in two sentences, all five names and roles (Member 5)
   - 0:30-1:15 Harvard memory architecture, block diagram and memory map (Member 1)
   - 1:15-2:00 processor datapath, one LW using both memories in a single cycle (Member 2)
   - 2:00-3:00 live run of the simulation and the simultaneous-access waveform (Member 4)
   - 3:00-3:50 shared-memory baseline and the comparison table (Member 3)
   - 3:50-4:40 current status, what remains for Phase II, repository tour (Member 5)
At roughly 140 words per minute, give a word budget per segment and keep to it.

Task 4, final check. When I ask for it, go through the repo against this checklist and report what is missing: report PDF present, video link present and working, all prototype files present, every member has commits on main, README instructions actually work from a clean clone, no build products committed.

Explain your choices briefly as you go, and suggest a commit message after each task.
```

## 5. Timeline

| When | Member 1 | Member 2 | Member 3 | Member 4 | Member 5 |
|---|---|---|---|---|---|
| Fri night | Clone, branch | Clone, branch | Clone, branch | Clone, branch | Create repo, `AGENTS.md`, skeleton, invites |
| Sat morning | `instr_mem`, `data_mem` | `regfile`, `alu`, `imm_gen`, `control` | `perf_counters` (PR), `shared_mem` | Assembler, programs | LaTeX skeleton, Introduction |
| Sat evening | `addr_decoder`, `rw_ctrl`, `harvard_mem` → PR | `cpu_core` → PR | `cpu_core_vn` | Unit testbenches | Literature Review, references |
| Sun morning | Fix issues, diagram | `harvard_top`, smoke test | `vn_top` | System testbenches | README, collect diagrams |
| Sun evening | Report paragraph | Report paragraph | Results table, synthesis | `tb_compare`, logs, screenshots | Proposed Solution, video script |
| Mon | Record segment | Record segment | Record segment | Record segment | Edit video, final PDF, submit by 8 PM |

**Integration checkpoint: Sunday 12 noon.** Everything merged to `main` and `make compare` attempted, even if it fails. Problems found at noon on Sunday are fixable; the same problems found on Monday night are not.

## 6. Submission checklist

- [ ] Report PDF in IEEE format with Abstract, Literature Review, Proposed Solution, Individual Contributions, References
- [ ] Every reference checked by a person
- [ ] Video is 5:00 or shorter, states the idea, names all five members, shows the prototype running
- [ ] Repo contains the report, the video link, all RTL, testbenches, programs and results
- [ ] Each of the five members has their own commits on `main`, spread over the three days
- [ ] `make compare` works from a fresh clone
- [ ] Repo link submitted through the form before 11:59 PM on 16 November
