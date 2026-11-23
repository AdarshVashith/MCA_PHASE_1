`default_nettype none
`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// imm_gen : builds the sign-extended immediate for the current instruction
//   I-type (ADDI.., LW, JALR) : imm[11:0]  = instr[31:20]
//   S-type (SW)               : imm[11:0]  = {instr[31:25], instr[11:7]}
//   B-type (branches)         : imm[12:1]  = {instr[31], instr[7], instr[30:25], instr[11:8]}
//   U-type (LUI)              : imm[31:12] = instr[31:12], imm[11:0] = 0
//   J-type (JAL)              : imm[20:1]  = {instr[31], instr[19:12], instr[20], instr[30:21]}
//   instr[31] is always the sign bit.
// -----------------------------------------------------------------------------
module imm_gen (
    input  wire [31:0] instr,
    output reg  [31:0] imm
);
    always @(*) begin
        case (instr[6:0])
            7'b0010011,                                             // I-type ALU
            7'b0000011,                                             // LW
            7'b1100111: imm = {{20{instr[31]}}, instr[31:20]};      // JALR
            7'b0100011: imm = {{20{instr[31]}}, instr[31:25], instr[11:7]};               // SW
            7'b1100011: imm = {{19{instr[31]}}, instr[31], instr[7], instr[30:25],
                               instr[11:8], 1'b0};                                        // branches
            7'b0110111: imm = {instr[31:12], 12'd0};                                      // LUI
            7'b1101111: imm = {{11{instr[31]}}, instr[31], instr[19:12], instr[20],
                               instr[30:21], 1'b0};                                       // JAL
            default:    imm = 32'h0000_0000;
        endcase
    end
endmodule
`default_nettype wire
