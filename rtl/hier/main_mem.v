`default_nettype none
`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// main_mem : unified lower-level memory (shared by instructions and data)
//
//   physical words   0..255 : program (PROG_FILE)  byte 0x000-0x3FF
//   physical words 256..511 : data    (DATA_FILE)  byte 0x400-0x7FF
//
// One port with a request/ready handshake and a fixed access time:
//   - the requester raises req and holds req/we/addr/wdata stable
//   - ready is high in the LATENCY-th cycle of a request (LATENCY >= 1);
//     LATENCY = 1 means ready in the same cycle, i.e. the ideal Phase I memory.
//     ready depends only on the internal timer, not on req, so it creates no
//     combinational path back to the requester; requesters only look at it
//     while they are requesting.
//   - a read returns the whole line (LINE_WORDS words) that contains addr on
//     rline, so a cache can be filled in one transfer (wide refill bus)
//   - a write stores one word on the rising edge at the end of the ready cycle
// -----------------------------------------------------------------------------
module main_mem #(
    parameter DEPTH_WORDS = 512,
    parameter LATENCY     = 1,
    parameter LINE_WORDS  = 4,
    parameter PROG_FILE   = "",
    parameter DATA_FILE   = ""
) (
    input  wire                     clk,
    input  wire                     rst,
    input  wire                     req,
    input  wire                     we,
    input  wire [31:0]              addr,
    input  wire [31:0]              wdata,
    output wire [LINE_WORDS*32-1:0] rline,
    output wire                     ready
);
    function integer clog2;
        input integer value;
        integer v;
        begin
            v = value - 1;
            for (clog2 = 0; v > 0; clog2 = clog2 + 1)
                v = v >> 1;
        end
    endfunction
    localparam AW = clog2(DEPTH_WORDS);

    reg [31:0] mem [0:DEPTH_WORDS-1];

    integer i;
    initial begin
        for (i = 0; i < DEPTH_WORDS; i = i + 1)
            mem[i] = 32'h0000_0000;
        if (PROG_FILE != "")
            $readmemh(PROG_FILE, mem, 0, 255);
        if (DATA_FILE != "")
            $readmemh(DATA_FILE, mem, 256, 511);
    end

    // ---- access timer: counts the cycles of the current request ----
    reg [7:0] cnt;
    assign ready = (cnt == LATENCY - 1);

    always @(posedge clk) begin
        if (rst)              cnt <= 8'd0;
        else if (req & ready) cnt <= 8'd0;
        else if (req)         cnt <= cnt + 8'd1;
    end

    wire [AW-1:0] word = addr[AW+1:2];

    always @(posedge clk) begin
        if (req & ready & we)
            mem[word] <= wdata;
    end

    // ---- line read: the LINE_WORDS words of the aligned block ----
    wire [AW-1:0] base = word & ~(LINE_WORDS - 1);
    genvar w;
    generate
        for (w = 0; w < LINE_WORDS; w = w + 1) begin : g_line
            assign rline[w*32 +: 32] = mem[base + w];
        end
    endgenerate
endmodule
`default_nettype wire
