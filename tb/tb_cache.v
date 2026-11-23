`default_nettype none
`timescale 1ns/1ps
// tb_cache: directed unit test of cache + main_mem (Phase II)
//   cache: 4 lines x 4 words (64 bytes), write-through, no-write-allocate, 1-entry write buffer
//   memory: LATENCY = 3, data image array_sum_data.hex (3 1 4 1 5 9 2 6) at physical 0x400
// Checks:
//   1. read miss takes LATENCY stall cycles + 1, then the line hits
//   2. hits complete in the same cycle and return the right words
//   3. store hit completes at once (buffered), updates the cache, reaches memory later
//   4. a second store waits while the first is still draining
//   5. store miss does not allocate; a later read sees the stored value
//   6. two addresses with the same index evict each other (conflict miss)
//   7. uncached instance (ENABLE = 0): every read costs exactly LATENCY cycles
module tb_cache;
    localparam L = 3;
    reg clk = 0, rst = 1;
    always #5 clk = ~clk;

    // ---------- cached instance ----------
    reg         re = 0, we = 0;
    reg  [31:0] addr = 0, wdata = 0;
    wire [31:0] rdata;
    wire        ready, m_req, m_we, m_ready;
    wire [31:0] m_addr, m_wdata;
    wire [127:0] rline;
    wire ev_hit, ev_fill, ev_wbst;

    cache #(.LINES(4), .LINE_WORDS(4), .ENABLE(1), .WBUF(1)) dut (
        .clk(clk), .rst(rst), .re(re), .we(we), .addr(addr), .wdata(wdata),
        .rdata(rdata), .ready(ready),
        .m_req(m_req), .m_we(m_we), .m_addr(m_addr), .m_wdata(m_wdata),
        .m_rline(rline), .m_ready(m_ready),
        .ev_read_hit(ev_hit), .ev_fill(ev_fill), .ev_wbuf_stall(ev_wbst));

    main_mem #(.LATENCY(L), .LINE_WORDS(4), .DATA_FILE("../programs/array_sum_data.hex")) mem (
        .clk(clk), .rst(rst), .req(m_req), .we(m_we), .addr(m_addr), .wdata(m_wdata),
        .rline(rline), .ready(m_ready));

    // ---------- uncached instance ----------
    reg         ure = 0;
    reg  [31:0] uaddr = 0;
    wire [31:0] urdata, um_addr, um_wdata;
    wire        uready, um_req, um_we, um_ready;
    wire [127:0] urline;
    wire u1, u2, u3;

    cache #(.LINES(4), .LINE_WORDS(4), .ENABLE(0), .WBUF(0)) dut_nc (
        .clk(clk), .rst(rst), .re(ure), .we(1'b0), .addr(uaddr), .wdata(32'd0),
        .rdata(urdata), .ready(uready),
        .m_req(um_req), .m_we(um_we), .m_addr(um_addr), .m_wdata(um_wdata),
        .m_rline(urline), .m_ready(um_ready),
        .ev_read_hit(u1), .ev_fill(u2), .ev_wbuf_stall(u3));

    main_mem #(.LATENCY(L), .LINE_WORDS(4), .DATA_FILE("../programs/array_sum_data.hex")) mem_nc (
        .clk(clk), .rst(rst), .req(um_req), .we(um_we), .addr(um_addr), .wdata(um_wdata),
        .rline(urline), .ready(um_ready));

    integer errors = 0, fills = 0;
    always @(posedge clk) if (ev_fill) fills = fills + 1;

    task chk(input [8*40-1:0] what, input [31:0] got, input [31:0] exp);
        if (got !== exp) begin
            $display("FAIL %0s = %0d (0x%h), expected %0d", what, got, got, exp);
            errors = errors + 1;
        end
    endtask

    // one access; returns read data and the number of cycles it took (1 = no stall)
    task access(input w, input [31:0] a, input [31:0] d, output [31:0] q, output integer cyc);
        begin
            @(negedge clk);
            re = ~w; we = w; addr = a; wdata = d; cyc = 1;
            #1;
            while (!ready) begin
                @(negedge clk); #1; cyc = cyc + 1;
            end
            q = rdata;
            @(posedge clk); #1;
            re = 0; we = 0;
        end
    endtask

    task uread(input [31:0] a, output [31:0] q, output integer cyc);
        begin
            @(negedge clk);
            ure = 1; uaddr = a; cyc = 1;
            #1;
            while (!uready) begin
                @(negedge clk); #1; cyc = cyc + 1;
            end
            q = urdata;
            @(posedge clk); #1;
            ure = 0;
        end
    endtask

    reg [31:0] q;
    integer c;
    initial begin
        repeat (2) @(posedge clk);
        @(negedge clk) rst = 0;

        // 1. cold read miss: L cycles waiting for memory + 1 cycle to hit
        access(0, 32'h400, 0, q, c);
        chk("miss cycles", c, L + 1);
        chk("miss data", q, 3);
        chk("fills after miss", fills, 1);

        // 2. hits in the same line
        access(0, 32'h404, 0, q, c);  chk("hit cycles", c, 1);  chk("hit data [1]", q, 1);
        access(0, 32'h40C, 0, q, c);  chk("hit cycles", c, 1);  chk("hit data [3]", q, 1);
        access(0, 32'h408, 0, q, c);  chk("hit data [2]", q, 4);

        // 3. store hit: buffered, completes at once, cache updated
        access(1, 32'h404, 77, q, c); chk("store (empty wbuf) cycles", c, 1);
        access(0, 32'h404, 0, q, c);  chk("read after store hit", q, 77); chk("hit cycles", c, 1);
        repeat (L + 1) @(posedge clk); #1;
        chk("memory after drain", mem.mem[257], 77);

        // 4. back-to-back stores: second one waits for the buffer
        access(1, 32'h408, 11, q, c); chk("store 1 cycles", c, 1);
        access(1, 32'h40C, 12, q, c);
        if (c < 2) begin $display("FAIL second store did not wait for the write buffer"); errors = errors + 1; end
        repeat (L + 1) @(posedge clk); #1;
        chk("memory word 258", mem.mem[258], 11);
        chk("memory word 259", mem.mem[259], 12);

        // 5. store miss: no allocate, then the read sees the value via memory
        access(1, 32'h480, 99, q, c); chk("store miss cycles", c, 1);
        chk("no allocate on store miss", fills, 1);
        access(0, 32'h480, 0, q, c);
        chk("read after store miss", q, 99);
        chk("fills after store-miss read", fills, 2);

        // 6. conflict: 0x400 and 0x440 share index 0 (4 lines x 16 B = 64 B)
        access(0, 32'h440, 0, q, c);  chk("conflict miss cycles", c, L + 1);
        access(0, 32'h400, 0, q, c);  chk("re-miss after eviction", c, L + 1);
        chk("data after re-fill", q, 3);
        chk("fills total", fills, 4);

        // 7. uncached: every read costs LATENCY, no hits
        uread(32'h400, q, c);  chk("uncached cycles", c, L);  chk("uncached data", q, 3);
        uread(32'h400, q, c);  chk("uncached again", c, L);
        uread(32'h414, q, c);  chk("uncached data [5]", q, 9);

        if (errors == 0) $display("tb_cache: PASS");
        else             $display("tb_cache: FAIL (%0d errors)", errors);
        $finish;
    end
endmodule
`default_nettype wire
