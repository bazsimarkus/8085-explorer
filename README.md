# 8085-explorer

A Netronics Explorer/85 compatible Intel 8085 single board computer that runs the original Microsoft ROM BASIC v4.7 and the original Netronics Explorer/85 monitor ROM. Software compatible with the 1979 original, built from a minimal number of through-hole chips, and easy to assemble.

![8085 Explorer](/docs/images/8085-explorer-1.jpg)

---

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Getting Started](#getting-started)
  - [What You Need](#what-you-need)
  - [Flashing the ROM](#flashing-the-rom)
  - [Connecting](#connecting)
  - [Starting BASIC](#starting-basic)
- [Schematic](#schematic)
- [How It Works](#how-it-works)
  - [Address Bus Demultiplexing](#address-bus-demultiplexing)
  - [Memory Map](#memory-map)
  - [The Boot Problem and the Glue Logic](#the-boot-problem-and-the-glue-logic)
  - [Serial Communication](#serial-communication)
- [Documentation](#documentation)
- [Acknowledgments](#acknowledgments)
- [License](#license)

---

## Overview

The 8085 Explorer is a single board computer built around the Intel 8085 microprocessor. It is software compatible with the original Netronics Explorer/85 from 1979 and runs the same monitor ROM and Microsoft BASIC that shipped with the original kit. The board uses a small number of readily available through-hole chips and communicates through an RS232 serial port. Connect it to a terminal emulator like Tera Term and you have a working retro computer that boots into a machine language monitor and can run BASIC programs interactively.

![8085 Explorer Top View](/docs/images/8085-explorer-2.jpg)

The design was inspired by Tom Nisbet's [Simple8085](https://github.com/TomNisbet/Simple8085). I used his [TommyPROM](https://github.com/TomNisbet/TommyPROM) programmer to flash the ROM image onto the 28C256 EEPROM.

---

## Features

- Intel 8085 CPU running at 3.072 MHz (6.144 MHz crystal divided by 2)
- 32K ROM (28C256 EEPROM) containing the Netronics monitor and Microsoft BASIC
- 32K Static RAM (HM62256BLP)
- RS232 serial port via MAX232 level converter and DB9 connector
- Bit-banged serial I/O using the 8085's SID and SOD pins
- Original Netronics Explorer/85 monitor ROM v1.4
- Microsoft ROM BASIC v4.7 (Copyright 1978 by Microsoft)
- Minimal chip count, all through-hole, easy to build on a soldering iron
- 9V DC barrel jack power input with L7805 5V regulator
- Power on reset with manual reset button
- Power LED, serial RX and TX activity LEDs
- Expansion header and SID/SOD pin headers
- Designed in KiCad, full schematic and PCB files included

---

## Getting Started

### What You Need

- The assembled 8085 Explorer board
- A 9V DC power supply (center positive, 2.1mm barrel jack)
- A DB9 serial cable or USB-to-RS232 adapter
- A terminal emulator (Tera Term, PuTTY, minicom, etc.)
- An EEPROM programmer for flashing the 28C256 (e.g. [TommyPROM](https://github.com/TomNisbet/TommyPROM))

### Flashing the ROM

The file `assets/8085-explorer-rom-image.bin` contains the combined ROM image with both the Netronics monitor and Microsoft BASIC. Flash this file onto a 28C256 EEPROM using your programmer of choice.

### Connecting

1. Configure your terminal emulator for **9600 baud, 8 data bits, no parity, 1 stop bit (9600 8N1)**.
2. Connect the serial cable between the board's DB9 port and your computer.
3. Flip the power switch on.
4. Press the Space key once. The monitor ROM uses this first character to auto-detect the baud rate. Nothing will appear on screen until you do this.

After pressing Space, you should see the Explorer/85 monitor banner:

```
EXPLORER-85    VER 1.4
Copyright 1979
Netronics R&D
New Milford, CT.
```

### Starting BASIC

From the monitor prompt, configure the memory map and jump to BASIC:

```
.XS 44FF-7800 FFFF-C000
.G
```

BASIC will ask for memory size and terminal width. Press Enter to accept the defaults, or type values:

```
Memory size? 30000
Terminal width? 72
Microsoft ROM BASIC Ver 4.7
Copyright (C) 1978 by Microsoft
29443 Bytes free
Ok
```

You are now in BASIC and can write and run programs interactively.

Note: In my experience there is no whitespace between a monitor command and its parameter. For example, `GC000` starts BASIC (jumps to address C000h), not `G C000`.

![Tera Term running BASIC on the 8085 Explorer](/docs/images/8085-explorer-terminal.png)

---

## Schematic

![8085 Explorer Schematic](/docs/images/8085-explorer-schematic.jpg)

The full KiCad project files (schematic, PCB layout, and project file) are in the `schematic/` directory.

---

## How It Works

The 8085 Explorer uses a small amount of glue logic to decode memory addresses and manage access to the ROM and RAM chips. If you are new to computer hardware, the following sections explain every piece of the design.

### Address Bus Demultiplexing

The 8085 multiplexes the lower 8 bits of the address bus (A0 to A7) with the data bus (D0 to D7) on the same physical pins. A 74LS573 octal latch (U2) captures the lower address bits when the ALE (Address Latch Enable) signal goes high. After the latch captures them, the bus is free to carry data. This gives us a full 16-bit address bus separated from the 8-bit data bus.

### Memory Map

Once the boot sequence is complete (see below), the memory is split into two halves using address line A15:

- `0000h` to `7FFFh` : 32K RAM (HM62256BLP)
- `8000h` to `FFFFh` : 32K ROM (28C256 EEPROM)

When A15 is low, RAM is selected. When A15 is high, ROM is selected. The monitor lives at F800h and Microsoft BASIC starts at C000h, both in the upper ROM half.

### The Boot Problem and the Glue Logic

If you are a beginner, your first instinct might be: just wire A15 directly to the chip enable pins, select ROM when A15 is high, select RAM when A15 is low. That would work for normal operation. But it creates a problem at startup.

When the 8085 resets, it always fetches its first instruction from address 0000h. If RAM is at 0000h, the CPU reads random garbage from the uninitialized RAM and crashes immediately. The CPU must see ROM at address 0000h when it first powers on.

But we cannot permanently place ROM at 0000h either. Microsoft BASIC and other 8080/8085 software assume that RAM starts at address 0000h. They use the lowest addresses for the stack, variables, and hardware interrupt vectors. If ROM occupied the bottom of memory permanently, BASIC would try to write its variables into ROM and fail.

So we have two conflicting requirements:
1. ROM must be at 0000h at power-on so the CPU can boot.
2. RAM must be at 0000h during normal operation so software works correctly.

The glue logic on this board solves this with a temporary override at reset.

**The Reset Condition Flip-Flop (U7, 74LS74)**

A 74LS74 D flip-flop acts as a one-bit "boot mode" flag. When the CPU resets, its RESET_OUT signal clocks the flip-flop, forcing its Q output high. As long as Q is high, the system is in boot mode.

**Boot Mode Behavior (U6, 74LS32 OR gates and U5, 74LS14 inverters)**

The OR gates enforce this rule: ROM is selected if the flip-flop is set OR if A15 is high. RAM is selected only when neither condition is true. The IO/M signal from the CPU disables both memory chips during I/O operations.

So at power-on, with the flip-flop set, the logic forces ROM to be active regardless of A15. The CPU asks for address 0000h and gets ROM. The first instruction in the ROM image is a jump to address F800h (where the monitor actually lives in the upper half of memory).

**Exiting Boot Mode**

When the CPU executes that jump and reads from the upper memory (A15 goes high), the logic detects a read operation with A15 high and clears the flip-flop. Boot mode ends. From this point forward, A15 alone controls memory selection: low for RAM, high for ROM.

Because the CPU is already executing code in the ROM at F800h, it does not notice that the bottom 32K just switched from ROM to RAM. The memory map is now in its normal configuration. When you later type `GC000` to start BASIC, BASIC wakes up, scans the lower memory, finds 32K of RAM starting at 0000h, and uses it for your programs and variables.

Without these few logic gates and the flip-flop, classic 8085 software like Microsoft BASIC simply would not work on this board.

### Serial Communication

Serial communication is handled through the 8085's built-in SID (Serial Input Data) and SOD (Serial Output Data) pins. The monitor ROM implements a bit-banged UART in software. A MAX232 chip (U8) converts the TTL level signals to proper RS232 voltage levels for the DB9 connector.

The monitor does not use a fixed baud rate. Instead, after reset it waits for you to press the Space key and measures the timing of that character to auto-detect the baud rate. This means the board works at whatever speed your terminal is configured for. I use 9600 bps.

---

## Documentation

The `docs/netronics-explorer-85/` directory contains scanned original documentation and photos from the Netronics Explorer/85:

- Original manual pages (Netronics_Explorer85_A through E)
- Terminal ROM user information
- Cabinet assembly instructions and photos
- Original ROM images for the monitor (`explorer_monitor_rom/EXPLORER.HEX`) and BASIC (`explorer_basic_roms/C000.HEX` through `D800.HEX`) as separate files matching the smaller ROM chips used in the original hardware

---

## Acknowledgments

- Tom Nisbet for [Simple8085](https://github.com/TomNisbet/Simple8085), which was the main inspiration for this project, and for [TommyPROM](https://github.com/TomNisbet/TommyPROM), which I used to program the EEPROM
- Netronics R&D for the original Explorer/85 design and monitor ROM
- Microsoft for ROM BASIC v4.7

---

## License

The original Netronics monitor ROM and Microsoft BASIC ROM images are included for educational and preservation purposes.
