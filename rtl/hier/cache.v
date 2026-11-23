`default_nettype none
`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// cache : direct-mapped, write-through, no-write-allocate cache
//         with an optional one-entry write buffer
//
// Used three ways:  I-cache (we is never asserted), D-cache, and unified cache.
//
// Address split (physical byte address, ADDR_BITS = 11 for the 512-word memory):
//     | tag | index (log2 LINES) | word offset (log2 LINE_WORDS) | 00 |
//
// CPU side (combinational, same cycle):
//   re = 1 : read.  hit  -> ready = 1, rdata from the cache line.
//                   miss -> the line is requested from memory and written into
//                           the cache when memory answers; the next cycle is a
//                           hit. Miss penalty = LATENCY cycles.
//                   (No critical-word forwarding: it would create a
//                   combinational path memory -> core -> address -> memory.
//                   Only the uncached mode forwards, since it has no array.)
//   we = 1 : write (write-through).
//            WBUF = 1 : the store is put into the write buffer and completes at
//                       once (ready = 1) if the buffer is empty, or if it is
//                       draining this very cycle; otherwise the core waits.
//            WBUF = 0 : the store goes to memory directly; ready when memory is.
//            On a hit the cached word is updated too; on a miss the line is NOT
//            allocated (no-write-allocate).
//   neither : ready = 1.
// The requester keeps re/we/addr/wdata stable until ready.
//
// Memory side: m_req/m_we/m_addr/m_wdata held until m_ready.
//   Priority inside the cache: write buffer drain first, then a line fill.
//   A read miss waits until the write buffer is empty, so memory is always up
//   to date before a line is fetched (no read-after-write hazard).
//
// ENABLE = 0 turns the cache off (every read misses, nothing is stored, the
// memory word is forwarded): an uncached path with the same handshake. Each
// access then takes exactly LATENCY cycles.
// -----------------------------------------------------------------------------
module cache #(
    parameter LINES      = 8,      // number of lines, power of 2
    parameter LINE_WORDS = 4,      // words per line, power of 2
    parameter ADDR_BITS  = 11,     // physical byte address bits used
    parameter ENABLE     = 1,
    parameter WBUF       = 1
) (
    input  wire                     clk,
    input  wire                     rst,
    // CPU side
    input  wire                     re,
    input  wire                     we,
    input  wire [31:0]              addr,
    input  wire [31:0]              wdata,
    output wire [31:0]              rdata,
    output wire                     ready,
    // memory side
    output wire                     m_req,
    output wire                     m_we,
    output wire [31:0]              m_addr,
    output wire [31:0]              m_wdata,
    input  wire [LINE_WORDS*32-1:0] m_rline,
    input  wire                     m_ready,
    // events (one-cycle pulses / levels) for the performance counters
    output wire                     ev_read_hit,     // read completed from the cache
    output wire                     ev_fill,         // line fill (read miss) completed
    output wire                     ev_wbuf_stall    // store waiting for the write buffer
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
    localparam OW   = clog2(LINE_WORDS);            // word-offset bits
    localparam IW   = clog2(LINES);                 // index bits
    localparam TAGW = ADDR_BITS - 2 - OW - IW;      // tag bits

    // ---- address fields (arithmetic form so 1-line / 1-word configs work) ----
    wire [ADDR_BITS-1:0] a      = addr[ADDR_BITS-1:0];
    wire [31:0]          wordad = {{(32-ADDR_BITS){1'b0}}, a} >> 2;
    wire [31:0]          woff   = wordad % LINE_WORDS;
    wire [31:0]          lineno = wordad / LINE_WORDS;
    wire [31:0]          index  = lineno % LINES;
    wire [TAGW-1:0]      tag    = lineno / LINES;

    // ---- storage ----
    reg              valid   [0:LINES-1];
    reg [TAGW-1:0]   tag_arr [0:LINES-1];
    reg [31:0]       data_arr[0:LINES*LINE_WORDS-1];

    wire hit = (ENABLE != 0) && valid[index] && (tag_arr[index] == tag);

    // ---- write buffer (one entry) ----
    reg        wb_valid;
    reg [31:0] wb_addr, wb_data;

    wire use_wb       = (WBUF != 0);
    wire direct_store = ~use_wb & we;               // WBUF = 0: store goes straight out
    wire need_fill    = re & ~hit & ~wb_valid;      // fill only with an empty buffer
    wire fill_done    = need_fill & m_ready;
    wire store_ok     = use_wb ? (we & (~wb_valid | m_ready)) : (we & m_ready);
    wire fwd          = (ENABLE == 0);              // forward memory data only when uncached

    // ---- memory-side request ----
    wire [31:0] line_addr = {lineno[29:0], 2'b00} << OW;   // first byte of the line
    assign m_req   = wb_valid | direct_store | need_fill;
    assign m_we    = wb_valid | direct_store;
    assign m_addr  = wb_valid ? wb_addr : direct_store ? addr : line_addr;
    assign m_wdata = wb_valid ? wb_data : wdata;

    // ---- CPU-side response ----
    assign ready = we ? store_ok : re ? (hit | (fwd & fill_done)) : 1'b1;
    assign rdata = fwd ? m_rline[woff * 32 +: 32] : data_arr[index * LINE_WORDS + woff];

    assign ev_read_hit   = re & hit;
    assign ev_fill       = fill_done;
    assign ev_wbuf_stall = we & ~store_ok;

    // ---- state update ----
    integer i;
    initial begin
        for (i = 0; i < LINES; i = i + 1) begin
            valid[i]   = 1'b0;
            tag_arr[i] = {TAGW{1'b0}};
        end
        for (i = 0; i < LINES * LINE_WORDS; i = i + 1)
            data_arr[i] = 32'h0000_0000;
    end

    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < LINES; i = i + 1)
                valid[i] <= 1'b0;
            wb_valid <= 1'b0;
        end else begin
            // write buffer: drain completes / new store accepted
            if (use_wb) begin
                if (store_ok) begin
                    wb_valid <= 1'b1;
                    wb_addr  <= addr;
                    wb_data  <= wdata;
                end else if (wb_valid & m_ready) begin
                    wb_valid <= 1'b0;
                end
            end
            // line fill
            if (fill_done && ENABLE != 0) begin
                valid[index]   <= 1'b1;
                tag_arr[index] <= tag;
                for (i = 0; i < LINE_WORDS; i = i + 1)
                    data_arr[index * LINE_WORDS + i] <= m_rline[i*32 +: 32];
            end
            // write hit: keep the cached copy up to date (write-through)
            if (store_ok & hit)
                data_arr[index * LINE_WORDS + woff] <= wdata;
        end
    end
endmodule
`default_nettype wire
