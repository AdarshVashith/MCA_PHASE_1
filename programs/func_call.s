# func_call.s - sum of squares 1..10 with a shift-and-add multiply subroutine.
# Exercises JAL/JALR (call/return), ANDI, SLLI, SRLI, BGE. The subroutine sits
# after the main loop, so the instruction stream jumps between two code regions
# (I-cache footprint), and every iteration stores one result (write buffer).
# Expected: data words 0..9 = 1 4 9 16 25 36 49 64 81 100, x11 = 385,
#           out_port = 385
        addi x10, x0, 10          # n
        addi x11, x0, 0           # acc
        addi x12, x0, 1           # k
        addi x20, x0, 0           # table pointer
loop:   mv   x13, x12             # multiplicand
        mv   x14, x12             # multiplier
        jal  x1, mul              # x15 = k * k
        add  x11, x11, x15
        sw   x15, 0(x20)          # squares[k-1]
        addi x20, x20, 4
        addi x12, x12, 1
        bge  x10, x12, loop       # while k <= n
        sw   x11, 1024(x0)        # out_port = 385
        ebreak
mul:    addi x15, x0, 0           # product = 0
mloop:  andi x16, x14, 1
        beq  x16, x0, mskip
        add  x15, x15, x13
mskip:  slli x13, x13, 1
        srli x14, x14, 1
        bne  x14, x0, mloop
        ret
