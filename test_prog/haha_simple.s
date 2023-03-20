.section .text
.align 4
li a1, 123
li a2, 342
li a3, 43981
li sp, 2048
sw a3, 0(sp)
lw a7, 0(sp)
lw a3, 0(sp)
mul a3, a1, a2  # a3 = 42066
mul a4, a2, a1  # a4 = 42066
mul a5, a1, a2  # a5 = 42066
mul a6, a2, a1  # a6 = 42066
mul a1, a5, a6  # a1 = 1769548356 = 0x69792A44
mul a2, a1, a3  # a2 = 0x67E319C8
add a1, a3, a4  # a1 = 84132
add a2, a6, a5  # a2 = 84132
add a2, a6, a2  # a2 = 126198
mul a1, a1, a2  # a1 = 0x78D6FD98
wfi