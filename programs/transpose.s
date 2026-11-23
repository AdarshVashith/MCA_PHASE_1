# transpose.s - B = transpose(A) for an 8x8 matrix, then sum one row of B.
#   A[i][j] at data word 8i+j      (words 0..63,   bytes 0x000-0x0FF), A[i][j] = 8i+j+1
#   B[j][i] at data word 64+8j+i   (words 64..127, bytes 0x100-0x1FF)
# Loads of A walk along a row (spatial locality); stores to B walk down a
# column (stride 8 words = 2 cache lines). The final loop reads row 1 of B,
# which was only written, never read: with no-write-allocate these are misses.
# Expected: B[j][i] = A[i][j], x6 = sum(A) = 2080, data word 128 = sum(B row 1)
#           = 2+10+18+...+58 = 240, out_port = 2080
        addi x10, x0, 8           # N
        addi x6, x0, 0            # checksum
        addi x1, x0, 0            # i = 0
iloop:  addi x2, x0, 0            # j = 0
jloop:  slli x3, x1, 3
        add  x3, x3, x2
        slli x3, x3, 2            # &A[i][j]
        lw   x4, 0(x3)
        slli x5, x2, 3
        add  x5, x5, x1
        slli x5, x5, 2            # &B[j][i] - 256
        sw   x4, 256(x5)
        add  x6, x6, x4
        addi x2, x2, 1
        blt  x2, x10, jloop
        addi x1, x1, 1
        blt  x1, x10, iloop
        addi x7, x0, 0            # row sum
        addi x8, x0, 288          # &B[1][0]
        addi x9, x0, 320          # &B[2][0]
rloop:  lw   x4, 0(x8)
        add  x7, x7, x4
        addi x8, x8, 4
        bne  x8, x9, rloop
        sw   x7, 512(x0)          # data word 128 = 240
        sw   x6, 1024(x0)         # out_port = 2080
        ebreak
