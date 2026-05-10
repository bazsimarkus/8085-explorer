# 8085-explorer

A Netronics Explorer/85 compatible Intel 8085 single board computer that runs the original Microsoft ROM BASIC v4.7, the original Netronics Explorer/85 monitor ROM, and a custom MicroPython interpreter written entirely in 8085 assembly. Software compatible with the 1979 original, built from a minimal number of through-hole chips, and easy to assemble.

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
- [MicroPython Interpreter](#micropython-interpreter)
  - [About](#about)
  - [Running MicroPython](#running-micropython)
  - [MicroPython Features](#micropython-features)
  - [Building from Source](#building-from-source)
- [Examples](#examples)
  - [Microsoft BASIC Examples](#microsoft-basic-examples)
  - [MicroPython Examples](#micropython-examples)
  - [Assembly Examples](#assembly-examples)
- [Schematic](#schematic)
  - [Bill of Materials](#bill-of-materials)
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

In addition to the classic Microsoft BASIC environment, the board can also run a custom MicroPython interpreter written from scratch in 8085 assembly. Flash a different ROM image and the board boots into a Python-like interactive shell instead.

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
- Custom MicroPython interpreter (written in 8085 assembly, runs from a separate ROM image)
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

The file `assets/msbasic47-rom-image.bin` contains the combined ROM image with both the Netronics monitor and Microsoft BASIC. Flash this file onto a 28C256 EEPROM using your programmer of choice.

Alternatively, flash `assets/micropython85/micropython85-rom-image.bin` to run the MicroPython interpreter instead.

### Connecting

1. Configure your terminal emulator for **9600 baud, 8 data bits, no parity, 1 stop bit (9600 8N1)**.
2. Connect the serial cable between the board's DB9 port and your computer.
3. Flip the power switch on.
4. If using the Microsoft BASIC ROM: press the Space key once. The monitor ROM uses this first character to auto-detect the baud rate. Nothing will appear on screen until you do this.
5. If using the MicroPython ROM: the interpreter boots directly and presents a `>>>` prompt.

After pressing Space (with the BASIC ROM), you should see the Explorer/85 monitor banner:

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

## MicroPython Interpreter

### About

The MicroPython interpreter is a minimal Python-like environment written entirely in 8085 assembly. It is not a port of the official MicroPython project. It is a from-scratch implementation that provides a familiar interactive experience on an 8-bit processor with no operating system.

The interpreter lives in a separate ROM image. You swap between Microsoft BASIC and MicroPython by flashing a different binary onto the 28C256.

### Running MicroPython

Flash `assets/micropython85/micropython85-rom-image.bin` onto your 28C256, insert the chip, and power on. The board boots directly into the REPL:

```
8085-Explorer Booting...
Memory Swap Successful: ROM@8000, RAM@0000
Booting MicroPython v1.20.0-8085 on 2026-05-10; 8085-Explorer with i8085
Type "help()" for more information.

>>> print("Hello world!")
Hello world!
>>>
```

![MicroPython running on the 8085 Explorer](/docs/images/8085-explorer-micropython-screenshot.png)

### MicroPython Features

- Interactive REPL with `>>>` prompt and `...` continuation for blocks
- 26 variables (a through z), each a 16-bit signed integer
- Arithmetic: `+` `-` `*` `/` `//` `**` `%`
- Comparisons: `>` `<` `>=` `<=` `==` `!=`
- `print()` with string literals and numeric expressions, comma-separated
- `if/else` blocks with indentation
- `for i in range(n)` and `for i in range(start, stop)` loops
- `help()` built-in
- Comments with `#`
- Error reporting: `SyntaxError` and `ZeroDivisionError`

### Building from Source

The full source is at `assets/micropython85/micropython85.asm`. Assemble it with [Tom Nisbet's asm85](https://github.com/TomNisbet/asm85):

```
asm85 -b 8000:ffff micropython85.asm
```

This produces the binary ROM image ready for flashing.

---

## Examples

The `examples/` directory contains programs for the three levels of the system.

### Microsoft BASIC Examples

Located in `examples/basic/`. These programs are typed in (or pasted) at the `Ok` prompt when the board is running the Microsoft ROM BASIC image.

### MicroPython Examples

Located in `examples/micropython/`. These scripts are typed in (or pasted) at the `>>>` prompt when the board is running the MicroPython interpreter ROM image.

### Assembly Examples

Located in `examples/assembly/`. These are standalone 8085 assembly programs that get assembled with [asm85](https://github.com/TomNisbet/asm85) and flashed directly onto the 28C256. Unlike the BASIC and MicroPython examples (which run inside their respective interpreters), assembly programs replace the entire ROM content and run on bare hardware.

To build and flash:

```
asm85 -b 8000:ffff yourprogram.asm
```

Then program the resulting binary onto a 28C256 EEPROM.

---

## Schematic

![8085 Explorer Schematic](/docs/images/8085-explorer-schematic.jpg)

The full KiCad project files (schematic, PCB layout, and project file) are in the `schematic/` directory.

### Bill of Materials

The following table lists all components needed to build one complete 8085 Explorer board.

#### PCB

| Ref | Qty | Description |
|-----|-----|-------------|
| - | 1 | 8085 Explorer v1.0 PCB |

#### Integrated Circuits

| Ref | Qty | Value | Package |
|-----|-----|-------|---------|
| U1 | 1 | 8085 | DIP-40 |
| U2 | 1 | 74LS573 | DIP-20 |
| U3 | 1 | 28C256 EEPROM | DIP-28 |
| U4 | 1 | HM62256BLP SRAM | DIP-28 |
| U5 | 1 | 74LS14 | DIP-14 |
| U6 | 1 | 74LS32 | DIP-14 |
| U7 | 1 | 74LS74 | DIP-14 |
| U8 | 1 | MAX232 | DIP-16 |
| U9 | 1 | L7805 voltage regulator | TO-220 |

#### IC Sockets

| Qty | Description |
|-----|-------------|
| 1 | 40-pin DIP socket (for U1) |
| 1 | 20-pin DIP socket (for U2) |
| 2 | 28-pin DIP socket (for U3, U4) |
| 3 | 14-pin DIP socket (for U5, U6, U7) |
| 1 | 16-pin DIP socket (for U8) |

#### Capacitors

| Ref | Qty | Value | Type |
|-----|-----|-------|------|
| C1-C7, C17 | 7 | 100nF | Ceramic |
| C8 | 1 | 22pF | Ceramic |
| C9 | 1 | 47uF | Electrolytic |
| C10-C14 | 5 | 1uF | Electrolytic |
| C15, C18 | 2 | 10uF | Electrolytic |
| C16 | 1 | 330nF | Ceramic |

#### Resistors

| Ref | Qty | Value |
|-----|-----|-------|
| R1, R2, R6 | 3 | 1k |
| R3, R4, R5 | 3 | 10k |

#### Diodes & LEDs

| Ref | Qty | Value |
|-----|-----|-------|
| D1 | 1 | LED 5mm Yellow |
| D2 | 1 | LED 5mm Green |
| D3, D5 | 2 | 1N4001 |
| D4 | 1 | LED 5mm Red |

#### Crystal

| Ref | Qty | Value |
|-----|-----|-------|
| Y1 | 1 | 6.144 MHz (HC49-U) |

#### Connectors & Switches

| Ref | Qty | Description |
|-----|-----|-------------|
| J1 | 1 | DB9 female connector (DE9, right-angle PCB mount) |
| J2 | 1 | DC-005 barrel jack (2.1mm center positive) |
| J4, J5 | 2 | 1x2 pin header (2.54mm) |
| J6 | 1 | 2x5 pin socket (2.54mm, expansion header) |
| S1 | 1 | Tactile push button 6x6mm (reset) |
| S2 | 1 | Toggle switch 7x7mm (power) |

#### Thermal Management

| Qty | Description |
|-----|-------------|
| 1 | Heatsink for TO-220 (for L7805 U9) |

#### External / Off-Board Items

| Qty | Description |
|-----|-------------|
| 1 | 9V DC power supply (center positive, 2.1mm barrel jack) |
| 1 | RS-232 to USB cable (DB9 male to USB-A) |
| 4 | Rubber feet, 3M SJ61A6 |

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

The MicroPython interpreter ROM uses its own bit-banged serial routines hardcoded to 9600 baud (tuned for the 6.144 MHz crystal). It does not require a Space keypress at startup.

---

## Documentation

The `docs/netronics-explorer-85/` directory contains scanned original documentation and photos from the Netronics Explorer/85:

- Original manual pages (Netronics_Explorer85_A through E)
- Terminal ROM user information
- Cabinet assembly instructions and photos
- Original ROM images for the monitor (`explorer_monitor_rom/EXPLORER.HEX`) and BASIC (`explorer_basic_roms/C000.HEX` through `D800.HEX`) as separate files matching the smaller ROM chips used in the original hardware

---

## Acknowledgments

- Tom Nisbet for [Simple8085](https://github.com/TomNisbet/Simple8085), which was the main inspiration for this project, for [TommyPROM](https://github.com/TomNisbet/TommyPROM), which I used to program the EEPROM, and for [asm85](https://github.com/TomNisbet/asm85), the assembler used to build the MicroPython interpreter
- Netronics R&D for the original Explorer/85 design and monitor ROM
- Microsoft for ROM BASIC v4.7

---

## License

The original Netronics monitor ROM and Microsoft BASIC ROM images are included for educational and preservation purposes.
