; -----------------------------------------------------------
; LISTING.PRG - FLAT Assembler Listing for TRDOS 386 (v2.0.9)
; Erdogan Tan - 2024
; Beginning: 08/10/2024
; Last Update: 09/10/2024
; -----------------------------------------------------------
; Modified from 'tools/libc/listing.asm' file of
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
	jnc	make_listing

	mov	esi,_usage
	call	display_string
	;ccall	exit,2
	mov	eax,1 ; sysexit
	mov	ebx,2
	int	40h

  make_listing:
	call	listing
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
	cmp	al,'-'
	je	option_param
	cmp	[input_file],0
	jne	get_output_file
	mov	[input_file],esi
	jmp	next_param
      get_output_file:
	cmp	[output_file],0
	jne	bad_params
	mov	[output_file],esi
	jmp	next_param
      option_param:
	inc	esi
	lodsb
	cmp	al,'a'
	je	addresses_option
	cmp	al,'A'
	je	addresses_option
	cmp	al,'b'
	je	bytes_per_line_option
	cmp	al,'B'
	je	bytes_per_line_option
      bad_params:
	stc
	ret
      addresses_option:
	cmp	byte [esi],0
	jne	bad_params
	mov	[show_addresses],1
	jmp	next_param
      bytes_per_line_option:
	cmp	byte [esi],0
	jne	get_bytes_per_line_setting
	dec	ecx
	jz	bad_params
	add	ebx,4
	mov	esi,[ebx]
      get_bytes_per_line_setting:
	call	get_option_value
	or	edx,edx
	jz	bad_params
	cmp	edx,1000
	ja	bad_params
	mov	[code_bytes_per_line],edx
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
      get_option_value:
	xor	eax,eax
	mov	edx,eax
      get_option_digit:
	lodsb
	cmp	al,20h
	je	option_value_ok
	cmp	al,0Dh
	je	option_value_ok
	or	al,al
	jz	option_value_ok
	sub	al,30h
	jc	invalid_option_value2
	cmp	al,9
	ja	invalid_option_value
	imul	edx,10
	jo	invalid_option_value
	add	edx,eax
	jc	invalid_option_value2
	jmp	get_option_digit
      option_value_ok:
	dec	esi
	;clc
	ret
      invalid_option_value:
	stc
      invalid_option_value2:
	ret

  include 'system.inc'

  include '..\listing.inc'

;section '.data' writeable align 4

  input_file dd 0
  output_file dd 0
  code_bytes_per_line dd 16
  show_addresses db 0

  line_break db 0Dh,0Ah

  _usage db 'listing generator for flat assembler',0Dh,0Ah
	 db 'usage: listing <input> <output>',0Dh,0Ah
	 db 'optional settings:',0Dh,0Ah
	 db ' -a           show target addresses for assembled code',0Dh,0Ah
	 db ' -b <number>  set the amount of bytes listed per line',0Dh,0Ah
	 db 0
  _error_prefix db 'error: ',0
  _error_suffix db '.',0Dh,0Ah,0

;section '.bss' writeable align 4

  ;argc rd 1
  ;argv rd 1

  input rd 1
  assembled_code rd 1
  assembled_code_length rd 1
  code_end rd 1
  code_offset rd 1
  code_length rd 1
  output_handle rd 1
  output_buffer rd 1
  current_source_file rd 1
  current_source_line rd 1
  source rd 1
  source_length rd 1
  maximum_address_length rd 1
  address_start rd 1
  last_listed_address rd 1

  ;display_handle rd 1
  ;character rb 1

  params rb 1000h
  characters rb 100h
  buffer rb 1000h

bss_end:
