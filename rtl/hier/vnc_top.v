`default_nettype none
`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// vnc_top : VON NEUMANN system with a memory hierarchy (Phase II)
//
//   +-------------+  m_addr  +-------------------+         +------------+
//   |             |--------->| decoder (data)    |         |            |
//   | cpu_core_vn |<---------|   +-------------+ |  m_req  |  main_mem  |
//   | FETCH_EXEC/ | m_rdata  |   | unified     | |-------->|  unified   |
//   |  MEM FSM    |--------->|   | cache       | |<--------|  LATENCY   |
//   |  + stall    | m_we/re  |   | (+ wbuf)    | |  rline  |  cycles    |
//   +-------------+          |   +-------------+ |         +------------+
//                            +-------------------+--> out_port (uncached)
//
// One bus from the core, one cache for both code and data, one memory.
//   CACHE_EN = 1 : unified level-1 cache of LINES lines (compare with split
//                  I/D caches of the same total size in mh_top)
//   CACHE_EN = 0 : no cache, every fetch and data access pays the memory
//                  latency (with LATENCY = 1 this is exactly Phase I vn_top)
// Same address map and translation as vn_top.
// -----------------------------------------------------------------------------
module vnc_top #(
    parameter PROG_FILE  = "",
    parameter DATA_FILE  = "",
    parameter LATENCY    = 4,
    parameter LINES      = 16,
    parameter LINE_WORDS = 4,
    parameter CACHE_EN   = 1,
    parameter WBUF       = 1
) (
    input  wire        clk,
    input  wire        rst,
    output wire        halt,
    output reg  [31:0] out_port,
    output wire [31:0] cycle_count,
    output wire [31:0] instr_count,
    output wire [31:0] d_access_count,
    output wire [31:0] simul_count,
    output wire [31:0] miss_count,        // unified-cache line fills
    output wire [31:0] stall_count,       // cycles the core waited for the bus
    output wire [31:0] wbuf_stall_count
);
    wire [31:0] m_addr, m_wdata, m_rdata;
    wire        m_we, m_re, m_is_data, m_ready, instr_done;
    wire        sel_ram, sel_io, addr_fault;

    cpu_core_vn u_core (
        .clk       (clk),
        .rst       (rst),
        .m_addr    (m_addr),
        .m_wdata   (m_wdata),
        .m_we      (m_we),
        .m_re      (m_re),
        .m_is_data (m_is_data),
        .m_rdata   (m_rdata),
        .m_ready   (m_ready),
        .halt      (halt),
        .instr_done(instr_done)
    );

    addr_decoder u_dec (
        .addr(m_addr), .sel_ram(sel_ram), .sel_io(sel_io), .addr_fault(addr_fault)
    );

    // which bus cycles go to the cache: every fetch, and data accesses to RAM
    wire to_mem    = ~m_is_data | sel_ram;
    wire [31:0] phys_addr = m_is_data ? (m_addr + 32'h0000_0400) : m_addr;

    wire                     uc_ready, mreq, mwe, mready;
    wire [31:0]              uc_rdata, maddr, mwdata;
    wire [LINE_WORDS*32-1:0] rline;
    wire                     hit_ev, fill_ev, wb_ev;

    // with the cache off, stores also go straight to memory (no buffer), so
    // LATENCY = 1 / CACHE_EN = 0 reproduces vn_top cycle for cycle
    cache #(.LINES(LINES), .LINE_WORDS(LINE_WORDS), .ENABLE(CACHE_EN),
            .WBUF(CACHE_EN ? WBUF : 0)) u_ucache (
        .clk(clk), .rst(rst),
        .re(m_re & to_mem), .we(m_we & to_mem),
        .addr(phys_addr), .wdata(m_wdata),
        .rdata(uc_rdata), .ready(uc_ready),
        .m_req(mreq), .m_we(mwe), .m_addr(maddr), .m_wdata(mwdata),
        .m_rline(rline), .m_ready(mready),
        .ev_read_hit(hit_ev), .ev_fill(fill_ev), .ev_wbuf_stall(wb_ev)
    );

    main_mem #(.DEPTH_WORDS(512), .LATENCY(LATENCY), .LINE_WORDS(LINE_WORDS),
               .PROG_FILE(PROG_FILE), .DATA_FILE(DATA_FILE)) u_mem (
        .clk(clk), .rst(rst),
        .req(mreq), .we(mwe), .addr(maddr), .wdata(mwdata),
        .rline(rline), .ready(mready)
    );

    assign m_ready = to_mem ? uc_ready : 1'b1;
    assign m_rdata = ~m_is_data              ? uc_rdata :
                     (m_re & sel_ram)        ? uc_rdata : 32'h0000_0000;

    always @(posedge clk) begin
        if (rst)
            out_port <= 32'h0000_0000;
        else if (m_is_data & m_we & sel_io)
            out_port <= m_wdata;
    end

    wire d_fault = m_is_data & (m_we | m_re) & addr_fault;   // for debugging / waves

    perf_counters u_perf (
        .clk           (clk),
        .rst           (rst),
        .halt          (halt),
        .instr_done    (instr_done),
        .i_access      (~m_is_data & m_re & m_ready),
        .d_access      (m_is_data & (m_we | m_re) & m_ready),
        .cycle_count   (cycle_count),
        .instr_count   (instr_count),
        .d_access_count(d_access_count),
        .simul_count   (simul_count)
    );

    event_counter u_c_miss (.clk(clk), .rst(rst), .halt(halt), .ev(fill_ev),                     .count(miss_count));
    event_counter u_c_stl  (.clk(clk), .rst(rst), .halt(halt), .ev(~halt & (m_re | m_we) & ~m_ready), .count(stall_count));
    event_counter u_c_wbst (.clk(clk), .rst(rst), .halt(halt), .ev(wb_ev),                       .count(wbuf_stall_count));
endmodule
`default_nettype wire
