#ifndef REGADDR_H
#define REGADDR_H

/* CONFREG (Configuration Register) Base Address */
#define CONFREG_BASE                0xbf20f000

/* Interrupt Controller Registers */
#define CONFREG_INT_EDGE           (CONFREG_BASE + 0x004)  // Interrupt edge select
#define CONFREG_INT_POL            (CONFREG_BASE + 0x008)  // Interrupt polarity
#define CONFREG_INT_CLR            (CONFREG_BASE + 0x00c)  // Interrupt clear
#define CONFREG_INT_EN             (CONFREG_BASE + 0x000)  // Interrupt enable
#define CONFREG_INT_STATE          (CONFREG_BASE + 0x014)  // Interrupt state

/* Timer Registers */
#define CONFREG_TIMER_CMP          (CONFREG_BASE + 0x104)  // Timer compare register
#define CONFREG_TIMER_EN           (CONFREG_BASE + 0x108)  // Timer enable register
#define CONFREG_SWITCH_DATA        (CONFREG_BASE + 0x400)  // DIP switch snapshot register

/* Simulation Flag Register */
#define CONFREG_SIMU_FLAG          (CONFREG_BASE + 0x500)  // Simulation flag register

#endif
