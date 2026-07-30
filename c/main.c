#include "inc/system.h"

__attribute__((naked, used, section(".text.bootloader"))) void reset_entry() {
    asm volatile("j program_main\n");
}

int main() {
    program_main();
    return 0;
}

void program_main() {
    designInit();
    while (1) {
        designApp();
    }
}
