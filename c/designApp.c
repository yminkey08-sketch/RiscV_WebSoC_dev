#include "system.h"

#define BUILD_DATE  0x20260728
#define BUILD_TIME  0x00000001

void designInit() {
    LCPU_REGS->my_reg.sw_build_date = BUILD_DATE;
    LCPU_REGS->my_reg.sw_build_time = BUILD_TIME;
    LCPU_REGS->my_reg.led_0 = 0x0;
    net_init();  // MDIO + PHY init
}

void designApp() {
    net_poll();  // handle incoming packets
}
