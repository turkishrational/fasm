; -----------------------------------------------------------
; PREPSRC.PRG - FLAT Assembler PREPSRC for TRDOS 386 (v2.0.9)
; Erdogan Tan - 2024
; Beginning: 09/10/2024
; Last Update: 09/10/2024
; -----------------------------------------------------------
; Modified from 'tools/libc/prepsrc.asm' file of
; 'flat assembler 1.73.32 for Linux' source code
; 2024

	;format	ELF
	;public	main

	format	binary

;include 'ccall.inc'

;section '.text' executable align 16

	use32
	org 0x0

  main:
	mov	ebx, bss_end
	mov	eax, 17 ; sysbreak
	int	40h
	;;;

	;mov	ecx,[esp+4]
	mov	ecx,[esp]
	;mov	[argc],ecx
	;mov	ebx,[esp+8]
	lea	ebx,[esp+4]
	;mov	[argv],ebx

	;mov	[display_handle],1

	call	get_params
	jnc	make_dump

	mov	esi,_usage
	call	display_string
	;ccall	exit,2
	mov	eax,1 ; sysexit
	mov	ebx,2
	int	40h

  make_dump:
	call	preprocessed_source
   error_@:
	;ccall	exit,0
	mov	eax,1 ; sysexit
	;mov	ebx,0
	sub	ebx,ebx
	int	40h

  error:
	;mov	[display_handle],2
	mov	esi,_error_prefix
	call	display_string
	pop	esi
	call	display_string
	mov	esi,_error_suffix
	call	display_string
	;;ccall	exit,0
	;mov	eax,1 ; sysexit
	;;mov	ebx,0
	;xor	ebx,ebx
	;int	40h
	jmp	error_@

  get_params:
	;mov	ecx,[argc]
	;mov	ebx,[argv]
	add	ebx,4
	dec	ecx
	jz	bad_params
      get_param:
	mov	esi,[ebx]
	mov	al,[esi]
	cmp	[input_file],0
	jne	get_output_file
	mov	[input_file],esi
	jmp	next_param
      get_output_file:
	cmp	[output_file],0
	jne	bad_params
	mov	[output_file],esi
	jmp	next_param
      bad_params:
	stc
	ret
      next_param:
	add	ebx,4
	dec	ecx
	jnz	get_param
	cmp	[input_file],0
	je	bad_params
	cmp	[output_file],0
	je	bad_params
	;clc
	ret

  include 'system.inc'

  include '..\prepsrc.inc'

;section '.data' writeable align 4

  input_file dd 0
  output_file dd 0

  _usage db 'preprocessed source dumper for flat assembler',0Dh,0Ah
	 db 'usage: prepsrc <input> <output>',0Dh,0Ah
	 db 0
  _error_prefix db 'error: ',0
  _error_suffix db '.',0Dh,0Ah,0

;section '.bss' writeable align 4

  ;argc dd ?
  ;argv dd ?

  ;display_handle dd ?
  ;character db ?

  params rb 1000h
  buffer rb 1000h

bss_end:
