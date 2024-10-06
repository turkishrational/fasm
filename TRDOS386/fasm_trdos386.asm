; -----------------------------------------------------------
; FASM.PRG - FLAT Assembler for TRDOS 386 (v2.0.9 and later)
; Erdogan Tan - 2024
; Beginning: 04/10/2024
; Last Update: 06/10/2024
; -----------------------------------------------------------
; Modified from 'fasm.asm' file of
; 'flat assembler 1.73.32 for Linux' source code
; 2024


; flat assembler interface for Linux
; Copyright (c) 1999-2022, Tomasz Grysztar.
; All rights reserved.

	;format	ELF executable 3
	;entry	start

;segment readable executable

	; TRDOS 386
	use32
	org 0x0
start:
	;mov	[con_handle],1
	mov	esi,_logo
	call	display_string

	; LINUX & TRDOS 386
	mov	[command_line],esp
	; TRDOS 386
	;mov	ecx,[esp]
	;lea	ebx,[esp+4+ecx*4+4]
	;mov	[environment],ebx
	call	get_params
	jc	information

	call	init_memory

	mov	esi,_memory_prefix
	call	display_string
	mov	eax,[memory_end]
	sub	eax,[memory_start]
	add	eax,[additional_memory_end]
	sub	eax,[additional_memory]
	shr	eax,10
	call	display_number
	mov	esi,_memory_suffix
	call	display_string

	;mov	eax,78
	;mov	ebx,buffer
	;xor	ecx,ecx
	;int	0x80
	;mov	eax,dword [buffer]
	;mov	ecx,1000
	;mul	ecx
	;mov	ebx,eax
	;mov	eax,dword [buffer+4]
	;div	ecx
	;add	eax,ebx
	; TRDOS 386
	mov	eax,13  ; systime
	sub	ebx,ebx ; 0 -> get unix/epoch time
	int	0x40
	mov	[start_time],eax

	and	[preprocessing_done],0
	call	preprocessor
	or	[preprocessing_done],-1
	call	parser
	call	assembler
	call	formatter

	call	display_user_messages
	movzx	eax,[current_pass]
	inc	eax
	call	display_number
	mov	esi,_passes_suffix
	call	display_string
	
	;mov	eax,78
	;mov	ebx,buffer
	;xor	ecx,ecx
	;int	0x80
	;mov	eax,dword [buffer]
	;mov	ecx,1000
	;mul	ecx
	;mov	ebx,eax
	;mov	eax,dword [buffer+4]
	;div	ecx
	;add	eax,ebx
	; TRDOS 386
	mov	eax,13  ; systime
	sub	ebx,ebx ; 0 -> get unix/epoch time
	int	0x40
		
	sub	eax,[start_time]
	;jnc	time_ok
	;;add	eax,3600000
	;add	eax,3600
	time_ok:
	;xor	edx,edx
	;mov	ebx,100
	;div	ebx
	;or	eax,eax
	;jz	display_bytes_count
	; TRDOS 386
	cmp	eax,2
	jb	display_bytes_count

	;xor	edx,edx
	;mov	ebx,10
	;div	ebx
	;push	edx
	;call	display_number
	;mov	dl,'.'
	;call	display_character
	;pop	eax
	call	display_number
	mov	esi,_seconds_suffix
	call	display_string
      display_bytes_count:
	mov	eax,[written_size]
	call	display_number
	mov	esi,_bytes_suffix
	call	display_string
	xor	al,al
	jmp	exit_program

information:
	mov	esi,_usage
	call	display_string
	mov	al,1
	jmp	exit_program

get_params:
	mov	ebx,[command_line] ; argc
	mov	[input_file],0
	mov	[output_file],0
	mov	[symbols_file],0
	mov	[memory_setting],0
	mov	[passes_limit],100
	mov	ecx,[ebx] ; argc
	add	ebx,8	; argv[1] ; argv[0] is program file's name
	dec	ecx
	jz	bad_params
	mov	[definitions_pointer],predefinitions
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
	cmp	al,'m'
	je	memory_option
	cmp	al,'M'
	je	memory_option
	cmp	al,'p'
	je	passes_option
	cmp	al,'P'
	je	passes_option
	cmp	al,'d'
	je	definition_option
	cmp	al,'D'
	je	definition_option
	cmp	al,'s'
	je	symbols_option
	cmp	al,'S'
	je	symbols_option
      bad_params:
	stc
	ret
      memory_option:
	cmp	byte [esi],0
	jne	get_memory_setting
	dec	ecx
	jz	bad_params
	add	ebx,4
	mov	esi,[ebx]
      get_memory_setting:
	call	get_option_value
	or	edx,edx
	jz	bad_params
	cmp	edx,1 shl (32-10)
	jae	bad_params
	mov	[memory_setting],edx
	jmp	next_param
      passes_option:
	cmp	byte [esi],0
	jne	get_passes_setting
	dec	ecx
	jz	bad_params
	add	ebx,4
	mov	esi,[ebx]
      get_passes_setting:
	call	get_option_value
	or	edx,edx
	jz	bad_params
	cmp	edx,10000h
	ja	bad_params
	mov	[passes_limit],dx
      next_param:
	add	ebx,4
	dec	ecx
	jnz	get_param
	cmp	[input_file],0
	je	bad_params
	mov	eax,[definitions_pointer]
	mov	byte [eax],0
	mov	[initial_definitions],predefinitions
	clc
	ret
      definition_option:
	cmp	byte [esi],0
	jne	get_definition
	dec	ecx
	jz	bad_params
	add	ebx,4
	mov	esi,[ebx]
      get_definition:
	push	edi
	mov	edi,[definitions_pointer]
	call	convert_definition_option
	mov	[definitions_pointer],edi
	pop	edi
	jc	bad_params
	jmp	next_param
      symbols_option:
	cmp	byte [esi],0
	jne	get_symbols_setting
	dec	ecx
	jz	bad_params
	add	ebx,4
	mov	esi,[ebx]
      get_symbols_setting:
	mov	[symbols_file],esi
	jmp	next_param
      get_option_value:
	xor	eax,eax
	mov	edx,eax
      get_option_digit:
	lodsb
	cmp	al,20h
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
	;clc	; TRDOS 386
	ret
      invalid_option_value:
	stc
      invalid_option_value2: ; TRDOS 386
	ret
      convert_definition_option:
	mov	edx,edi
	cmp	edi,predefinitions+1000h
	jae	bad_definition_option
	xor	al,al
	stosb
      copy_definition_name:
	lodsb
	cmp	al,'='
	je	copy_definition_value
	cmp	al,20h
	je	bad_definition_option
	or	al,al
	jz	bad_definition_option
	cmp	edi,predefinitions+1000h
	jae	bad_definition_option
	stosb
	inc	byte [edx]
	jnz	copy_definition_name
      bad_definition_option:
	stc
	ret
      copy_definition_value:
	lodsb
	cmp	al,20h
	je	definition_value_end
	or	al,al
	jz	definition_value_end
	cmp	edi,predefinitions+1000h
	jae	bad_definition_option
	stosb
	jmp	copy_definition_value
      definition_value_end:
	dec	esi
	cmp	edi,predefinitions+1000h
	jae	bad_definition_option
	xor	al,al
	stosb
	;clc	 ; TRDOS 386
	ret

include 'system.inc'

include '..\version.inc'

_copyright db 'Copyright (c) 1999-2022, Tomasz Grysztar',0xA,0

_logo db 'flat assembler  version ',VERSION_STRING,0
; LINUX
;_usage db 0xA
;      db 'usage: fasm <source> [output]',0xA
;      db 'optional settings:',0xA
;      db ' -m <limit>         set the limit in kilobytes for the available memory',0xA
;      db ' -p <limit>         set the maximum allowed number of passes',0xA
;      db ' -d <name>=<value>  define symbolic variable',0xA
;      db ' -s <file>          dump symbolic information for debugging',0xA
;      db 0
; WINDOWS & TRDOS 386
_usage db 0Dh,0Ah
       db 'usage: fasm <source> [output]',0Dh,0Ah
       db 'optional settings:',0Dh,0Ah
       db ' -m <limit>         set the limit in kilobytes for the available memory',0Dh,0Ah
       db ' -p <limit>         set the maximum allowed number of passes',0Dh,0Ah
       db ' -d <name>=<value>  define symbolic variable',0Dh,0Ah
       db ' -s <file>          dump symbolic information for debugging',0Dh,0Ah
       db 0

_memory_prefix db '  (',0
; LINUX
;_memory_suffix db ' kilobytes memory)',0xA,0
; TRDOS 386 (& WINDOWS)
_memory_suffix db ' kilobytes memory)',0Dh,0Ah,0
_passes_suffix db ' passes, ',0
_seconds_suffix db ' seconds, ',0
; LINUX
;_bytes_suffix db ' bytes.',0xA,0
; TRDOS 386 (& WINDOWS)
_bytes_suffix db ' bytes.',0Dh,0Ah,0

include '..\errors.inc'
include '..\symbdump.inc'
include '..\preproce.inc'
include '..\parser.inc'
include '..\exprpars.inc'
include '..\assemble.inc'
include '..\exprcalc.inc'
include '..\formats.inc'
include '..\x86_64.inc'
include '..\avx.inc'

include '..\tables.inc'
include '..\messages.inc'

;segment readable writeable

align 4

include '..\variable.inc'

command_line dd ?
memory_setting dd ?
definitions_pointer dd ?
environment dd ?
timestamp dq ?
start_time dd ?
; TRDOS 386
;con_handle dd ?
displayed_count dd ?
last_displayed db ?
character db ?
preprocessing_done db ?

predefinitions rb 1000h
buffer rb 1000h

program db 0Dh,0Ah
	db "Flat Asssembler for TRDOS 386 v2"
	db 0Dh,0Ah
	db "Erdogan Tan - October 2024"
	db 0Dh,0Ah,0