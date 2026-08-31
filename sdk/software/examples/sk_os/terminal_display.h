#ifndef TERMINAL_DISPLAY_H
#define TERMINAL_DISPLAY_H

#include "common_func.h"

void terminal_display_init(void);
void terminal_display_write(const char *str);
void terminal_display_putchar(char ch);
U8 terminal_display_is_ready(void);
void terminal_display_on_button_irq(U8 button_state);

#endif /* TERMINAL_DISPLAY_H */
