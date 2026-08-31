#ifndef UART_IO_H
#define UART_IO_H

/*
 * UART 16550 register offsets.
 * DLAB=0: 0x0 is RBR/THR
 */
#define UART_REG_RBR_THR 0x0
#define UART_REG_LSR     0x5

/* LSR bits */
#define UART_LSR_DR      0x01
#define UART_LSR_THRE    0x20

int uart_rx_ready(void);
int uart_tx_ready(void);

int uart_getchar_blocking(void);
int uart_getchar_nonblocking(int *out_ch);

void uart_putchar_blocking(char ch);
void uart_puts_blocking(const char *str);

/*
 * Read one line from UART.
 * '\r', '\n', or "\r\n" ends a line; line ending is not kept in buffer.
 */
int uart_read_line(char *buf, int max_len);

#endif
