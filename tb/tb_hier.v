`default_nettype none
`timescale 1ns/1ps
// tb_hier: Phase II system test. Runs ONE program on four organisations at once:
//
//   ref : harvard_top   ideal Harvard (Phase I), the golden reference
//   mh  : mh_top        modified Harvard: split I/D caches of LINES lines each,
//                       one shared lower-level memory with LATENCY cycles
//   uc  : vnc_top       von Neumann with ONE unified cache of 2*LINES lines
//                       (same total capacity as mh), same memory
//   nc  : vnc_top       von Neumann, no cache, same memory
//
// Checks (all self-checking):
//   1. registers, the 256 data words and out_port are identical to ref on all
//      three hierarchy systems (after the write buffers have drained)
//   2. instruction counts are identical
//   3. cycle accounting: mh  cycles = instructions + I-stall + D-stall cycles
//                        uc/nc cycles = bus cycles (instr + LW/SW) + stall cycles
//   4. with LATENCY = 1 the uncached VN system is cycle-identical to Phase I vn_top
//      (cycles = instructions + LW/SW)
// Prints one "ROW," line (CSV) that tools/sweep.py collects and checks against
// the miss counts predicted by tools/iss.py.
module tb_hier;
    parameter PROG_NAME  = "basic";
    parameter PROG_FILE  = "../programs/basic.hex";
    parameter DATA_FILE  = "../programs/basic_data.hex";
    parameter LATENCY    = 4;
    parameter LINES      = 8;
    parameter LINE_WORDS = 4;
    parameter WBUF       = 1;
    parameter TIMEOUT    = 400000;
    parameter DUMP       = 0;

    reg clk = 0, rst = 1;
    always #5 clk = ~clk;

    // ---- reference: ideal Harvard ----
    wire        r_halt;
    wire [31:0] r_out, r_cyc, r_ins, r_dacc, r_sim;
    harvard_top #(.PROG_FILE(PROG_FILE), .DATA_FILE(DATA_FILE)) ref_h (
        .clk(clk), .rst(rst), .halt(r_halt), .out_port(r_out),
        .cycle_count(r_cyc), .instr_count(r_ins), .d_access_count(r_dacc), .simul_count(r_sim));

    // ---- modified Harvard ----
    wire        m_halt;
    wire [31:0] m_out, m_cyc, m_ins, m_dacc, m_sim;
    wire [31:0] m_imiss, m_dmiss, m_istl, m_dstl, m_conf, m_wbst;
    mh_top #(.PROG_FILE(PROG_FILE), .DATA_FILE(DATA_FILE), .LATENCY(LATENCY),
             .I_LINES(LINES), .D_LINES(LINES), .LINE_WORDS(LINE_WORDS), .WBUF(WBUF)) mh (
        .clk(clk), .rst(rst), .halt(m_halt), .out_port(m_out),
        .cycle_count(m_cyc), .instr_count(m_ins), .d_access_count(m_dacc), .simul_count(m_sim),
        .i_miss_count(m_imiss), .d_miss_count(m_dmiss), .i_stall_count(m_istl),
        .d_stall_count(m_dstl), .conflict_count(m_conf), .wbuf_stall_count(m_wbst));

    // ---- von Neumann + unified cache (same total capacity) ----
    wire        u_halt;
    wire [31:0] u_out, u_cyc, u_ins, u_dacc, u_sim, u_miss, u_stl, u_wbst;
    vnc_top #(.PROG_FILE(PROG_FILE), .DATA_FILE(DATA_FILE), .LATENCY(LATENCY),
              .LINES(2 * LINES), .LINE_WORDS(LINE_WORDS), .CACHE_EN(1), .WBUF(WBUF)) uc (
        .clk(clk), .rst(rst), .halt(u_halt), .out_port(u_out),
        .cycle_count(u_cyc), .instr_count(u_ins), .d_access_count(u_dacc), .simul_count(u_sim),
        .miss_count(u_miss), .stall_count(u_stl), .wbuf_stall_count(u_wbst));

    // ---- von Neumann, no cache ----
    wire        n_halt;
    wire [31:0] n_out, n_cyc, n_ins, n_dacc, n_sim, n_miss, n_stl, n_wbst;
    vnc_top #(.PROG_FILE(PROG_FILE), .DATA_FILE(DATA_FILE), .LATENCY(LATENCY),
              .LINES(2 * LINES), .LINE_WORDS(LINE_WORDS), .CACHE_EN(0), .WBUF(0)) nc (
        .clk(clk), .rst(rst), .halt(n_halt), .out_port(n_out),
        .cycle_count(n_cyc), .instr_count(n_ins), .d_access_count(n_dacc), .simul_count(n_sim),
        .miss_count(n_miss), .stall_count(n_stl), .wbuf_stall_count(n_wbst));

    integer errors = 0, cyc, n;

    task chk(input [8*48-1:0] what, input [31:0] got, input [31:0] exp);
        if (got !== exp) begin
            $display("FAIL %0s = %0d, expected %0d", what, got, exp);
            errors = errors + 1;
        end
    endtask

    initial begin
        if (DUMP) begin
            $dumpfile({"build/tb_hier_", PROG_NAME, ".vcd"});
            $dumpvars(0, tb_hier);
        end
        repeat (2) @(posedge clk);
        @(negedge clk) rst = 0;

        cyc = 0;
        while (!(r_halt && m_halt && u_halt && n_halt) && cyc < TIMEOUT) begin
            @(posedge clk); cyc = cyc + 1;
        end
        if (!(r_halt && m_halt && u_halt && n_halt)) begin
            $display("FAIL timeout: ref=%b mh=%b uc=%b nc=%b", r_halt, m_halt, u_halt, n_halt);
            errors = errors + 1;
        end
        repeat (4 * LATENCY + 10) @(posedge clk);     // let the write buffers drain
        #1;

        // 1. architectural state
        for (n = 0; n < 32; n = n + 1) begin
            chk("mh reg", mh.u_core.u_regfile.regs[n], ref_h.u_core.u_regfile.regs[n]);
            chk("uc reg", uc.u_core.u_regfile.regs[n], ref_h.u_core.u_regfile.regs[n]);
            chk("nc reg", nc.u_core.u_regfile.regs[n], ref_h.u_core.u_regfile.regs[n]);
        end
        for (n = 0; n < 256; n = n + 1) begin
            chk("mh data", mh.u_mem.mem[256 + n], ref_h.u_mem.u_dmem.mem[n]);
            chk("uc data", uc.u_mem.mem[256 + n], ref_h.u_mem.u_dmem.mem[n]);
            chk("nc data", nc.u_mem.mem[256 + n], ref_h.u_mem.u_dmem.mem[n]);
        end
        chk("mh out_port", m_out, r_out);
        chk("uc out_port", u_out, r_out);
        chk("nc out_port", n_out, r_out);

        // 2. same instruction stream
        chk("mh instr_count", m_ins, r_ins);
        chk("uc instr_count", u_ins, r_ins);
        chk("nc instr_count", n_ins, r_ins);
        chk("mh d_access_count", m_dacc, r_dacc);

        // 3. cycle accounting
        chk("mh cycles = instr + I-stall + D-stall", m_cyc, m_ins + m_istl + m_dstl);
        chk("uc cycles = instr + LS + stall", u_cyc, u_ins + r_dacc + u_stl);
        chk("nc cycles = instr + LS + stall", n_cyc, n_ins + r_dacc + n_stl);

        // 4. Phase I equivalence at LATENCY = 1
        if (LATENCY == 1)
            chk("nc (L=1) == Phase I vn_top cycles", n_cyc, r_ins + r_dacc);

        // prog,L,lines,line_words,wbuf,instr,ls,ideal_h,ideal_vn,
        // mh_cyc,mh_imiss,mh_dmiss,mh_istall,mh_dstall,mh_conflict,mh_wbstall,mh_simul,
        // uc_cyc,uc_miss,uc_stall,uc_wbstall,nc_cyc
        $display("ROW,%0s,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",
                 PROG_NAME, LATENCY, LINES, LINE_WORDS, WBUF, r_ins, r_dacc, r_cyc, r_ins + r_dacc,
                 m_cyc, m_imiss, m_dmiss, m_istl, m_dstl, m_conf, m_wbst, m_sim,
                 u_cyc, u_miss, u_stl, u_wbst, n_cyc);
        if (errors == 0) $display("tb_hier(%0s L=%0d lines=%0d wbuf=%0d): PASS", PROG_NAME, LATENCY, LINES, WBUF);
        else             $display("tb_hier(%0s L=%0d lines=%0d wbuf=%0d): FAIL (%0d errors)", PROG_NAME, LATENCY, LINES, WBUF, errors);
        $finish;
    end
endmodule
`default_nettype wire
