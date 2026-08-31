#ifndef BLADE_OS_H
#define BLADE_OS_H

#include "common_func.h"

void blade_os_hw_init(void);
void blade_os_console_putchar(char ch);
void blade_os_console_write(const char *str);
U8 blade_os_is_ready(void);
void blade_os_on_button_irq(U8 button_state);

#endif /* BLADE_OS_H */
