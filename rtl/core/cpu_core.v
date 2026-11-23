`default_nettype none
`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// cpu_core : single-cycle RV32I-subset processor for the Harvard systems
//
// Every cycle, in one pass of combinational logic:
//   fetch   : i_addr = PC, instruction comes back on i_rdata (instruction port)
//   decode  : control + imm_gen + register reads
//   execute : ALU computes a result, a data address, or a branch compare
//   memory  : LW/SW use the data port (d_addr/d_we/d_re) IN THE SAME CYCLE
//   write   : result written to rd and PC updated on the next rising edge
//
// The core contains no memory; it only talks to the i_* and d_* ports.
//
// Phase II: stall support for a memory hierarchy with caches.
//   i_ready = 0 : the instruction port has no valid instruction this cycle
//                 (I-cache miss). The core decodes a NOP and holds everything.
//   d_ready = 0 : a LW/SW has not completed (D-cache miss, full write buffer).
//                 The core holds the PC and does not write the register file.
// While a stall lasts the PC, i_addr, d_addr and d_wdata stay constant, so the
// memory side sees a stable request. harvard_top ties both to 1, which gives
// exactly the Phase I single-cycle behaviour.
//
// Halt: when EBREAK is decoded, halt goes high in that cycle and the PC stops.
// The 'halted' flag keeps halt high afterwards and makes sure EBREAK is
// counted as retired exactly once (instr_done is high in the EBREAK cycle only).
// -----------------------------------------------------------------------------
module cpu_core (
    input  wire        clk,
    input  wire        rst,
    output wire [31:0] i_addr,
    input  wire [31:0] i_rdata,
    input  wire        i_ready,
    output wire [31:0] d_addr,
    output wire [31:0] d_wdata,
    output wire        d_we,
    output wire        d_re,
    input  wire [31:0] d_rdata,
    input  wire        d_ready,
    output wire        halt,
    output wire        instr_done
);
    localparam NOP = 32'h0000_0013;   // addi x0, x0, 0

    wire [31:0] pc, pc_next;
    // no valid instruction during an I-side stall: decode a NOP instead
    wire [31:0] instr = i_ready ? i_rdata : NOP;

    // control signals
    wire       reg_we, alu_src, mem_re, mem_we, branch, is_jal, is_jalr, is_halt;
    wire [2:0] alu_op;
    wire [1:0] wb_sel, br_type;

    // datapath values
    wire [31:0] rs1_val, rs2_val, imm, alu_b, alu_y;
    reg  [31:0] wb_data;
    wire        alu_zero;

    reg halted;                       // set after EBREAK has retired

    wire stall = ~i_ready | ((mem_re | mem_we) & ~d_ready);

    // ---------------- fetch ----------------
    pc_reg u_pc (
        .clk    (clk),
        .rst    (rst),
        .en     (~halt & ~stall),     // PC freezes on a stall, in the EBREAK cycle and after
        .pc_next(pc_next),
        .pc     (pc)
    );
    assign i_addr = pc;

    // ---------------- decode ----------------
    control u_ctrl (
        .instr  (instr),
        .reg_we (reg_we),
        .alu_src(alu_src),
        .alu_op (alu_op),
        .mem_re (mem_re),
        .mem_we (mem_we),
        .wb_sel (wb_sel),
        .branch (branch),
        .br_type(br_type),
        .is_jal (is_jal),
        .is_jalr(is_jalr),
        .is_halt(is_halt)
    );

    imm_gen u_imm (
        .instr(instr),
        .imm  (imm)
    );

    regfile u_regfile (
        .clk(clk),
        .we (reg_we & ~halt & ~stall),
        .ra1(instr[19:15]),           // rs1
        .ra2(instr[24:20]),           // rs2
        .wa (instr[11:7]),            // rd
        .wd (wb_data),
        .rd1(rs1_val),
        .rd2(rs2_val)
    );

    // ---------------- execute ----------------
    assign alu_b = alu_src ? imm : rs2_val;

    alu u_alu (
        .a   (rs1_val),
        .b   (alu_b),
        .op  (alu_op),
        .y   (alu_y),
        .zero(alu_zero)
    );

    // BEQ/BNE: ALU does rs1 - rs2, zero flag means equal.
    // BLT/BGE: ALU does SLT, y[0] = 1 means rs1 < rs2 (signed).
    reg cond;
    always @(*) begin
        case (br_type)
            2'b00:   cond =  alu_zero;    // BEQ
            2'b01:   cond = ~alu_zero;    // BNE
            2'b10:   cond =  alu_y[0];    // BLT
            default: cond = ~alu_y[0];    // BGE
        endcase
    end
    wire branch_taken = branch & cond;
    wire [31:0] pc_plus4 = pc + 32'd4;

    assign pc_next = is_jalr                  ? {alu_y[31:1], 1'b0} :   // rs1 + imm, bit 0 cleared
                     (is_jal | branch_taken)  ? (pc + imm)          :
                                                pc_plus4;

    // ---------------- memory (data port, same cycle as the fetch) -------------
    assign d_addr  = alu_y;
    assign d_wdata = rs2_val;
    assign d_we    = mem_we & ~halt;
    assign d_re    = mem_re & ~halt;

    // ---------------- write back ----------------
    always @(*) begin
        case (wb_sel)
            2'b00:   wb_data = alu_y;
            2'b01:   wb_data = d_rdata;
            2'b10:   wb_data = pc_plus4;  // JAL / JALR link
            default: wb_data = imm;       // LUI
        endcase
    end

    // ---------------- halt / retire ----------------
    always @(posedge clk) begin
        if (rst)
            halted <= 1'b0;
        else if (is_halt)
            halted <= 1'b1;
    end

    assign halt       = halted | is_halt;
    assign instr_done = ~halted & ~stall;   // one instruction per non-stalled cycle
endmodule
`default_nettype wire
