; ============================================================================
; MicroPython 8085 - A minimal Python interpreter for the 8085-Explorer
; ============================================================================
; Target: 8085-Explorer board (28C256 ROM + 62256 RAM)
; Serial: Bit-banged SID/SOD at 9600 baud, 6.144MHz crystal
; Assemble: asm85.exe -b 8000:ffff micropython85.asm
; Memory: ROM at 8000-FFFF, RAM at 0000-7FFF
; ============================================================================

SYSROMST    equ     8000H
SYSRAMST    equ     0000H
STACK       equ     SYSRAMST + 7F00H

            org     SYSROMST

; === Serial Constants (9600 baud, 6.144MHz crystal) ===
BITTIME     equ     0113H
HALFBIT     equ     010AH
BITSOUT     equ     11
BITSIN      equ     9

; === Character Constants ===
LF          equ     00AH
CR          equ     00DH
BS          equ     008H
DEL         equ     07FH
TAB         equ     009H
SPACE       equ     020H
DQUOTE      equ     022H
SQUOTE      equ     027H

; === RAM Layout (0000-7EFF usable) ===
VARS        equ     SYSRAMST + 0000H   ; 26 vars * 2 bytes = 52 bytes
LINEBUF     equ     SYSRAMST + 0100H   ; Input line buffer (256 bytes)
BLOCKBUF    equ     SYSRAMST + 0200H   ; Block lines buffer (2KB)
NUMBUF      equ     SYSRAMST + 0A00H   ; Number conversion (16 bytes)
TEMPBUF     equ     SYSRAMST + 0A10H   ; Temp exec buffer (256 bytes)

; Interpreter state
BLOCKMODE   equ     SYSRAMST + 0B10H   ; 0=immediate, 1=collecting block
BLOCKTYPE   equ     SYSRAMST + 0B11H   ; 1=if, 2=for
BLOCKPTR    equ     SYSRAMST + 0B12H   ; Next free byte in BLOCKBUF (2 bytes)
BLKLINES    equ     SYSRAMST + 0B14H   ; Line count in block
FORVAR      equ     SYSRAMST + 0B15H   ; For-loop variable index (0-25)
FORSTART    equ     SYSRAMST + 0B16H   ; For start value (2 bytes)
FOREND      equ     SYSRAMST + 0B18H   ; For end value (2 bytes)
FORCUR      equ     SYSRAMST + 0B1AH   ; For current value (2 bytes)
IFRESULT    equ     SYSRAMST + 0B1CH   ; If condition: 1=true, 0=false
PARSEPTR    equ     SYSRAMST + 0B1DH   ; Expression parse pointer (2 bytes)

; ============================================================================
; ENTRY POINT - JMP clears boot flip-flop
; ============================================================================
            jmp     START

; ============================================================================
; STRING CONSTANTS (in ROM)
; ============================================================================
S_BOOT:     db      CR,LF,"8085-Explorer Booting...",CR,LF,0
S_SWAP:     db      "Memory Swap Successful: ROM@8000, RAM@0000"
            db      CR,LF,0
S_BANNER:   db      "Booting MicroPython v1.20.0-8085 on "
            db      "2026-05-10; 8085-Explorer with i8085"
            db      CR,LF,0
S_HELP:     db      "Type ",DQUOTE,"help()",DQUOTE
            db      " for more information.",CR,LF,0
S_PROMPT:   db      ">>> ",0
S_CONTIN:   db      "... ",0
S_CRLF:     db      CR,LF,0
S_HELPTXT:  db      "Welcome to MicroPython for 8085!",CR,LF
            db      "Features:",CR,LF
            db      "  Variables (a-z): x = 42",CR,LF
            db      "  Math: + - * / // ** %",CR,LF
            db      "  Compare: > < >= <= == !=",CR,LF
            db      "  print(): print(",DQUOTE,"Hi",DQUOTE,", x)"
            db      CR,LF
            db      "  if/else: if x > 5:",CR,LF
            db      "  for: for i in range(n):",CR,LF
            db      "  range(stop) or range(start,stop)",CR,LF
            db      "  16-bit signed integers",CR,LF,0
S_ERRSYN:   db      "SyntaxError: invalid syntax",CR,LF,0
S_ERRDIV:   db      "ZeroDivisionError: division by zero"
            db      CR,LF,0

KW_PRINT:   db      "print(",0
KW_IF:      db      "if ",0
KW_FOR:     db      "for ",0
KW_ELSE:    db      "else:",0
KW_HELP:    db      "help()",0

; ============================================================================
; START - Initialize and boot
; ============================================================================
START:
            mvi     a,0C0H          ; SOD high = serial idle
            sim
            lxi     h,STACK
            sphl

            ; Clear variable area
            lxi     h,VARS
            mvi     b,52
SINIT:      mvi     m,0
            inx     h
            dcr     b
            jnz     SINIT

            ; Initialize interpreter state
            xra     a
            sta     BLOCKMODE
            sta     BLOCKTYPE
            sta     BLKLINES
            lxi     h,BLOCKBUF
            shld    BLOCKPTR

            ; Print boot sequence
            lxi     h,S_BOOT
            call    PUTS
            lxi     h,S_SWAP
            call    PUTS
            lxi     h,S_BANNER
            call    PUTS
            lxi     h,S_HELP
            call    PUTS
            lxi     h,S_CRLF
            call    PUTS

; ============================================================================
; REPL - Read-Eval-Print Loop
; ============================================================================
REPL:
            lda     BLOCKMODE
            ora     a
            jnz     REPL1
            lxi     h,S_PROMPT
            call    PUTS
            jmp     REPL2
REPL1:      lxi     h,S_CONTIN
            call    PUTS
REPL2:      call    GETLINE         ; Read input into LINEBUF

            ; Check block mode
            lda     BLOCKMODE
            ora     a
            jnz     BCOLLECT

            ; Empty line in immediate mode = just reprompt
            lda     LINEBUF
            ora     a
            jz      REPL

            ; Execute the line
            lxi     h,LINEBUF
            call    EXECLINE
            jmp     REPL

; ============================================================================
; BCOLLECT - Collecting lines for multi-line block
; ============================================================================
BCOLLECT:
            ; Empty line = execute block
            lda     LINEBUF
            ora     a
            jz      BEXEC

            ; Check if line is indented (part of block)
            lxi     h,LINEBUF
            mov     a,m
            cpi     SPACE
            jz      BSTORE
            cpi     TAB
            jz      BSTORE

            ; Not indented: check for "else:"
            lxi     d,KW_ELSE
            call    MATCHKW
            jc      BSTORE

            ; Non-indented, non-else: end block, then exec this line
            call    BRUN
            lxi     h,LINEBUF
            call    EXECLINE
            jmp     REPL

BSTORE:
            ; Append LINEBUF to block buffer
            lhld    BLOCKPTR
            lxi     d,LINEBUF
BST1:       ldax    d
            mov     m,a
            inx     h
            ora     a
            jz      BST2
            inx     d
            jmp     BST1
BST2:       shld    BLOCKPTR        ; Save new write position
            lda     BLKLINES
            inr     a
            sta     BLKLINES
            jmp     REPL

BEXEC:      call    BRUN
            jmp     REPL

; ============================================================================
; BRUN - Execute the collected block then reset
; ============================================================================
BRUN:
            lda     BLKLINES
            ora     a
            jz      BRESET

            lda     BLOCKTYPE
            cpi     1
            jz      RUN_IF
            cpi     2
            jz      RUN_FOR

BRESET:
            xra     a
            sta     BLOCKMODE
            sta     BLOCKTYPE
            sta     BLKLINES
            lxi     h,BLOCKBUF
            shld    BLOCKPTR
            ret

; ============================================================================
; RUN_IF - Execute if/else block based on IFRESULT
; ============================================================================
RUN_IF:
            lda     IFRESULT
            mov     b,a             ; B=1 true, B=0 false
            lxi     h,BLOCKBUF
            lda     BLKLINES
            mov     c,a             ; C = line count
            mvi     d,0             ; D=0 if-branch, D=1 else-branch

RIFLP:      mov     a,c
            ora     a
            jz      BRESET          ; Done

            ; Is this line "else:"?
            push    b
            push    d
            push    h
            xchg                    ; DE = line start
            lxi     h,KW_ELSE
            call    MATCH_DE_HL
            pop     h
            pop     d
            pop     b
            jc      RIF_ELS

            ; Decide whether to execute
            mov     a,d
            ora     a
            jnz     RIF_EBR
            ; If-branch: exec if B=1
            mov     a,b
            ora     a
            jz      RIF_NXT
            jmp     RIF_EXE
RIF_EBR:    ; Else-branch: exec if B=0
            mov     a,b
            ora     a
            jnz     RIF_NXT

RIF_EXE:    push    b
            push    d
            push    h
            call    EXECBLK         ; Execute line at HL
            pop     h
            pop     d
            pop     b

RIF_NXT:    ; Advance HL past this line (find null)
            mov     a,m
            inx     h
            ora     a
            jnz     RIF_NXT
            dcr     c
            jmp     RIFLP

RIF_ELS:    mvi     d,1             ; Switch to else branch
            ; Skip past else: line
RIF_ELA:    mov     a,m
            inx     h
            ora     a
            jnz     RIF_ELA
            dcr     c
            jmp     RIFLP

; ============================================================================
; RUN_FOR - Execute for-loop block
; ============================================================================
RUN_FOR:
            lhld    FORSTART
            shld    FORCUR

RFLP:       ; Check current < end (signed)
            lhld    FORCUR
            xchg                    ; DE = current
            lhld    FOREND          ; HL = end
            call    CMP_DE_LT_HL    ; Carry if DE < HL
            jnc     RFDONE

            ; Store current in loop variable
            lhld    FORCUR
            xchg                    ; DE = value
            lda     FORVAR
            call    SETVAR

            ; Execute all block lines
            push    d               ; Save for safety
            lxi     h,BLOCKBUF
            lda     BLKLINES
            mov     c,a

RFEL:       mov     a,c
            ora     a
            jz      RFINC
            push    b
            push    h
            call    EXECBLK
            pop     h
            pop     b
            ; Advance to next line
RFAD:       mov     a,m
            inx     h
            ora     a
            jnz     RFAD
            dcr     c
            jmp     RFEL

RFINC:      pop     d               ; Balance stack
            lhld    FORCUR
            inx     h
            shld    FORCUR
            jmp     RFLP

RFDONE:     jmp     BRESET

; ============================================================================
; CMP_DE_LT_HL - Signed: is DE < HL? Carry set if yes.
; ============================================================================
CMP_DE_LT_HL:
            ; Compute DE - HL
            mov     a,d
            xra     h               ; Check sign difference
            jp      CDLH1           ; Same sign
            ; Different signs: DE < HL iff DE is negative
            mov     a,d
            ral
            ret                     ; Carry = sign bit of D
CDLH1:      ; Same sign: subtract
            mov     a,e
            sub     l
            mov     a,d
            sbb     h               ; A = high byte of (DE - HL)
            ral                     ; Carry = sign of result
            ret

; ============================================================================
; EXECBLK - Execute block line at HL (strip indent, copy to TEMPBUF)
; ============================================================================
EXECBLK:
            ; Skip leading whitespace
EBK1:       mov     a,m
            cpi     SPACE
            jz      EBK2
            cpi     TAB
            jz      EBK2
            jmp     EBK3
EBK2:       inx     h
            jmp     EBK1
EBK3:       ; Copy to TEMPBUF
            lxi     d,TEMPBUF
EBK4:       mov     a,m
            stax    d
            ora     a
            jz      EBK5
            inx     h
            inx     d
            jmp     EBK4
EBK5:       lxi     h,TEMPBUF
            call    EXECLINE
            ret

; ============================================================================
; EXECLINE - Parse and execute one line (HL = pointer to text)
; ============================================================================
EXECLINE:
            ; Skip whitespace
            call    SKIPWS
            mov     a,m
            ora     a
            rz                      ; Empty
            cpi     '#'
            rz                      ; Comment

            ; --- Try: print( ---
            push    h
            lxi     d,KW_PRINT
            call    MATCHKW
            pop     h
            jc      DO_PRINT

            ; --- Try: if ---
            push    h
            lxi     d,KW_IF
            call    MATCHKW
            pop     h
            jc      DO_IF

            ; --- Try: for ---
            push    h
            lxi     d,KW_FOR
            call    MATCHKW
            pop     h
            jc      DO_FOR

            ; --- Try: help() ---
            push    h
            lxi     d,KW_HELP
            call    MATCHKW
            pop     h
            jc      DO_HELP

            ; --- Try: assignment ---
            push    h
            call    CHK_ASSIGN
            pop     h
            jc      DO_ASSIGN

            ; --- Try: expression ---
            shld    PARSEPTR
            call    PARSE_CMP
            jnc     EXLERR
            ; Print result
            xchg                    ; HL = value
            call    PINT16
            lxi     h,S_CRLF
            call    PUTS
            ret

EXLERR:     lxi     h,S_ERRSYN
            call    PUTS
            ret

; ============================================================================
; DO_HELP
; ============================================================================
DO_HELP:
            lxi     h,S_HELPTXT
            call    PUTS
            ret

; ============================================================================
; DO_PRINT - print(arg1, arg2, ...)
; ============================================================================
DO_PRINT:
            ; HL -> "print(...)"  skip 6 chars "print("
            inx     h
            inx     h
            inx     h
            inx     h
            inx     h
            inx     h              ; Past "print("

DPARGS:     call    SKIPWS
            mov     a,m
            ora     a
            jz      DPEND
            cpi     ')'
            jz      DPEND

            ; String?
            cpi     DQUOTE
            jz      DPSTR
            cpi     SQUOTE
            jz      DPSTR

            ; Expression
            shld    PARSEPTR
            push    h
            call    PARSE_CMP
            pop     h
            jnc     DPERR
            ; Print number from DE
            push    d
            xchg
            call    PINT16
            pop     d
            ; Advance parse pointer
            lhld    PARSEPTR
            call    SKIPWS
            mov     a,m
            cpi     ','
            jz      DPCOM
            jmp     DPARGS

DPSTR:      mov     b,m             ; B = quote char
            inx     h
DPSL:       mov     a,m
            ora     a
            jz      DPEND
            cmp     b
            jz      DPSE
            mov     c,a
            push    h
            push    b
            call    COUT
            pop     b
            pop     h
            inx     h
            jmp     DPSL
DPSE:       inx     h               ; Past closing quote
            call    SKIPWS
            mov     a,m
            cpi     ','
            jz      DPCOM
            jmp     DPARGS

DPCOM:      inx     h               ; Skip comma
            push    h
            mvi     c,SPACE
            call    COUT
            pop     h
            jmp     DPARGS

DPEND:      mvi     c,CR
            call    COUT
            mvi     c,LF
            call    COUT
            ret

DPERR:      lxi     h,S_ERRSYN
            call    PUTS
            ret

; ============================================================================
; DO_IF - if <condition>:
; ============================================================================
DO_IF:
            ; Skip "if "
            inx     h
            inx     h
            inx     h
            ; Evaluate condition
            shld    PARSEPTR
            call    PARSE_CMP
            jnc     DIFERR
            ; Nonzero = true
            mov     a,d
            ora     e
            mvi     a,0
            jz      DIF1
            mvi     a,1
DIF1:       sta     IFRESULT
            ; Enter block mode
            mvi     a,1
            sta     BLOCKMODE
            sta     BLOCKTYPE
            xra     a
            sta     BLKLINES
            lxi     h,BLOCKBUF
            shld    BLOCKPTR
            ret

DIFERR:     lxi     h,S_ERRSYN
            call    PUTS
            ret

; ============================================================================
; DO_FOR - for <var> in range(<args>):
; ============================================================================
DO_FOR:
            ; Skip "for "
            inx     h
            inx     h
            inx     h
            inx     h
            ; Get variable
            mov     a,m
            call    TOLWR
            sui     'a'
            jc      DFERR
            cpi     26
            jnc     DFERR
            sta     FORVAR
            ; Skip variable name
            inx     h
DFSV:       mov     a,m
            call    ISALNUM
            jnc     DFSV2
            inx     h
            jmp     DFSV
DFSV2:      call    SKIPWS
            ; Expect "in"
            mov     a,m
            cpi     'i'
            jnz     DFERR
            inx     h
            mov     a,m
            cpi     'n'
            jnz     DFERR
            inx     h
            call    SKIPWS
            ; Expect "range("
            mov     a,m
            cpi     'r'
            jnz     DFERR
            inx     h
            mov     a,m
            cpi     'a'
            jnz     DFERR
            inx     h
            mov     a,m
            cpi     'n'
            jnz     DFERR
            inx     h
            mov     a,m
            cpi     'g'
            jnz     DFERR
            inx     h
            mov     a,m
            cpi     'e'
            jnz     DFERR
            inx     h
            mov     a,m
            cpi     '('
            jnz     DFERR
            inx     h
            ; Parse first argument
            shld    PARSEPTR
            call    PARSE_CMP
            jnc     DFERR
            push    d               ; Save arg1
            lhld    PARSEPTR
            call    SKIPWS
            mov     a,m
            cpi     ','
            jz      DF2ARG
            ; range(stop): start=0
            pop     d
            xchg
            shld    FOREND
            lxi     h,0
            shld    FORSTART
            jmp     DFOK
DF2ARG:     inx     h               ; Skip comma
            shld    PARSEPTR
            call    PARSE_CMP
            jnc     DFE2
            ; arg1=start, arg2=stop
            xchg
            shld    FOREND
            pop     d
            xchg
            shld    FORSTART
            jmp     DFOK
DFE2:       pop     d               ; Clean stack
DFERR:      lxi     h,S_ERRSYN
            call    PUTS
            ret
DFOK:       mvi     a,1
            sta     BLOCKMODE
            mvi     a,2
            sta     BLOCKTYPE
            xra     a
            sta     BLKLINES
            lxi     h,BLOCKBUF
            shld    BLOCKPTR
            ret

; ============================================================================
; DO_ASSIGN - var = expr
; ============================================================================
DO_ASSIGN:
            mov     a,m
            call    TOLWR
            sui     'a'
            mov     b,a             ; B = var index
            ; Skip variable name
            inx     h
DAS1:       mov     a,m
            call    ISALNUM
            jnc     DAS2
            inx     h
            jmp     DAS1
DAS2:       call    SKIPWS
            inx     h               ; Skip '='
            call    SKIPWS
            ; Evaluate RHS
            shld    PARSEPTR
            push    b
            call    PARSE_CMP
            pop     b
            jnc     DAERR
            ; Store DE in variable B
            mov     a,b
            call    SETVAR
            ret
DAERR:      lxi     h,S_ERRSYN
            call    PUTS
            ret

; ============================================================================
; CHK_ASSIGN - Does line at HL contain an assignment? Carry=yes
; ============================================================================
CHK_ASSIGN:
            mov     a,m
            call    ISLETR
            rnc
            push    h
CA1:        mov     a,m
            ora     a
            jz      CA_NO
            cpi     '='
            jz      CA_CHK
            cpi     DQUOTE
            jz      CA_NO
            cpi     SQUOTE
            jz      CA_NO
            inx     h
            jmp     CA1
CA_CHK:     ; Check not part of ==, !=, <=, >=
            dcx     h
            mov     a,m
            inx     h
            cpi     '!'
            jz      CA_NX
            cpi     '<'
            jz      CA_NX
            cpi     '>'
            jz      CA_NX
            inx     h
            mov     a,m
            dcx     h
            cpi     '='
            jz      CA_NX
            pop     h
            stc
            ret
CA_NX:      inx     h
            jmp     CA1
CA_NO:      pop     h
            ora     a
            ret

; ============================================================================
; EXPRESSION PARSER
; ============================================================================

; PARSE_CMP - Comparison operators (lowest precedence)
; Returns DE = result, carry set on success
PARSE_CMP:
            call    PARSE_ADD
            rnc
            push    d

PC_LP:      lhld    PARSEPTR
            call    SKIPWS
            shld    PARSEPTR
            mov     a,m

            cpi     '>'
            jz      PC_GT
            cpi     '<'
            jz      PC_LT
            cpi     '='
            jz      PC_EQ
            cpi     '!'
            jz      PC_NE
            ; Also stop at : ) , and end
            pop     d
            stc
            ret

PC_GT:      inx     h
            mov     a,m
            cpi     '='
            jz      PC_GTE
            shld    PARSEPTR
            call    PARSE_ADD
            jnc     PC_ERR
            pop     b               ; left in BC
            call    SGT_BC_DE       ; BC>DE?
            push    d
            jmp     PC_LP
PC_GTE:     inx     h
            shld    PARSEPTR
            call    PARSE_ADD
            jnc     PC_ERR
            pop     b
            call    SGTE_BC_DE
            push    d
            jmp     PC_LP

PC_LT:      inx     h
            mov     a,m
            cpi     '='
            jz      PC_LTE
            shld    PARSEPTR
            call    PARSE_ADD
            jnc     PC_ERR
            pop     b
            ; BC < DE  means  DE > BC
            push    d
            mov     d,b
            mov     e,c
            pop     b
            call    SGT_BC_DE
            push    d
            jmp     PC_LP
PC_LTE:     inx     h
            shld    PARSEPTR
            call    PARSE_ADD
            jnc     PC_ERR
            pop     b
            push    d
            mov     d,b
            mov     e,c
            pop     b
            call    SGTE_BC_DE
            push    d
            jmp     PC_LP

PC_EQ:      inx     h
            mov     a,m
            cpi     '='
            jnz     PC_NOP
            inx     h
            shld    PARSEPTR
            call    PARSE_ADD
            jnc     PC_ERR
            pop     b
            ; BC == DE?
            mov     a,b
            cmp     d
            jnz     PC_EQF
            mov     a,c
            cmp     e
            jnz     PC_EQF
            lxi     d,1
            push    d
            jmp     PC_LP
PC_EQF:     lxi     d,0
            push    d
            jmp     PC_LP

PC_NE:      inx     h
            mov     a,m
            cpi     '='
            jnz     PC_NOP
            inx     h
            shld    PARSEPTR
            call    PARSE_ADD
            jnc     PC_ERR
            pop     b
            ; BC != DE?
            mov     a,b
            cmp     d
            jnz     PC_NET
            mov     a,c
            cmp     e
            jnz     PC_NET
            lxi     d,0
            push    d
            jmp     PC_LP
PC_NET:     lxi     d,1
            push    d
            jmp     PC_LP

PC_NOP:     ; Not a comparison, restore
            dcx     h
            shld    PARSEPTR
            pop     d
            stc
            ret

PC_ERR:     pop     b
            ora     a
            ret

; SGT_BC_DE: Signed BC > DE? Result DE=1 or 0
SGT_BC_DE:
            mov     a,b
            xra     d
            jp      SGT1
            ; Different signs
            mov     a,b
            ani     80H
            jz      SGT_T           ; B positive, D negative => yes
            jmp     SGT_F
SGT1:       ; Same sign: unsigned compare works
            mov     a,b
            cmp     d
            jc      SGT_F           ; B < D
            jnz     SGT_T           ; B > D
            mov     a,c
            cmp     e
            jc      SGT_F
            jz      SGT_F           ; Equal = not greater
SGT_T:      lxi     d,1
            ret
SGT_F:      lxi     d,0
            ret

; SGTE_BC_DE: Signed BC >= DE?
SGTE_BC_DE:
            mov     a,b
            xra     d
            jp      SGTE1
            mov     a,b
            ani     80H
            jz      SGTE_T
            jmp     SGTE_F
SGTE1:      mov     a,b
            cmp     d
            jc      SGTE_F
            jnz     SGTE_T
            mov     a,c
            cmp     e
            jc      SGTE_F
SGTE_T:     lxi     d,1
            ret
SGTE_F:     lxi     d,0
            ret

; PARSE_ADD - Addition and subtraction
PARSE_ADD:
            call    PARSE_MUL
            rnc
PA_LP:      push    d
            lhld    PARSEPTR
            call    SKIPWS
            shld    PARSEPTR
            mov     a,m
            cpi     '+'
            jz      PA_PLS
            cpi     '-'
            jz      PA_MIN
            pop     d
            stc
            ret
PA_PLS:     inx     h
            shld    PARSEPTR
            call    PARSE_MUL
            jnc     PA_ERR
            pop     b
            mov     a,c
            add     e
            mov     e,a
            mov     a,b
            adc     d
            mov     d,a
            jmp     PA_LP
PA_MIN:     inx     h
            shld    PARSEPTR
            call    PARSE_MUL
            jnc     PA_ERR
            pop     b
            ; BC - DE
            mov     a,c
            sub     e
            mov     e,a
            mov     a,b
            sbb     d
            mov     d,a
            jmp     PA_LP
PA_ERR:     pop     b
            ora     a
            ret

; PARSE_MUL - Multiply, divide, modulo
PARSE_MUL:
            call    PARSE_POW
            rnc
PM_LP:      push    d
            lhld    PARSEPTR
            call    SKIPWS
            shld    PARSEPTR
            mov     a,m
            cpi     '*'
            jz      PM_ST
            cpi     '/'
            jz      PM_DV
            cpi     '%'
            jz      PM_MD
            pop     d
            stc
            ret

PM_ST:      inx     h
            mov     a,m
            cpi     '*'             ; ** is power, bail
            jz      PM_NM
            shld    PARSEPTR
            call    PARSE_POW
            jnc     PM_ERR
            pop     b
            call    MUL16           ; BC*DE->DE
            jmp     PM_LP
PM_NM:      dcx     h
            shld    PARSEPTR
            pop     d
            stc
            ret

PM_DV:      inx     h
            mov     a,m
            cpi     '/'             ; //
            jnz     PM_DV1
            inx     h
PM_DV1:     shld    PARSEPTR
            call    PARSE_POW
            jnc     PM_ERR
            mov     a,d
            ora     e
            jz      PM_DZ
            pop     b
            call    SDIV16          ; BC/DE -> quot in BC
            mov     d,b
            mov     e,c
            jmp     PM_LP

PM_MD:      inx     h
            shld    PARSEPTR
            call    PARSE_POW
            jnc     PM_ERR
            mov     a,d
            ora     e
            jz      PM_DZ
            pop     b
            call    SMOD16          ; BC%DE -> DE
            jmp     PM_LP

PM_DZ:      pop     b
            lxi     h,S_ERRDIV
            call    PUTS
            ora     a
            ret
PM_ERR:     pop     b
            ora     a
            ret

; PARSE_POW - Power (**)
PARSE_POW:
            call    PARSE_UNR
            rnc
PP_LP:      push    d
            lhld    PARSEPTR
            call    SKIPWS
            shld    PARSEPTR
            mov     a,m
            cpi     '*'
            jnz     PP_NO
            inx     h
            mov     a,m
            cpi     '*'
            jnz     PP_NO2
            inx     h
            shld    PARSEPTR
            call    PARSE_UNR       ; Right-associative
            jnc     PP_ERR
            pop     b               ; BC=base, DE=exponent
            call    POW16           ; result in DE
            jmp     PP_LP
PP_NO2:     dcx     h
PP_NO:      pop     d
            stc
            ret
PP_ERR:     pop     b
            ora     a
            ret

; PARSE_UNR - Unary minus
PARSE_UNR:
            lhld    PARSEPTR
            call    SKIPWS
            shld    PARSEPTR
            mov     a,m
            cpi     '-'
            jz      PU_NG
            jmp     PARSE_ATM
PU_NG:      inx     h
            shld    PARSEPTR
            call    PARSE_ATM
            rnc
            ; Negate DE
            mov     a,e
            cma
            mov     e,a
            mov     a,d
            cma
            mov     d,a
            inx     d
            stc
            ret

; PARSE_ATM - Atom: number, variable, (expr)
PARSE_ATM:
            lhld    PARSEPTR
            call    SKIPWS
            shld    PARSEPTR
            mov     a,m

            cpi     '('
            jz      PAT_P
            cpi     '0'
            jc      PAT_V
            cpi     '9'+1
            jc      PAT_N

PAT_V:      ; Variable
            mov     a,m
            call    ISLETR
            jnc     PAT_F
            mov     a,m
            call    TOLWR
            sui     'a'
            mov     b,a
            ; Skip variable name
PAT_VS:     inx     h
            mov     a,m
            call    ISALNUM
            jc      PAT_VS
            shld    PARSEPTR
            mov     a,b
            call    GETVAR          ; DE = value
            stc
            ret

PAT_N:      ; Number
            lxi     d,0
PAT_NL:     mov     a,m
            cpi     '0'
            jc      PAT_ND
            cpi     '9'+1
            jnc     PAT_ND
            ; DE = DE * 10 + digit
            sui     '0'
            push    h
            push    psw
            mov     h,d
            mov     l,e
            dad     h               ; *2
            dad     h               ; *4
            dad     d               ; *5
            dad     h               ; *10
            xchg                    ; DE = old * 10
            pop     psw
            add     e
            mov     e,a
            mov     a,d
            aci     0
            mov     d,a
            pop     h
            inx     h
            jmp     PAT_NL
PAT_ND:     shld    PARSEPTR
            stc
            ret

PAT_P:      ; Parenthesized expression
            inx     h
            shld    PARSEPTR
            call    PARSE_CMP
            rnc
            lhld    PARSEPTR
            call    SKIPWS
            mov     a,m
            cpi     ')'
            jnz     PAT_F
            inx     h
            shld    PARSEPTR
            stc
            ret

PAT_F:      ora     a
            ret

; ============================================================================
; MATH LIBRARY (16-bit signed)
; ============================================================================

; MUL16: BC * DE -> DE
MUL16:
            mov     a,b
            xra     d
            push    psw             ; Sign of result
            mov     a,b
            ora     a
            jp      ML_BP
            call    NEGBC
ML_BP:      mov     a,d
            ora     a
            jp      ML_DP
            call    NEGDE
ML_DP:      ; Unsigned BC * DE -> HL
            lxi     h,0
            mvi     a,16
ML_LP:      dad     h               ; Shift result left
            xchg
            dad     h               ; Shift multiplier (DE was swapped to HL)
            xchg
            jnc     ML_NX
            dad     b               ; Add multiplicand
ML_NX:      dcr     a
            jnz     ML_LP
            xchg                    ; DE = result
            pop     psw
            jp      ML_RT
            call    NEGDE
ML_RT:      stc
            ret

; SDIV16: Signed BC / DE -> quotient in BC
SDIV16:
            mov     a,b
            xra     d
            push    psw
            mov     a,b
            ora     a
            jp      SD_BP
            call    NEGBC
SD_BP:      mov     a,d
            ora     a
            jp      SD_DP
            call    NEGDE
SD_DP:      call    UDIV16
            pop     psw
            jp      SD_RT
            call    NEGBC
SD_RT:      ret

; SMOD16: Signed BC % DE -> remainder in DE
SMOD16:
            mov     a,b
            push    psw             ; Sign of dividend for remainder
            ora     a
            jp      SM_BP
            call    NEGBC
SM_BP:      mov     a,d
            ora     a
            jp      SM_DP
            call    NEGDE
SM_DP:      call    UDIV16          ; Rem in HL
            xchg                    ; DE = remainder
            pop     psw
            ora     a
            jp      SM_RT
            call    NEGDE
SM_RT:      stc
            ret

; UDIV16: Unsigned BC / DE -> quotient BC, remainder HL
UDIV16:
            lxi     h,0
            mvi     a,16
UD_LP:      push    psw
            ; Shift BC left into HL
            mov     a,c
            ral
            mov     c,a
            mov     a,b
            ral
            mov     b,a
            mov     a,l
            ral
            mov     l,a
            mov     a,h
            ral
            mov     h,a
            ; Try HL - DE
            mov     a,l
            sub     e
            mov     l,a
            mov     a,h
            sbb     d
            mov     h,a
            jnc     UD_OK
            ; Restore
            mov     a,l
            add     e
            mov     l,a
            mov     a,h
            adc     d
            mov     h,a
            pop     psw
            dcr     a
            jnz     UD_LP
            ret
UD_OK:      inr     c
            pop     psw
            dcr     a
            jnz     UD_LP
            ret

; POW16: BC ^ DE -> DE
POW16:
            ; Check exp = 0
            mov     a,d
            ora     e
            jnz     PW_GO
            lxi     d,1
            ret
PW_GO:      ; Save base and exponent
            mov     a,e             ; Use low byte of exponent
            mov     e,a
            push    b               ; Save base on stack
            lxi     b,1             ; Result = 1 (in BC)
            ; Loop: result = result * base, exp times
PW_LP:      push    d               ; Save exp counter
            ; Multiply BC (result) * base (on stack, at SP+2)
            ; Grab base
            lxi     h,2
            dad     sp              ; HL points to saved base (low byte)
            push    b               ; Save current result
            mov     c,m
            inx     h
            mov     b,m             ; BC = base
            pop     d               ; DE = current result
            ; BC * DE -> DE
            call    MUL16
            ; DE = new result, move to BC
            mov     b,d
            mov     c,e
            pop     d               ; Restore exp counter
            dcr     e
            jnz     PW_LP
            ; Result in BC
            mov     d,b
            mov     e,c
            pop     b               ; Remove saved base
            ret

; NEGBC: Negate BC
NEGBC:      mov     a,c
            cma
            mov     c,a
            mov     a,b
            cma
            mov     b,a
            inx     b
            ret

; NEGDE: Negate DE
NEGDE:      mov     a,e
            cma
            mov     e,a
            mov     a,d
            cma
            mov     d,a
            inx     d
            ret

; ============================================================================
; VARIABLE ACCESS
; ============================================================================

; SETVAR: variable[A] = DE
SETVAR:     push    h
            mov     l,a
            mvi     h,0
            dad     h
            lxi     b,VARS
            dad     b
            mov     m,e
            inx     h
            mov     m,d
            pop     h
            ret

; GETVAR: DE = variable[A]
GETVAR:     push    h
            mov     l,a
            mvi     h,0
            dad     h
            lxi     b,VARS
            dad     b
            mov     e,m
            inx     h
            mov     d,m
            pop     h
            ret

; ============================================================================
; STRING / CHAR UTILITIES
; ============================================================================

; SKIPWS: Advance HL past spaces and tabs
SKIPWS:     mov     a,m
            cpi     SPACE
            jz      SKW1
            cpi     TAB
            jz      SKW1
            ret
SKW1:       inx     h
            jmp     SKIPWS

; MATCHKW: Does string at HL start with string at DE? Carry=yes
MATCHKW:    push    h
            push    d
MK1:        ldax    d
            ora     a
            jz      MK_Y
            cmp     m
            jnz     MK_N
            inx     h
            inx     d
            jmp     MK1
MK_Y:       pop     d
            pop     h
            stc
            ret
MK_N:       pop     d
            pop     h
            ora     a
            ret

; MATCH_DE_HL: Does string at DE start with pattern at HL? Carry=yes
MATCH_DE_HL:
            push    h
            push    d
MDH1:       mov     a,m             ; Pattern
            ora     a
            jz      MDH_Y
            ldax    d
            cmp     m
            jnz     MDH_N
            inx     h
            inx     d
            jmp     MDH1
MDH_Y:      pop     d
            pop     h
            stc
            ret
MDH_N:      pop     d
            pop     h
            ora     a
            ret

; TOLWR: A -> lowercase
TOLWR:      cpi     'A'
            rc
            cpi     'Z'+1
            rnc
            adi     20H
            ret

; ISLETR: Carry if A is letter or underscore
ISLETR:     cpi     'a'
            jc      ILU
            cpi     'z'+1
            jc      IL_Y
ILU:        cpi     'A'
            jc      ILSC
            cpi     'Z'+1
            jc      IL_Y
ILSC:       cpi     '_'
            jz      IL_Y
            ora     a
            ret
IL_Y:       stc
            ret

; ISALNUM: Carry if letter, digit, or _
ISALNUM:    call    ISLETR
            rc
            cpi     '0'
            jc      IAN_N
            cpi     '9'+1
            jc      IAN_Y
IAN_N:      ora     a
            ret
IAN_Y:      stc
            ret

; ============================================================================
; PINT16 - Print signed 16-bit integer in HL
; ============================================================================
PINT16:
            mov     a,h
            ani     80H
            jz      PPOS
            ; Negative
            push    h
            mvi     c,'-'
            call    COUT
            pop     h
            mov     a,l
            cma
            mov     l,a
            mov     a,h
            cma
            mov     h,a
            inx     h
PPOS:       ; HL = positive value, print decimal
            ; Use NUMBUF as scratch (right-to-left)
            lxi     d,NUMBUF+8
            dcx     d
            xra     a
            stax    d               ; Null terminator

            ; Zero check
            mov     a,h
            ora     l
            jnz     PDLP
            dcx     d
            mvi     a,'0'
            stax    d
            jmp     PPR
PDLP:       mov     a,h
            ora     l
            jz      PPR
            ; HL / 10: use BC=HL, DE=10
            push    d
            mov     b,h
            mov     c,l
            lxi     d,10
            call    UDIV16          ; BC=quotient, HL=remainder
            mov     a,l
            adi     '0'
            mov     h,b
            mov     l,c             ; HL = quotient
            pop     d
            dcx     d
            stax    d
            jmp     PDLP
PPR:        xchg
            call    PUTS
            ret

; ============================================================================
; GETLINE - Read a line into LINEBUF with editing
; ============================================================================
GETLINE:
            lxi     h,LINEBUF
            mvi     b,0             ; Character count
GL_LP:      push    h
            push    b
            call    CIN             ; Char in A
            pop     b
            pop     h

            ; Enter?
            cpi     CR
            jz      GL_DN
            cpi     LF
            jz      GL_DN

            ; Backspace?
            cpi     BS
            jz      GL_BS
            cpi     DEL
            jz      GL_BS

            ; Control char?
            cpi     SPACE
            jc      GL_LP

            ; Buffer full?
            mov     c,a             ; Save char in C
            mov     a,b
            cpi     250
            jnc     GL_LP

            ; Store and echo
            mov     m,c
            inx     h
            inr     b
            push    h
            push    b
            call    COUT            ; C has the char
            pop     b
            pop     h
            jmp     GL_LP

GL_BS:      mov     a,b
            ora     a
            jz      GL_LP
            dcx     h
            dcr     b
            push    h
            push    b
            mvi     c,BS
            call    COUT
            mvi     c,SPACE
            call    COUT
            mvi     c,BS
            call    COUT
            pop     b
            pop     h
            jmp     GL_LP

GL_DN:      mvi     m,0
            push    h
            push    b
            mvi     c,CR
            call    COUT
            mvi     c,LF
            call    COUT
            pop     b
            pop     h
            ret

; ============================================================================
; SERIAL I/O - Bit-banged UART (from working test5-char-in-out.asm)
; ============================================================================
CIN:
            di
            push    b
            mvi     b,BITSIN
CI1:        rim
            ora     a
            jm      CI1
            lxi     h,HALFBIT
CI2:        dcr     l
            jnz     CI2
            dcr     h
            jnz     CI2
CI3:        lxi     h,BITTIME
CI4:        dcr     l
            jnz     CI4
            dcr     h
            jnz     CI4
            rim
            ral
            dcr     b
            jz      CI5
            mov     a,c
            rar
            mov     c,a
            nop
            jmp     CI3
CI5:        mov     a,c
            pop     b
            ei
            ret

COUT:
            di
            push    h
            push    b
            mvi     b,BITSOUT
            xra     a
CO1:        mvi     a,080H
            rar
            cmc
            sim
            lxi     h,BITTIME
CO2:        dcr     l
            jnz     CO2
            dcr     h
            jnz     CO2
            stc
            mov     a,c
            rar
            mov     c,a
            dcr     b
            jnz     CO1
            pop     b
            pop     h
            ei
            ret

; PUTS - Print null-terminated string at HL
PUTS:       mov     a,m
            ora     a
            rz
            mov     c,a
            call    COUT
            inx     h
            jmp     PUTS

; DELAY - HL iterations
DELAY:      dcr     l
            jnz     DELAY
            dcr     h
            jnz     DELAY
            ret

            end
