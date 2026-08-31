#include "terminal_display.h"

#include "blade_os.h"

void terminal_display_init(void)
{
    blade_os_hw_init();
}

void terminal_display_write(const char *str)
{
    blade_os_console_write(str);
}

void terminal_display_putchar(char ch)
{
    blade_os_console_putchar(ch);
}

U8 terminal_display_is_ready(void)
{
    return blade_os_is_ready();
}

void terminal_display_on_button_irq(U8 button_state)
{
    blade_os_on_button_irq(button_state);
}
