# bubble_sort.s - sort 16 signed words in place (data words 0..15), ascending.
# Memory-heavy with strong temporal locality: the same 16 words are read and
# written again on every pass. Uses BLT/BGE (signed) and SLLI.
# Data image: 23 -4 17 8 42 0 -15 31 5 12 -1 27 9 3 50 -8
# Expected: words 0..15 = -15 -8 -4 -1 0 3 5 8 9 12 17 23 27 31 42 50
#           out_port = (max << 8) | (min & 0xFF) = (50 << 8) | 0xF1 = 13041
        addi x10, x0, 16          # n
        addi x11, x0, 15          # n - 1
        addi x1, x0, 0            # i = 0
outer:  addi x2, x0, 0            # j (byte offset) = 0
        sub  x3, x10, x1
        addi x3, x3, -1           # comparisons this pass = n - i - 1 (>= 1)
        slli x3, x3, 2            # ... in bytes
inner:  lw   x4, 0(x2)            # a[j]
        lw   x5, 4(x2)            # a[j+1]
        bge  x5, x4, noswap       # already in order
        sw   x5, 0(x2)            # swap
        sw   x4, 4(x2)
noswap: addi x2, x2, 4
        blt  x2, x3, inner
        addi x1, x1, 1
        blt  x1, x11, outer
        lw   x6, 0(x0)            # min
        lw   x7, 60(x0)           # max
        andi x6, x6, 0xFF
        slli x7, x7, 8
        or   x8, x7, x6
        sw   x8, 1024(x0)         # out_port
        ebreak
