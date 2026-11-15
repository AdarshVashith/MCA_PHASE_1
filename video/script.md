# Prototype video script (target 4:40, limit 5:00)

**Video Link:** [Google Drive](https://drive.google.com/drive/folders/1SoN0jAJ3BcboLqRUhE7eCVd88pDHP2RP?usp=sharing)

Budget at ~140 words per minute. Each member records their own segment (screen capture + voice).

| Time | Speaker | Words | On screen |
|---|---|---|---|
| 0:00-0:30 | Ram (M5) | ~70 | Title slide, team names |
| 0:30-1:15 | Kanishk (M1) | ~105 | Memory block diagram, memory map |
| 1:15-2:00 | Adarsh (M2) | ~105 | Datapath diagram, LW highlighted |
| 2:00-3:00 | Daksh (M4) | ~140 | Terminal `make compare`, GTKWave |
| 3:00-3:50 | Deepanshu (M3) | ~115 | FSM diagram, results table |
| 3:50-4:40 | Ram (M5) | ~115 | Repo tour on GitHub |

---

## 0:00-0:30 · Introduction (Ram)

*Screen: title slide "Project 9: Instruction and Data Memory Hierarchy", then the five names.*

> Hello, we are Kanishk, Adarsh, Deepanshu, Daksh and Ram,
> and this is Project 9,
> Instruction and Data Memory Hierarchy. A processor needs memory for two things: fetching its
> instructions and reading or writing data. We built a Harvard design that gives each its own
> memory, ran a small RISC-V processor on it, and measured it against a design where both share one
> memory.

## 0:30-1:15 · Harvard memory architecture (Kanishk)

*Screen: memory subsystem block diagram; then the memory map table.*

> The memory subsystem has two completely separate ports. The instruction port goes to a
> read-only instruction memory of 256 words, loaded from a hex file. The data port goes through an
> address decoder. Addresses below 0x400 select the data RAM, address 0x400 selects an output
> register we use to show results, and any other address raises a fault flag: the write is ignored
> and a read returns zero. A small read/write controller turns the processor's read and write
> requests into the right enable signal. Because the two ports share no bus and no memory array, an
> instruction fetch and a data access happen in the same clock cycle.

## 1:15-2:00 · Processor datapath (Adarsh)

*Screen: datapath diagram; highlight the path of one LW.*

> The processor is single-cycle and supports ten RISC-V instructions: add, subtract, and, or, add
> immediate, load word, store word, two branches, and EBREAK to halt. Let's follow one load word.
> At the start of the cycle the program counter goes out on the instruction port and the
> instruction comes back. The control unit decodes it, the register file supplies the base
> register, and the ALU adds the offset to form the data address. In the same cycle that address
> goes out on the data port, the word comes back, and on the clock edge it is written into the
> destination register. Fetch and load, one cycle.

## 2:00-3:00 · Live simulation (Daksh)

*Screen: terminal, run `make compare`; then GTKWave with `make waves PROG=memcopy`.*

> To check all of this we wrote a small assembler and four test programs with different amounts
> of memory traffic. Every testbench checks itself and prints pass or fail. Here I run make
> compare. It runs each program on both designs at the same time, checks that all 32 registers and
> all 256 data words end up identical, and prints the cycle counts. All four pass. Now the
> waveform for the memcopy program. On the Harvard design, look at this cycle: the instruction
> address and the data address are both active, and the store happens while the next instruction
> is being fetched. Below, the shared-memory design runs the same store. The single address bus
> first carries the program counter, then in the next cycle the data address. The same
> instruction takes two cycles.

## 3:00-3:50 · Baseline and comparison (Deepanshu)

*Screen: the two-state FSM diagram, then results/comparison.md.*

> The baseline has one memory port, controlled by a two-state machine. In the fetch-execute state
> the bus fetches the instruction, and arithmetic and branches finish there. A load or store has to
> wait for a second state, where the bus is used for data. So baseline cycles equal Harvard cycles
> plus the number of loads and stores, and our simulations match that exactly. Harvard has a CPI of
> one on every program. The baseline ranges from 1.02 for a register-only loop to 1.37 for our most
> memory-heavy program. The more a program touches memory, the more the separate paths help.

## 3:50-4:40 · Status and Phase II (Ram)

*Screen: GitHub repository: folders, commit history, README, report PDF.*

> Everything is in our GitHub repository: the RTL for both designs, the testbenches, programs and
> assembler, the simulation logs and comparison table, and our IEEE-format report. The README shows
> how to run every test with one command. For Phase II we plan to put small instruction and data
> caches in front of a single main memory, which is how real processors use the Harvard idea, add
> memory latency to study stalls, and synthesize both designs on an FPGA to compare area and
> clock speed. Thank you for watching.

---

Video link: [Google Drive](https://drive.google.com/drive/folders/1SoN0jAJ3BcboLqRUhE7eCVd88pDHP2RP?usp=sharing)
(same link as in `README.md`; sharing must be "Anyone with the link can view", checked from a
logged-out browser window).
