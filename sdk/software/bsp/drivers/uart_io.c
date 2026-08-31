#include "uart_io.h"

unsigned long __attribute__((weak)) UART_BASE = 0xbf000000UL;

static inline volatile unsigned char *uart_reg(unsigned int offset)
{
    return (volatile unsigned char *)(UART_BASE + (unsigned long)offset);
}

int uart_rx_ready(void)
{
    return ((*uart_reg(UART_REG_LSR)) & UART_LSR_DR) ? 1 : 0;
}

int uart_tx_ready(void)
{
    return ((*uart_reg(UART_REG_LSR)) & UART_LSR_THRE) ? 1 : 0;
}

int uart_getchar_blocking(void)
{
    while (!uart_rx_ready()) {
    }
    return (int)(*uart_reg(UART_REG_RBR_THR));
}

int uart_getchar_nonblocking(int *out_ch)
{
    if (!uart_rx_ready()) {
        return 0;
    }

    if (out_ch != 0) {
        *out_ch = (int)(*uart_reg(UART_REG_RBR_THR));
    } else {
        (void)(*uart_reg(UART_REG_RBR_THR));
    }
    return 1;
}

void uart_putchar_blocking(char ch)
{
    while (!uart_tx_ready()) {
    }
    *uart_reg(UART_REG_RBR_THR) = (unsigned char)ch;
}

void uart_puts_blocking(const char *str)
{
    if (str == 0) {
        return;
    }

    while (*str != '\0') {
        if (*str == '\n') {
            uart_putchar_blocking('\r');
        }
        uart_putchar_blocking(*str);
        str++;
    }
}

int uart_read_line(char *buf, int max_len)
{
    static int swallow_next_lf = 0;
    int idx = 0;
    int ch;

    if ((buf == 0) || (max_len <= 0)) {
        return 0;
    }

    while (1) {
        ch = uart_getchar_blocking();

        if (swallow_next_lf && (ch == '\n')) {
            swallow_next_lf = 0;
            continue;
        }

        if (ch == '\r') {
            swallow_next_lf = 1;
            break;
        }
        if (ch == '\n') {
            swallow_next_lf = 0;
            break;
        }

        if (idx < (max_len - 1)) {
            buf[idx++] = (char)ch;
        }
    }

    buf[idx] = '\0';
    return idx;
}
