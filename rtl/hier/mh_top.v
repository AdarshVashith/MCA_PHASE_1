`default_nettype none
`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// mh_top : MODIFIED HARVARD system (Phase II)
//
//        +----------+  i_addr  +---------+                   +-------------+
//        |          |--------->| I-cache |---+               |             |
//        |          |<---------| (RO)    |   |  +---------+  |  main_mem   |
//        | cpu_core |  i_rdata +---------+   +->|  mem_   |  |  unified    |
//        | (single  |                           | arbiter |->|  code+data  |
//        |  cycle + |  d_addr  +---------+   +->| I first |  |  LATENCY    |
//        |  stall)  |--------->| decoder |   |  +---------+  |  cycles     |
//        |          |<---------| D-cache |---+               +-------------+
//        +----------+  d_rdata | + wbuf  |--> out_port (0x400, uncached)
//                              +---------+
//
// Split level-1 caches give the core the Harvard property (fetch and data
// access in the same cycle while both hit); below them a single memory holds
// code and data, as in a von Neumann machine. The data address map is the same
// as in Phase I: RAM 0x000-0x3FF (physical +0x400), out_port 0x400, else fault.
// -----------------------------------------------------------------------------
module mh_top #(
    parameter PROG_FILE  = "",
    parameter DATA_FILE  = "",
    parameter LATENCY    = 4,     // lower-level memory access time in cycles
    parameter I_LINES    = 8,
    parameter D_LINES    = 8,
    parameter LINE_WORDS = 4,
    parameter WBUF       = 1      // D-cache write buffer on/off
) (
    input  wire        clk,
    input  wire        rst,
    output wire        halt,
    output reg  [31:0] out_port,
    // Phase I counters
    output wire [31:0] cycle_count,
    output wire [31:0] instr_count,
    output wire [31:0] d_access_count,
    output wire [31:0] simul_count,
    // Phase II hierarchy counters
    output wire [31:0] i_miss_count,      // I-cache line fills
    output wire [31:0] d_miss_count,      // D-cache line fills (read misses)
    output wire [31:0] i_stall_count,     // cycles waiting for an instruction
    output wire [31:0] d_stall_count,     // cycles waiting for a load/store
    output wire [31:0] conflict_count,    // cycles both caches wanted the memory
    output wire [31:0] wbuf_stall_count   // cycles a store waited for the write buffer
);
    // ---------------- core ----------------
    wire [31:0] i_addr, i_rdata, d_addr, d_wdata, d_rdata;
    wire        i_ready, d_ready, d_we, d_re, instr_done;

    cpu_core u_core (
        .clk       (clk),
        .rst       (rst),
        .i_addr    (i_addr),
        .i_rdata   (i_rdata),
        .i_ready   (i_ready),
        .d_addr    (d_addr),
        .d_wdata   (d_wdata),
        .d_we      (d_we),
        .d_re      (d_re),
        .d_rdata   (d_rdata),
        .d_ready   (d_ready),
        .halt      (halt),
        .instr_done(instr_done)
    );

    // ---------------- instruction side ----------------
    wire                     ic_mreq, ic_mwe, ic_mready;
    wire [31:0]              ic_maddr, ic_mwdata;
    wire [LINE_WORDS*32-1:0] rline;
    wire                     ic_hit_ev, ic_fill_ev, ic_wb_ev;

    cache #(.LINES(I_LINES), .LINE_WORDS(LINE_WORDS), .ENABLE(1), .WBUF(0)) u_icache (
        .clk(clk), .rst(rst),
        // re is constant 1, NOT ~halt: halt is decoded from i_rdata, which is only
        // valid when i_ready, so re = ~halt would form the loop
        // i_ready -> instr -> halt -> re -> i_ready (found with 1-line caches,
        // where the stale word at the missing address was an EBREAK). After
        // EBREAK the PC sits on a cached line, so no further requests are made.
        .re(1'b1), .we(1'b0), .addr(i_addr), .wdata(32'd0),
        .rdata(i_rdata), .ready(i_ready),
        .m_req(ic_mreq), .m_we(ic_mwe), .m_addr(ic_maddr), .m_wdata(ic_mwdata),
        .m_rline(rline), .m_ready(ic_mready),
        .ev_read_hit(ic_hit_ev), .ev_fill(ic_fill_ev), .ev_wbuf_stall(ic_wb_ev)
    );

    // ---------------- data side ----------------
    wire sel_ram, sel_io, addr_fault;
    addr_decoder u_dec (
        .addr(d_addr), .sel_ram(sel_ram), .sel_io(sel_io), .addr_fault(addr_fault)
    );

    wire                     dc_mreq, dc_mwe, dc_mready, dc_ready;
    wire [31:0]              dc_maddr, dc_mwdata, dc_rdata;
    wire                     dc_hit_ev, dc_fill_ev, dc_wb_ev;

    cache #(.LINES(D_LINES), .LINE_WORDS(LINE_WORDS), .ENABLE(1), .WBUF(WBUF)) u_dcache (
        .clk(clk), .rst(rst),
        .re(d_re & sel_ram), .we(d_we & sel_ram),
        .addr(d_addr + 32'h0000_0400),            // data RAM lives at physical 0x400
        .wdata(d_wdata),
        .rdata(dc_rdata), .ready(dc_ready),
        .m_req(dc_mreq), .m_we(dc_mwe), .m_addr(dc_maddr), .m_wdata(dc_mwdata),
        .m_rline(rline), .m_ready(dc_mready),
        .ev_read_hit(dc_hit_ev), .ev_fill(dc_fill_ev), .ev_wbuf_stall(dc_wb_ev)
    );

    // IO and invalid addresses never wait; only the RAM goes through the cache
    assign d_ready = sel_ram ? dc_ready : 1'b1;
    assign d_rdata = (d_re & sel_ram) ? dc_rdata : 32'h0000_0000;

    always @(posedge clk) begin
        if (rst)
            out_port <= 32'h0000_0000;
        else if (d_we & sel_io)
            out_port <= d_wdata;
    end

    wire d_fault = (d_we | d_re) & addr_fault;   // for debugging / waves

    // ---------------- shared lower level ----------------
    wire        m_req, m_we, m_ready, conflict_ev;
    wire [31:0] m_addr, m_wdata;

    mem_arbiter #(.LINE_WORDS(LINE_WORDS)) u_arb (
        .clk(clk), .rst(rst),
        .i_req(ic_mreq), .i_we(ic_mwe), .i_addr(ic_maddr), .i_wdata(ic_mwdata), .i_ready(ic_mready),
        .d_req(dc_mreq), .d_we(dc_mwe), .d_addr(dc_maddr), .d_wdata(dc_mwdata), .d_ready(dc_mready),
        .m_req(m_req), .m_we(m_we), .m_addr(m_addr), .m_wdata(m_wdata), .m_ready(m_ready),
        .ev_conflict(conflict_ev)
    );

    main_mem #(.DEPTH_WORDS(512), .LATENCY(LATENCY), .LINE_WORDS(LINE_WORDS),
               .PROG_FILE(PROG_FILE), .DATA_FILE(DATA_FILE)) u_mem (
        .clk(clk), .rst(rst),
        .req(m_req), .we(m_we), .addr(m_addr), .wdata(m_wdata),
        .rline(rline), .ready(m_ready)
    );

    // ---------------- counters ----------------
    wire d_op = d_we | d_re;

    perf_counters u_perf (
        .clk           (clk),
        .rst           (rst),
        .halt          (halt),
        .instr_done    (instr_done),
        .i_access      (~halt & i_ready),
        .d_access      (d_op & d_ready),          // completed data accesses
        .cycle_count   (cycle_count),
        .instr_count   (instr_count),
        .d_access_count(d_access_count),
        .simul_count   (simul_count)
    );

    event_counter u_c_imiss (.clk(clk), .rst(rst), .halt(halt), .ev(ic_fill_ev),              .count(i_miss_count));
    event_counter u_c_dmiss (.clk(clk), .rst(rst), .halt(halt), .ev(dc_fill_ev),              .count(d_miss_count));
    event_counter u_c_istl  (.clk(clk), .rst(rst), .halt(halt), .ev(~halt & ~i_ready),        .count(i_stall_count));
    event_counter u_c_dstl  (.clk(clk), .rst(rst), .halt(halt), .ev(i_ready & d_op & ~d_ready), .count(d_stall_count));
    event_counter u_c_conf  (.clk(clk), .rst(rst), .halt(halt), .ev(conflict_ev),             .count(conflict_count));
    event_counter u_c_wbst  (.clk(clk), .rst(rst), .halt(halt), .ev(dc_wb_ev),                .count(wbuf_stall_count));
endmodule
`default_nettype wire
