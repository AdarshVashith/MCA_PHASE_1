// expected.vh - expected final state of each test program, shared by
// tb_harvard_top and tb_vn_top. The including testbench defines:
//   `REG(n)   -> register n of its DUT
//   `DMEM(n)  -> data word n of its DUT
// and has: parameter PROG_NAME, integer errors, wire [31:0] out_port,
// and task chk(input [8*24-1:0] what, input [31:0] got, input [31:0] exp).
//
// exp_instr / exp_daccess are the hand-counted dynamic instruction count and
// number of LW/SW executed, used to check the cycle counts.

integer exp_instr, exp_daccess;
integer k;

task check_program;
    begin
        exp_instr = -1; exp_daccess = -1;
        if (PROG_NAME == "basic") begin
            exp_instr = 19; exp_daccess = 7;
            chk("x1",  `REG(1),  5);
            chk("x2",  `REG(2),  7);
            chk("x3",  `REG(3),  12);
            chk("x4",  `REG(4),  2);
            chk("x5",  `REG(5),  5);
            chk("x6",  `REG(6),  7);
            chk("x7",  `REG(7),  12);
            chk("x8",  `REG(8),  0);
            chk("x9",  `REG(9),  32'hFFFF_FFFF);
            chk("x10", `REG(10), 0);
            chk("x11", `REG(11), 0);
            chk("x12", `REG(12), 32'h800);
            chk("mem[0]", `DMEM(0), 12);
            chk("mem[1]", `DMEM(1), 32'hFFFF_FFFF);
            chk("out_port", out_port, 12);
        end else if (PROG_NAME == "array_sum") begin
            exp_instr = 38; exp_daccess = 10;
            chk("x3", `REG(3), 31);
            chk("mem[8]", `DMEM(8), 31);
            chk("out_port", out_port, 31);
        end else if (PROG_NAME == "memcopy") begin
            exp_instr = 54; exp_daccess = 17;
            for (k = 0; k < 8; k = k + 1)
                chk("copy", `DMEM(16 + k), 10 * (k + 1));
            chk("x5", `REG(5), 360);
            chk("out_port", out_port, 360);
        end else if (PROG_NAME == "count_loop") begin
            exp_instr = 64; exp_daccess = 1;
            chk("x1", `REG(1), 0);
            chk("x2", `REG(2), 210);
            chk("out_port", out_port, 210);
        end else if (PROG_NAME == "isa_test") begin
            exp_instr = 38; exp_daccess = 5;
            chk("x1 lui+addi", `REG(1),  32'h1234_5678);
            chk("x2 xori",     `REG(2),  32'hEDCB_A987);
            chk("x3 andi",     `REG(3),  32'h78);
            chk("x4 ori",      `REG(4),  32'hF0);
            chk("x5 xor",      `REG(5),  32'h88);
            chk("x6 slli",     `REG(6),  32'h780);
            chk("x7 srli",     `REG(7),  1);
            chk("x9 sll",      `REG(9),  8);
            chk("x10 srl",     `REG(10), 32'hF0);
            chk("x11",         `REG(11), 32'hFFFF_FFFB);
            chk("x12 slt",     `REG(12), 1);
            chk("x13 slt",     `REG(13), 0);
            chk("x14 slti",    `REG(14), 1);
            chk("x15 br/jmp",  `REG(15), 7);
            chk("x16 jal link",`REG(16), 32'h60);
            chk("x0",          `REG(0),  0);
            chk("mem[0]", `DMEM(0), 32'h88);
            chk("mem[3]", `DMEM(3), 7);
            chk("out_port", out_port, 2313);
        end else if (PROG_NAME == "bubble_sort") begin
            exp_instr = 826; exp_daccess = 369;
            chk("sorted[0]",  `DMEM(0),  -15);
            chk("sorted[1]",  `DMEM(1),  -8);
            chk("sorted[2]",  `DMEM(2),  -4);
            chk("sorted[3]",  `DMEM(3),  -1);
            chk("sorted[4]",  `DMEM(4),  0);
            chk("sorted[5]",  `DMEM(5),  3);
            chk("sorted[6]",  `DMEM(6),  5);
            chk("sorted[7]",  `DMEM(7),  8);
            chk("sorted[8]",  `DMEM(8),  9);
            chk("sorted[9]",  `DMEM(9),  12);
            chk("sorted[10]", `DMEM(10), 17);
            chk("sorted[11]", `DMEM(11), 23);
            chk("sorted[12]", `DMEM(12), 27);
            chk("sorted[13]", `DMEM(13), 31);
            chk("sorted[14]", `DMEM(14), 42);
            chk("sorted[15]", `DMEM(15), 50);
            chk("out_port", out_port, 13041);
        end else if (PROG_NAME == "func_call") begin
            exp_instr = 268; exp_daccess = 11;
            for (k = 0; k < 10; k = k + 1)
                chk("square", `DMEM(k), (k + 1) * (k + 1));
            chk("x11", `REG(11), 385);
            chk("out_port", out_port, 385);
        end else if (PROG_NAME == "transpose") begin
            exp_instr = 769; exp_daccess = 138;
            for (k = 0; k < 64; k = k + 1)
                chk("B[j][i]", `DMEM(64 + 8 * (k % 8) + k / 8), k + 1);
            chk("row sum", `DMEM(128), 240);
            chk("x6", `REG(6), 2080);
            chk("out_port", out_port, 2080);
        end else begin
            $display("NOTE: no expected values for program '%0s', only counters checked", PROG_NAME);
        end
    end
endtask
