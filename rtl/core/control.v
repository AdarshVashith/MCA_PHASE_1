`default_nettype none
`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// control : main decoder. Looks at opcode/funct3/funct7 and drives the datapath.
//
// Phase I subset : ADD SUB AND OR ADDI LW SW BEQ BNE EBREAK
// Phase II adds  : XOR SLT SLL SRL (R-type)  ANDI ORI XORI SLTI SLLI SRLI (I-type)
//                  BLT BGE (branches)  JAL JALR (jumps)  LUI (upper immediate)
//
//   instr   reg_we alu_src alu_op mem_re mem_we wb_sel  branch br_type jal jalr halt
//   R-type    1      0     funct    0      0     ALU      0      -      0   0    0
//   I-ALU     1      1     funct    0      0     ALU      0      -      0   0    0
//   LW        1      1     ADD      1      0     MEM      0      -      0   0    0
//   SW        0      1     ADD      0      1      -       0      -      0   0    0
//   BEQ/BNE   0      0     SUB      0      0      -       1    EQ/NE    0   0    0
//   BLT/BGE   0      0     SLT      0      0      -       1    LT/GE    0   0    0
//   JAL       1      -      -       0      0     PC4      0      -      1   0    0
//   JALR      1      1     ADD      0      0     PC4      0      -      0   1    0
//   LUI       1      -      -       0      0     IMM      0      -      0   0    0
//   EBREAK    0      0      -       0      0      -       0      -      0   0    1
//   other     all zero (behaves as a NOP)
// -----------------------------------------------------------------------------
module control (
    input  wire [31:0] instr,
    output reg         reg_we,
    output reg         alu_src,
    output reg  [2:0]  alu_op,
    output reg         mem_re,
    output reg         mem_we,
    output reg  [1:0]  wb_sel,     // 00 ALU, 01 memory, 10 PC+4, 11 immediate (LUI)
    output reg         branch,
    output reg  [1:0]  br_type,    // 00 EQ, 01 NE, 10 LT, 11 GE
    output reg         is_jal,
    output reg         is_jalr,
    output reg         is_halt
);
    localparam ALU_ADD = 3'b000, ALU_SUB = 3'b001, ALU_AND = 3'b010, ALU_OR  = 3'b011,
               ALU_XOR = 3'b100, ALU_SLT = 3'b101, ALU_SLL = 3'b110, ALU_SRL = 3'b111;
    localparam WB_ALU = 2'b00, WB_MEM = 2'b01, WB_PC4 = 2'b10, WB_IMM = 2'b11;

    wire [6:0] opcode = instr[6:0];
    wire [2:0] funct3 = instr[14:12];
    wire [6:0] funct7 = instr[31:25];

    always @(*) begin
        // defaults = NOP
        reg_we  = 1'b0;
        alu_src = 1'b0;
        alu_op  = ALU_ADD;
        mem_re  = 1'b0;
        mem_we  = 1'b0;
        wb_sel  = WB_ALU;
        branch  = 1'b0;
        br_type = 2'b00;
        is_jal  = 1'b0;
        is_jalr = 1'b0;
        is_halt = 1'b0;

        if (instr == 32'h0010_0073) begin
            is_halt = 1'b1;                                         // EBREAK
        end else begin
            case (opcode)
                7'b0110011: begin                                   // R-type
                    case ({funct7, funct3})
                        {7'b0000000, 3'b000}: begin reg_we = 1'b1; alu_op = ALU_ADD; end
                        {7'b0100000, 3'b000}: begin reg_we = 1'b1; alu_op = ALU_SUB; end
                        {7'b0000000, 3'b111}: begin reg_we = 1'b1; alu_op = ALU_AND; end
                        {7'b0000000, 3'b110}: begin reg_we = 1'b1; alu_op = ALU_OR;  end
                        {7'b0000000, 3'b100}: begin reg_we = 1'b1; alu_op = ALU_XOR; end
                        {7'b0000000, 3'b010}: begin reg_we = 1'b1; alu_op = ALU_SLT; end
                        {7'b0000000, 3'b001}: begin reg_we = 1'b1; alu_op = ALU_SLL; end
                        {7'b0000000, 3'b101}: begin reg_we = 1'b1; alu_op = ALU_SRL; end
                        default: ;                                  // NOP
                    endcase
                end
                7'b0010011: begin                                   // I-type ALU
                    case (funct3)
                        3'b000: begin reg_we = 1'b1; alu_src = 1'b1; alu_op = ALU_ADD; end // ADDI
                        3'b111: begin reg_we = 1'b1; alu_src = 1'b1; alu_op = ALU_AND; end // ANDI
                        3'b110: begin reg_we = 1'b1; alu_src = 1'b1; alu_op = ALU_OR;  end // ORI
                        3'b100: begin reg_we = 1'b1; alu_src = 1'b1; alu_op = ALU_XOR; end // XORI
                        3'b010: begin reg_we = 1'b1; alu_src = 1'b1; alu_op = ALU_SLT; end // SLTI
                        3'b001: if (funct7 == 7'b0000000) begin                         // SLLI
                                    reg_we = 1'b1; alu_src = 1'b1; alu_op = ALU_SLL; end
                        3'b101: if (funct7 == 7'b0000000) begin                         // SRLI
                                    reg_we = 1'b1; alu_src = 1'b1; alu_op = ALU_SRL; end
                        default: ;                                  // NOP
                    endcase
                end
                7'b0000011: if (funct3 == 3'b010) begin             // LW
                    reg_we = 1'b1; alu_src = 1'b1; mem_re = 1'b1; wb_sel = WB_MEM;
                end
                7'b0100011: if (funct3 == 3'b010) begin             // SW
                    alu_src = 1'b1; mem_we = 1'b1;
                end
                7'b1100011: begin                                   // branches
                    case (funct3)
                        3'b000: begin branch = 1'b1; br_type = 2'b00; alu_op = ALU_SUB; end // BEQ
                        3'b001: begin branch = 1'b1; br_type = 2'b01; alu_op = ALU_SUB; end // BNE
                        3'b100: begin branch = 1'b1; br_type = 2'b10; alu_op = ALU_SLT; end // BLT
                        3'b101: begin branch = 1'b1; br_type = 2'b11; alu_op = ALU_SLT; end // BGE
                        default: ;                                  // NOP
                    endcase
                end
                7'b1101111: begin                                   // JAL
                    reg_we = 1'b1; wb_sel = WB_PC4; is_jal = 1'b1;
                end
                7'b1100111: if (funct3 == 3'b000) begin             // JALR
                    reg_we = 1'b1; alu_src = 1'b1; wb_sel = WB_PC4; is_jalr = 1'b1;
                end
                7'b0110111: begin                                   // LUI
                    reg_we = 1'b1; wb_sel = WB_IMM;
                end
                default: ;                                          // NOP
            endcase
        end
    end
endmodule
`default_nettype wire
