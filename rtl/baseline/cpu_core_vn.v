`default_nettype none
`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// cpu_core_vn : same instruction behaviour as cpu_core, but with ONE memory bus
//
// Two-state FSM:
//
//             non-memory instr (ALU, branch, jump, EBREAK): done, PC updated
//            +-----+
//            |     v
//         +------------+   LW / SW: latch instr   +-------+
//   rst ->| FETCH_EXEC |------------------------->|  MEM  |
//         +------------+ <------------------------+-------+
//                         data access done, PC+4
//
//   FETCH_EXEC : bus carries the PC (instruction fetch). ALU/branch/jump/EBREAK
//                finish here. LW/SW cannot use the bus again this cycle, so
//                the instruction is latched in 'ir' and we go to MEM.
//   MEM        : bus carries the data address (m_is_data = 1). SW writes, LW
//                reads and writes the register; the PC advances.
//
// The register file is not written in FETCH_EXEC for LW/SW, so in MEM the
// same rs1/rs2 values are read again and the ALU recomputes the address from
// the latched instruction.
//
// Phase II: m_ready = 0 means the bus transfer of this cycle has not finished
// (unified-cache miss, memory latency). The core then holds its state, PC, ir
// and register file, and keeps the request on the bus. vn_top ties m_ready to
// 1, which gives exactly the Phase I behaviour.
// -----------------------------------------------------------------------------
module cpu_core_vn (
    input  wire        clk,
    input  wire        rst,
    output wire [31:0] m_addr,
    output wire [31:0] m_wdata,
    output wire        m_we,
    output wire        m_re,
    output wire        m_is_data,
    input  wire [31:0] m_rdata,
    input  wire        m_ready,
    output wire        halt,
    output wire        instr_done
);
    localparam FETCH_EXEC = 1'b0, MEM = 1'b1;
    localparam NOP = 32'h0000_0013;

    reg        state;
    reg [31:0] pc;
    reg [31:0] ir;          // instruction latched for the MEM cycle
    reg        halted;

    // in FETCH_EXEC the instruction arrives on the bus (only valid when m_ready);
    // in MEM use the latched one
    wire [31:0] fetched = m_ready ? m_rdata : NOP;
    wire [31:0] instr   = (state == MEM) ? ir : fetched;

    wire       reg_we, alu_src, mem_re, mem_we, branch, is_jal, is_jalr, is_halt;
    wire [2:0] alu_op;
    wire [1:0] wb_sel, br_type;
    wire [31:0] rs1_val, rs2_val, imm, alu_y;
    reg  [31:0] wb_data;
    wire        alu_zero;

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

    wire is_mem_op = mem_re | mem_we;

    // register write: non-memory instrs in FETCH_EXEC, LW in MEM; never on a stall
    wire rf_we = ~halt & m_ready & reg_we & ((state == FETCH_EXEC) ? ~is_mem_op : 1'b1);

    regfile u_regfile (
        .clk(clk),
        .we (rf_we),
        .ra1(instr[19:15]),
        .ra2(instr[24:20]),
        .wa (instr[11:7]),
        .wd (wb_data),
        .rd1(rs1_val),
        .rd2(rs2_val)
    );

    alu u_alu (
        .a   (rs1_val),
        .b   (alu_src ? imm : rs2_val),
        .op  (alu_op),
        .y   (alu_y),
        .zero(alu_zero)
    );

    wire [31:0] pc_plus4 = pc + 32'd4;

    always @(*) begin
        case (wb_sel)
            2'b00:   wb_data = alu_y;
            2'b01:   wb_data = m_rdata;
            2'b10:   wb_data = pc_plus4;
            default: wb_data = imm;
        endcase
    end

    reg cond;
    always @(*) begin
        case (br_type)
            2'b00:   cond =  alu_zero;
            2'b01:   cond = ~alu_zero;
            2'b10:   cond =  alu_y[0];
            default: cond = ~alu_y[0];
        endcase
    end
    wire branch_taken = branch & cond;
    wire [31:0] pc_next = is_jalr                 ? {alu_y[31:1], 1'b0} :
                          (is_jal | branch_taken) ? (pc + imm)          :
                                                    pc_plus4;

    // ---------------- the single memory bus ----------------
    assign m_is_data = (state == MEM);
    assign m_addr    = (state == MEM) ? alu_y : pc;      // data address or PC
    assign m_wdata   = rs2_val;
    assign m_we      = (state == MEM) & mem_we;
    assign m_re      = (state == MEM) ? mem_re : ~halted; // fetch read until halted

    // ---------------- halt / retire ----------------
    assign halt       = halted | ((state == FETCH_EXEC) & is_halt);
    assign instr_done = ~halted & m_ready & ((state == MEM) | ~is_mem_op);

    // ---------------- state, PC, latched instruction ----------------
    always @(posedge clk) begin
        if (rst) begin
            state  <= FETCH_EXEC;
            pc     <= 32'h0000_0000;
            ir     <= 32'h0000_0000;
            halted <= 1'b0;
        end else if (!m_ready) begin
            // stall: hold everything, the request stays on the bus
        end else if (state == FETCH_EXEC) begin
            if (halt) begin
                halted <= 1'b1;                          // EBREAK: PC frozen
            end else if (is_mem_op) begin
                ir    <= m_rdata;                        // keep LW/SW for MEM
                state <= MEM;                            // PC waits
            end else begin
                pc <= pc_next;
            end
        end else begin                                   // MEM
            pc    <= pc_plus4;
            state <= FETCH_EXEC;
        end
    end
endmodule
`default_nettype wire
