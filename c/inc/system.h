#ifndef _SYSTEM_H
#define _SYSTEM_H

#include <stdint.h>

typedef unsigned int uint32;
typedef int int32;

#define LCPU_BASE 0x80000000
#define LCPU_REGS ((volatile Lcpu_Registers *)LCPU_BASE)

// 工作用的 struct (对齐 fpga_cpu-master)
typedef struct str_my_reg {
    uint32 fpga_build_date;
    uint32 fpga_build_time;
    uint32 sw_build_date;
    uint32 sw_build_time;
    uint32 scratch[12];
    uint32 led_0;
} str_my_reg;

typedef struct Lcpu_Registers {
    struct str_my_reg my_reg;
} Lcpu_Registers;

void program_main(void);
void designInit(void);
void designApp(void);

// Network stack (in netstack.c)
void net_init(void);
void net_poll(void);

#endif
