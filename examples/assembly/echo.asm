; echo.asm - Simple character echo example for the 8085-Explorer board
;
; This program prints a welcome message and then echoes every character
; received from the serial port back to the terminal. What you type in
; Tera Term is immediately displayed back to you.
;
; Build:  asm85.exe -b 8000:ffff echo.asm
; Flash:  Flash echo-8000.bin onto the 28C256 using TommyPROM
;
; Hardware: 8085-Explorer (6.144 MHz, SID/SOD serial at 9600,N,8,1)
; Memory:   ROM @ 8000-FFFF, RAM @ 0000-7FFF

SYSROMST    equ     8000H
SYSRAMST    equ     0000H

STACK       equ     SYSRAMST + 7F00H

            org     SYSROMST

; Constants for serial communications at 9600 baud with a 6.144MHz crystal
; The connected terminal should be set for 9600,N,8,1
BITTIME     equ     0113H           ; Time delay for a single bit
HALFBIT     equ     010AH           ; Time after start bit detected to read middle of a bit
BITSOUT     equ     11              ; Serial bits to send (start + 8 data + 2 stop)
BITSIN      equ     9               ; Serial bits to read + 1 (8 data bits)

; Character constants
LF          equ     00AH
CR          equ     00DH
ESC         equ     01BH

; ===========================================================================
; RESET VECTOR - Jump to ROM to clear the reset-mode flip-flop
; ===========================================================================
            jmp     START

; ===========================================================================
; String data stored in ROM
; ===========================================================================
WELCOME:    db      CR,LF
            db      "8085-Explorer Serial Echo",CR,LF
            db      "-------------------------",CR,LF
            db      "Type any character and it will be echoed back.",CR,LF
            db      "This is a minimal example for building your own programs.",CR,LF
            db      CR,LF,0

; ===========================================================================
; MAIN PROGRAM
; ===========================================================================
START:
            mvi     a,0C0H          ; Set SOD high (serial line idle)
            sim
            lxi     h,STACK         ; Initialize stack pointer
            sphl

            lxi     h,WELCOME       ; Print the welcome message
            call    PUTS

; ---------------------------------------------------------------------------
; Main echo loop: read a character, echo it back, repeat forever
; ---------------------------------------------------------------------------
ECHOLOOP:
            call    CIN             ; Wait for a character from serial input
                                    ; Character is returned in A

            mov     c,a             ; Move character to C for COUT
            call    COUT            ; Send it back out

            jmp     ECHOLOOP        ; Loop forever


; ===========================================================================
; SERIAL I/O SUBROUTINES
; ===========================================================================

;*****************************************************************************
; CIN - Character in from serial console
;
; inputs:   none
; outputs:  A - character from the console
; calls:    none
; destroys: a,f,b,c,h,l
;
; Waits for a start bit (logic 0 on SID), then reads 8 data bits LSB first.
; Stop bits provide guaranteed delay before the next character.
;*****************************************************************************
CIN:
            di
            push    b
            mvi     b,BITSIN        ; Number of bits to read (8 data bits)
CI1:
            rim                     ; Wait for start bit (SID goes low)
            ora     a
            jm      CI1
            lxi     h,HALFBIT       ; Delay half bit to reach middle of start bit
CI2:
            dcr     l
            jnz     CI2
            dcr     h
            jnz     CI2
CI3:
            lxi     h,BITTIME       ; Delay one full bit time
CI4:
            dcr     l
            jnz     CI4
            dcr     h
            jnz     CI4

            rim                     ; Read the data bit from SID
            ral                     ; Shift data bit into carry
            dcr     b               ; All bits read?
            jz      CI5
            mov     a,c             ; Get character in progress
            rar                     ; Shift carry (data bit) into MSB
            mov     c,a             ; Store back
            nop
            jmp     CI3             ; Next bit
CI5:
            mov     a,c             ; Return completed character in A
            pop     b
            ei
            ret


;*****************************************************************************
; COUT - Character out to serial console
;
; inputs:   C - character to output
; outputs:  none
; calls:    none
; destroys: a,f
;
; Sends start bit (0), 8 data bits LSB first, then 2 stop bits (1).
;*****************************************************************************
COUT:
            di
            push    h
            push    b
            mvi     b,BITSOUT       ; Total bits: 1 start + 8 data + 2 stop
            xra     a               ; Clear carry for start bit (0)
CO1:
            mvi     a,080H          ; Set MSB to shift into SDE flag
            rar                     ; Shift: SDE=1 (enable), SOD=carry (data bit)
            cmc
            sim                     ; Output the bit on SOD
            lxi     h,BITTIME       ; Delay one bit time
CO2:
            dcr     l
            jnz     CO2
            dcr     h
            jnz     CO2
            stc                     ; Set carry for stop bits (logic 1)
            mov     a,c             ; Get character
            rar                     ; Shift LSB into carry for next output
            mov     c,a             ; Store rotated character
            dcr     b
            jnz     CO1             ; Next bit
            pop     b
            pop     h
            ei
            ret


;*****************************************************************************
; PUTS - Print a zero-terminated string to the console
;
; inputs:   HL - points to zero-terminated string in memory
; outputs:  none
; calls:    COUT
; destroys: a,f,c,h,l
;*****************************************************************************
PUTS:
            mov     a,m             ; Get character from string
            ora     a               ; Is it zero (end of string)?
            rz                      ; Yes - return
            mov     c,a             ; No - put char in C for COUT
            call    COUT            ; Print it
            inx     h               ; Advance to next character
            jmp     PUTS            ; Continue


;*****************************************************************************
; DELAY - Spin loop delay
;
; inputs:   HL - loop count
; outputs:  none
; calls:    none
; destroys: f,h,l
;*****************************************************************************
DELAY:
            dcr     l
            jnz     DELAY
            dcr     h
            jnz     DELAY
            ret

            end
