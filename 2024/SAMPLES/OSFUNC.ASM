; -----------------------------------------------------------
; Small C Compiler for TRDOS 386 (v2.0.9 and later)
; Erdogan Tan - 2024
; Beginning: 05/09/2024
; Last Update: 23/09/2024
; -----------------------------------------------------------
; Derived from 'osfunc.asm' file of KolibriOS SCC source code
; 2024

; 20/08/2024 ; TRDOS 386 v2.0.9
; 29/04/2016
_ver 	equ 0
_exit 	equ 1
_fork 	equ 2
_read 	equ 3
_write	equ 4
_open	equ 5
_close 	equ 6
_wait 	equ 7
_creat 	equ 8
_link 	equ 9
_unlink	equ 10
_exec	equ 11
_chdir	equ 12
_time 	equ 13
_mkdir 	equ 14
_chmod	equ 15
_chown	equ 16
_break	equ 17
_stat	equ 18
_seek	equ 19
_tell 	equ 20
_mount	equ 21
_umount	equ 22
_setuid	equ 23
_getuid	equ 24
_stime	equ 25
_quit	equ 26
_intr	equ 27
_fstat	equ 28
_emt 	equ 29
_mdate 	equ 30
_video 	equ 31
_audio	equ 32
_timer	equ 33
_sleep	equ 34
_msg    equ 35
_geterr	equ 36
_fpsave	equ 37
_pri	equ 38
_rele	equ 39
_fff	equ 40
_fnf	equ 41
_alloc	equ 42
_dalloc equ 43
_calbac equ 44
_dma	equ 45
_stdio  equ 46

    ; 12/09/2024 ('sys' macro in FASM format)

macro sys op1,op2,op3,op4
{
    if op4 eq
    else
        mov edx, op4
    end if
    if op3 eq
    else
        mov ecx, op3
    end if
    if op2 eq
    else
        mov ebx, op2
    end if
    mov eax, op1
    int 40h
}

; -----------------------------

;
; OS function implementation
; SmallC for KolibriOS
;

init_osfunc:
; 05/09/2024 - TRDOS 386 v2.0.9
; nothing to do for now
retn

;Main OS functions

_OS_fopen:
;Implement "fopen"
  ;esp+4 - mode
  ;esp+8 - file name

  mov  eax, [esp+4] ; file open mode
  mov  ebx, [esp+8] ; file name
 
  xor  ecx, ecx ; 0 ; open for read
  cmp  byte [eax], 'r'
  je   short open_read
  inc  ecx ; 1 ; open for write
  cmp  byte [eax], 'w'
  je   short open_write
  ;bad mode
file_notfound:
access_error:
  xor  eax, eax ; 0 ; invalid open mode
  retn

open_read:
;Open for read
open_write:
;Open for write
  sys  _open
  ;jc  short file_notfound ; return 0
  jnc  short open_create_ok ; 18/09/2024

  ; 18/09/2024	
open_create:
  or   ecx, ecx
  jz   short file_notfound ; return 0
  ; ecx = 1 -> open for write
  cmp  eax, 2 ; file not found ?
  jne  short access_error
  dec  ecx ; ecx = 0 -> ordinary file
  ; ebx = file name
  sys  _creat	  
  jc   short access_error ; create_err

open_create_ok:
  ; eax = file handle
  ; 15/09/2024
  inc  eax ; file handle (1 based)
.close_ok:
close_ok: ; 12/09/2024
  retn

_OS_fclose:
;Close file
 ;esp+4 - file handle

  mov  ebx, [esp+4] ; file handle (1 based)
  dec  ebx ; 0 based

  sys  _close
  jnc   short close_ok ; eax = 0

.close_err:
read_err:  ; 12/09/2024
  mov  eax, -1 ; BAD
  retn

_OS_fgetc:
;Load char from file
 ;esp+4 - input file

  mov  eax, [esp+4] ; file handle, 1 based
  ; -1 -> STDIN
  inc  eax ; -1 -> 0
  jz   short _OS_getc ; 16/09/2024

  dec  eax ; 1 based
  dec  eax ; 0 based file handle

  mov  byte [character], 0

  sys  _read, eax, character, 1
  jc   short read_err

  and 	eax,eax	
  jnz	short _OS_fgetc_ok	
  dec	eax
  ; eax = -1 ; EOF	
  retn

_OS_fgetc_ok:	
  mov  al, [character]
  retn

_OS_getc:
  sys  _stdio, 0 ; read STDIN (wait keypress)
  ; eax (al) = character (ascii) code
  retn

character: db 0

_OS_fputc:
;Save char to file
 ;esp+4 - output file
 ;esp+8 - char to write

  mov  ecx, [esp+8]
  mov  [character], cl

  mov  eax, [esp+4] ; file handle, 1 based
  ; -1 -> STDOUT/STDERR
  inc  eax ; -1 -> 0
  jz   short _OS_putc_@ ; 16/09/2024
  	
  dec  eax ; 1 based
  dec  eax ; 0 based file handle
  
  sys  _write, eax, character, 1
  retn

_OS_putc:
;Save char to file
 ;esp+4 - char to write

  mov  ecx, [esp+4]
_OS_putc_@:
  ; cl = character to be written
  sys  _stdio, 2 ; write to STDOUT (display char)
calloc_ok: ; 13/09/2024
  retn

_OS_calloc:
;Alloc memory

  ; TRDOS 386 v2 feature
  ; default u.break (bss) address is file size for PRG files

  ; temporary - 23/09/2024
  ;mov  eax,[ubreak]
  ;and  eax,eax
  ;jnz  short ubreak_ready

  sys  _break, -1  ; get u.break address
  jc   short calloc_err

ubreak_ready:	; temporary - 23/09/2024
  ; eax = [u.break]
  add  eax, 3
  and  al, not 3 ; dword aligned allocation (malloc) address

  push eax ; *	
  mov  eax, [esp+8] ; element size (integer=4)
  mov  ebx, [esp+12] ; structure/area length (element count)
  mul  ebx
  ;;;
  ; temporary - 23/09/2024
  ;mov ecx, eax
  ;mov edi,[esp] 
  ;;;
  add  eax, [esp] ; *

  ; new break point - old break point = allocation size

  ; temporary - 23/09/2024
  ;mov  [ubreak],eax
  ;;;
  ; temporary - 23/09/2024
  ;xor eax, eax
  ;rep stosb
  ;;;			
  ;pop  eax ; *
  ;retn		
	
  sys  _break, eax ; set new u.break address
  pop  eax ; * ; 13/09/2024
  ;jc  short .calloc_err

  ; return value
  ; eax = start/beginning address
  ;retn
  ; 13/09/2024
  jnc	short calloc_ok

calloc_err:
  ; write "malloc error" message to STDERR
  mov  esi, .malloc_err_msg
.calloc_err_p:
  lodsb
  or   al, al
  jz   short .calloc_err_x
  sys  _stdio, 3, eax
  jmp  short .calloc_err_p

.calloc_err_x:
  sys  _exit, -1 
  retn ; normally cpu must not come here !

.malloc_err_msg:
  db 0Dh, 0Ah
  db 07h  ; beep !
  db "Memory Allocation Error!"
  db 0Dh, 0Ah, 0

; temporary - 23/09/2024
;ubreak: dd 0

_OS_exit:
  mov	ebx, [esp+4]  ; exit code ; 13/09/2024
  sys  _exit
  retn ; normally cpu must not come here !
