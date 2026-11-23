`default_nettype none
`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// mem_arbiter : connects the I-cache and the D-cache to ONE lower-level memory
//
//   - fixed priority: instruction requests win (a read that stalls the core),
//     the D side waits. D-side reads only happen while the I-cache hits, so in
//     practice the conflict is an I-miss against a draining write buffer.
//   - once a transfer has started it keeps the memory until ready (no
//     pre-emption), so the memory always sees a stable request.
//   - ev_conflict = 1 in every cycle in which both sides request the memory
//     (one of them is waiting because the lower level is shared).
// -----------------------------------------------------------------------------
module mem_arbiter #(
    parameter LINE_WORDS = 4
) (
    input  wire                     clk,
    input  wire                     rst,
    // instruction side (I-cache)
    input  wire                     i_req,
    input  wire                     i_we,
    input  wire [31:0]              i_addr,
    input  wire [31:0]              i_wdata,
    output wire                     i_ready,
    // data side (D-cache)
    input  wire                     d_req,
    input  wire                     d_we,
    input  wire [31:0]              d_addr,
    input  wire [31:0]              d_wdata,
    output wire                     d_ready,
    // lower-level memory
    output wire                     m_req,
    output wire                     m_we,
    output wire [31:0]              m_addr,
    output wire [31:0]              m_wdata,
    input  wire                     m_ready,
    output wire                     ev_conflict
);
    reg busy;       // a transfer is in progress
    reg owner;      // 0 = I side, 1 = D side

    // idle: D side gets the memory only when the I side does not want it. sel_d
    // deliberately does not depend on d_req (no combinational D -> I path).
    wire sel_d = busy ? owner : ~i_req;

    assign m_req   = sel_d ? d_req   : i_req;
    assign m_we    = sel_d ? d_we    : i_we;
    assign m_addr  = sel_d ? d_addr  : i_addr;
    assign m_wdata = sel_d ? d_wdata : i_wdata;

    assign i_ready = ~sel_d & m_ready;
    assign d_ready =  sel_d & m_ready;

    assign ev_conflict = i_req & d_req;

    always @(posedge clk) begin
        if (rst) begin
            busy  <= 1'b0;
            owner <= 1'b0;
        end else if (m_req & ~m_ready) begin
            busy  <= 1'b1;
            owner <= sel_d;
        end else if (m_req & m_ready) begin
            busy  <= 1'b0;
        end
    end
endmodule
`default_nettype wire
