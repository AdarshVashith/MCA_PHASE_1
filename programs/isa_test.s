# isa_test.s - exercises every Phase II instruction once, with hand-checked results.
# Expected final state (also checked by tools/iss.py):
#   x1=0x12345678 x2=0xEDCBA987 x3=0x78 x4=0xF0 x5=0x88 x6=0x780 x7=1 x8=3
#   x9=8 x10=0xF0 x11=-5 x12=1 x13=0 x14=1 x15=7 (branch/jump path marker)
#   x16 = return address of the JAL (0x60)   x0 stays 0
#   data words 0..3 = x5, x6, x9, x15   out_port = x5+x6+x9+x10+x12+x14+x15 = 2313
        lui  x1, 0x12345          # x1 = 0x12345000
        addi x1, x1, 0x678        # x1 = 0x12345678
        xori x2, x1, -1           # x2 = ~x1 = 0xEDCBA987
        andi x3, x1, 0xFF         # x3 = 0x78
        ori  x4, x0, 0xF0         # x4 = 0xF0
        xor  x5, x3, x4           # x5 = 0x78 ^ 0xF0 = 0x88
        slli x6, x3, 4            # x6 = 0x780
        srli x7, x1, 28           # x7 = 0x1
        addi x8, x0, 3
        sll  x9, x7, x8           # x9 = 1 << 3 = 8
        srl  x10, x6, x8          # x10 = 0x780 >> 3 = 0xF0
        addi x11, x0, -5
        slt  x12, x11, x7         # -5 < 1  -> 1   (signed)
        slt  x13, x7, x11         #  1 < -5 -> 0
        slti x14, x11, -4         # -5 < -4 -> 1
        lui  x0, 0x1              # write to x0 is discarded
        addi x15, x0, 0
        blt  x11, x7, t1          # taken (-5 < 1)
        addi x15, x15, 100        # skipped
t1:     bge  x11, x7, bad         # not taken (-5 >= 1 is false)
        bge  x7, x7, t2           # taken (equal)
        addi x15, x15, 100        # skipped
t2:     addi x15, x15, 1          # x15 = 1
        jal  x16, sub             # call: x16 = address of the next instruction (0x60)
        addi x15, x15, 4          # x15 = 1 + 2 + 4 = 7
        j    done
sub:    addi x15, x15, 2
        jalr x0, 0(x16)           # return
done:   sw   x5, 0(x0)
        sw   x6, 4(x0)
        sw   x9, 8(x0)
        sw   x15, 12(x0)
        add  x20, x5, x6
        add  x20, x20, x9
        add  x20, x20, x10
        add  x20, x20, x12
        add  x20, x20, x14
        add  x20, x20, x15        # 0x88+0x780+8+0xF0+1+1+7 = 2313
        sw   x20, 1024(x0)        # out_port
        ebreak
bad:    addi x15, x0, -1
        sw   x15, 1024(x0)
        ebreak
