; -----------------------------------------------------------
; Small C Compiler for TRDOS 386 (v2.0.9 and later)
; Erdogan Tan - 2024
; Beginning: 05/09/2024
; Last Update: 22/09/2024
; -----------------------------------------------------------
; Derived from 'scc.asm' file of KolibriOS SCC source code
; 2024

;B+ System header
use32
org 0x0
  jmp START	; TRDOS 386 PRG file doesn't contain header

  dd  0

;B+ Include C files
  ; Compiler tools
  include "INTRINS.ASM"

  ; C Library ("stdio.asm")
  include "LIBSTD.ASM"

  ; MenuetOS implement
  include "OSFUNC.ASM"

_fopen	equ _OS_fopen
_fputc	equ _OS_fputc
_fgetc	equ _OS_fgetc
_fclose equ _OS_fclos

  ; Main program (compiled from C)
  include "GETARG.ASM"
  include "HELLO.ASM"
;E:.

START:
   ; esp = argc
   ; esp+4 = argv[0] address
   pop  eax	; argc (value)
   mov  ebx,esp	; argv[0] address (not value)
   push	eax	; argc
   push	ebx
   call _main
   ;add esp,8
   pop	ebx
   ;
   xor  ebx,ebx	; exit code = 0
   mov	eax,1	; sysexit
   int  40h

  db 0	
  db "Small C Compiler v1.0 for TRDOS 386"
  db 0
  db "Erdogan Tan - 2024"
  db 0	