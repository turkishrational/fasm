; -----------------------------------------------------------
; FLAT Assembler for TRDOS 386 (v2.0.9 and later)
; Erdogan Tan - 2024
; Beginning: 04/10/2024
; Last Update: 06/10/2024
; -----------------------------------------------------------
; Modified from 'system.inc' file of
; 'flat assembler 1.73.32 for Linux' source code
; 2024

; flat assembler interface for Linux
; Copyright (c) 1999-2022, Tomasz Grysztar.
; All rights reserved.

;O_ACCMODE  = 0003o
;O_RDONLY   = 0000o
;O_WRONLY   = 0001o
;O_RDWR	    = 0002o
;O_CREAT    = 0100o
;O_EXCL	    = 0200o
;O_NOCTTY   = 0400o
;O_TRUNC    = 1000o
;O_APPEND   = 2000o
;O_NONBLOCK = 4000o
;
;S_ISUID    = 4000o
;S_ISGID    = 2000o
;S_ISVTX    = 1000o
;S_IRUSR    = 0400o
;S_IWUSR    = 0200o
;S_IXUSR    = 0100o
;S_IRGRP    = 0040o
;S_IWGRP    = 0020o
;S_IXGRP    = 0010o
;S_IROTH    = 0004o
;S_IWOTH    = 0002o
;S_IXOTH    = 0001o

init_memory:
	mov	eax,esp
	and	eax,not 0FFFh
	add	eax,1000h-10000h
	mov	[stack_limit],eax
	xor	ebx,ebx
	;mov	eax,45
	;int	0x80
	; TRDOS 386
	dec	ebx
	; ebx = -1
	mov	eax,17 ; sysbreak
	int	0x40
	; eax = current u.break (bss) address
	mov	[additional_memory],eax
	mov	ecx,[memory_setting]
	shl	ecx,10
	jnz	allocate_memory
	mov	ecx,1000000h
      allocate_memory:
	mov	ebx,[additional_memory]
	add	ebx,ecx
	;mov	eax,45
	;int	0x80
	; TRDOS 386
	mov	eax,17 ; sysbreak
	int	0x40
	mov	[memory_end],eax
	sub	eax,[additional_memory]
	shr	eax,2
	add	eax,[additional_memory]
	mov	[additional_memory_end],eax
	mov	[memory_start],eax
	ret

exit_program:
	movzx	ebx,al
	mov	eax,1	; sysexit
	;int	0x80
	; TRDOS 386
	int	0x40

get_environment_variable:

if 0
	mov	ecx,esi
	mov	ebx,[environment]
      next_variable:
	mov	esi,[ebx]
	test	esi,esi
	jz	no_environment_variable
	add	ebx,4
      compare_variable_names:
	mov	edx,ecx
      compare_character:
	lodsb
	mov	ah,[edx]
	inc	edx
	cmp	al,'='
	je	end_of_variable_name
	or	ah,ah
	jz	next_variable
	sub	ah,al
	jz	compare_character
	cmp	ah,20h
	jne	next_variable
	cmp	al,41h
	jb	next_variable
	cmp	al,5Ah
	jna	compare_character
	jmp	next_variable
      no_environment_variable:
	ret
      end_of_variable_name:
	or	ah,ah
	jnz	next_variable
	
      copy_variable_value:
	lodsb
	cmp	edi,[memory_end]
	jae	out_of_memory
	stosb
	or	al,al
	jnz	copy_variable_value
	dec	edi
	ret
else
	; TRDOS 386
	; esi = environment variable address
	; (edi = [memory_start])
	mov	ecx,32 ; max. 32 chars
	mov	ebx,edi
      copy_environment_variable:
 	lodsb
	;cmp	edi,[memory_end]
	;jae	out_of_memory
	stosb
	or	al,al
	jz	short end_of_variable_name
	loop	copy_environment_variable
	mov	byte [edi-1],0
      end_of_variable_name:
	;neg	ecx
	;add	ecx,32
	neg	cl
	add	cl,32
	mov	eax,24	; sysenv
	xor	edx,edx ; dl = 0 -> 256 byte
	int	0x40
	;jc	no_environment_variable
	or	eax,eax
	jz	no_environment_variable
	; eax = string length with zero tail
	mov	ecx,eax
	mov	edi,ebx
	mov	al,'='
	repne	scasb
	jcxz	no_environment_variable
	mov	esi,edi
	; esi = value address of env variable
	mov	edi,ebx
	; (edi = [memory_start])
	rep	movsb ; the last char/byte is 00h
	dec	edi ; except zero tail
	retn
      no_environment_variable:
	mov	edi,ebx
	ret
end if

open:
	;push	esi edi ebp
	push	esi edi
	call	adapt_path
	mov	eax,5
	mov	ebx,buffer
	;mov	ecx,O_RDONLY
	xor	edx,edx
	;int	0x80
	; TRDOS 386
	xor	ecx,ecx ; open for read
	int	0x40
	;pop	ebp edi esi
	pop	edi esi
	;test	eax,eax
	;js	file_error
	jc	file_error ; TRDOS 386
	mov	ebx,eax
	;clc	 ; TRDOS 386
	ret
    adapt_path:
	mov	esi,edx
	mov	edi,buffer
      copy_path:
	lods	byte [esi]
	cmp	al,'\'
	jne	path_char_ok
	mov	al,'/'
      path_char_ok:
	stos	byte [edi]
	or	al,al
	jnz	copy_path
	cmp	edi,buffer+1000h
	ja	out_of_memory
	ret
create:
if 0
	push	esi edi ebp edx
	call	adapt_path
	mov	ebx,buffer
	mov	ecx,O_CREAT+O_TRUNC+O_WRONLY
	mov	edx,S_IRUSR+S_IWUSR+S_IRGRP+S_IROTH
	pop	eax
	cmp	eax,[output_file]
	jne	do_create
	cmp	[output_format],5
	jne	do_create
	bt	[format_flags],0
	jnc	do_create
	or	edx,S_IXUSR+S_IXGRP+S_IXOTH
      do_create:
	mov	eax,5
	int	0x80
	pop	ebp edi esi
	test	eax,eax
	js	file_error
else
	; TRDOS 386
	push	esi edi
	call	adapt_path
	pop	edi esi
	mov	ebx,buffer
	xor	ecx,ecx ; cl = 0 -> ordinary file
	mov	eax,8	; syscreat
	int	0x40
	jc	file_error
end if
	mov	ebx,eax
	;clc	; TRDOS 386
	ret
close:
	; ebx = file handle
	mov	eax,6
	;int	0x80
	; TRDOS 386
	int	0x40
	ret
read:
if 0
	push	ecx edx esi edi ebp
	mov	eax,3
	xchg	ecx,edx
	int	0x80
	pop	ebp edi esi edx ecx
	test	eax,eax
	js	file_error
else
	; TRDOS 386
	; ebx = file handle
	push	ecx edx
	mov	eax,3	 ; sysread
	xchg	ecx,edx
	int	0x40
	pop	edx ecx
	jc	file_error
end if
	;cmp	eax,ecx
	cmp	ecx,eax
	;jne	file_error ; ecx < eax
	;clc
	;ret
    file_error:
	;stc
	ret
write:
if 0
	push	edx esi edi ebp
	mov	eax,4
	xchg	ecx,edx
	int	0x80
	pop	ebp edi esi edx
	test	eax,eax
	js	file_error
	clc
	ret
else
	; TRDOS 386
	; ebx = file handle
	push	ecx edx
	mov	eax, 4	; syswrite
	xchg	ecx,edx
	int	0x40
	pop	edx ecx
	jc	file_error
	cmp	ecx,eax
	;jne	file_error ; ecx < eax
	retn
end if

lseek:
	; ebx = file handle
	mov	ecx,edx
	xor	edx,edx
	mov	dl,al
	mov	eax,19	; sysseek
	;int	0x80
	; TRDOS 386 
	int	0x40
	;cmp	eax,-1
	;je	file_error
	;clc
	;ret
	jc	file_error
	; TRDOS 386
	; Needed for v2.0.9 and previous.
	; systell ; sys _tell,ebx
	mov	eax,20
	int	0x40
	; eax = file offset pointer
	retn

display_string:
if 0
	push	ebx
	mov	edi,esi
	mov	edx,esi
	or	ecx,-1
	xor	al,al
	repne	scasb
	neg	ecx
	sub	ecx,2
	mov	eax,4
	mov	ebx,[con_handle]
	xchg	ecx,edx
	int	0x80
	pop	ebx
	ret
else
	; TRDOS 386
print_msg:
	;push	esi
	push	ebx
print_msg_loop:
	lodsb
	or	al,al
	jz	print_msg_ok
	; TRDOS 386 v2
	;; write tty (ROMBIOS Int 10h simulation)
	;mov	ah,0Eh
	;mov	bx,07h
	;int	31h
	; TRDOS 386 v2.0.9 and later
	mov	cl,al
	;sys	_stdio,3 ; write char to STDERR
	mov	ebx,3
	mov	eax,46 ; sysstdio
	int	0x40
	jmp	print_msg_loop
print_msg_ok:
	pop	ebx
	;pop	esi
	retn
end if

display_character:
	push	ebx
if 0
	mov	[character],dl
	mov	eax,4
	mov	ebx,[con_handle]
	mov	ecx,character
	mov	edx,1
	int	0x80
else
	; TRDOS 386
	;mov	[character],dl
	; TRDOS 386 v2
	;; write tty (ROMBIOS Int 10h simulation)
	;mov	al,[character]
	;mov	al,dl 
	;mov	ah,0Eh
	;mov	bx,07h
	;int	31h
	; TRDOS 386 v2.0.9 and later
	;mov	cl,[character]
	mov	cl,dl
	;sys	_stdio,3 ; write char to STDERR
	mov	ebx,3
	mov	eax,46 ; sysstdio
	int	0x40
end if
	pop	ebx
	ret
display_number:
	push	ebx
	mov	ecx,1000000000
	xor	edx,edx
	xor	bl,bl
      display_loop:
	div	ecx
	push	edx
	cmp	ecx,1
	je	display_digit
	or	bl,bl
	jnz	display_digit
	or	al,al
	jz	digit_ok
	not	bl
      display_digit:
	mov	dl,al
	add	dl,30h
	push	ebx ecx
	call	display_character
	pop	ecx ebx
      digit_ok:
	mov	eax,ecx
	xor	edx,edx
	mov	ecx,10
	div	ecx
	mov	ecx,eax
	pop	eax
	or	ecx,ecx
	jnz	display_loop
	pop	ebx
	ret

display_user_messages:

if 0
	; LINUX
	mov	[displayed_count],0
	call	show_display_buffer
	cmp	[displayed_count],0
	je	line_break_ok
	cmp	[last_displayed],0Ah
	je	line_break_ok
	mov	dl,0Ah
	call	display_character
      line_break_ok:
	ret
display_block:
	jecxz	block_displayed
	add	[displayed_count],ecx
	mov	al,[esi+ecx-1]
	mov	[last_displayed],al
	push	ebx
	mov	eax,4
	mov	ebx,[con_handle]
	mov	edx,ecx
	mov	ecx,esi
	int	0x80
	pop	ebx
      block_displayed:
	ret
else
	; WINDOWS
	mov	[displayed_count],0
	call	show_display_buffer
	cmp	[displayed_count],1
	jb	line_break_ok
	je	make_line_break
	mov	ax,word [last_displayed]
	cmp	ax,0A0Dh
	je	line_break_ok
	cmp	ax,0D0Ah
	je	line_break_ok
      make_line_break:
	; TRDOS 386
	;mov	word [buffer],0A0Dh
	push	ebx
	; TRDOS 386 v2
	; write TTY (ROMBIOS Int 10h simulation)
	;mov	al,0Dh
	;mov	ah,0Eh
	;mov	bx,07h
	;int	31h
	;mov	al,0Ah
	;int	31h
	; TRDOS 386 v2.0.9 and later
	; sys	_stdio,3, 0Dh
	; sys	_stdio,3, 0Ah
	mov	cl,0Dh
	mov	ebx,3 ; write to STDERR
	mov	eax,46 ; sysstdio
	int	0x40
	mov	cl,0Ah
	;mov	ebx,3 ; write to STDERR
	mov	eax,46 ; sysstdio
	;mov	al,46
	int	0x40
	pop	ebx
      line_break_ok:
	ret

display_block:
	; WINDOWS
	add	[displayed_count],ecx
	cmp	ecx,1
	ja	take_last_two_characters
	jb	block_displayed
	mov	al,[last_displayed+1]
	mov	ah,[esi]
	mov	word [last_displayed],ax
	jmp	block_ok
      take_last_two_characters:
	mov	ax,[esi+ecx-2]
	mov	word [last_displayed],ax
      block_ok:
	; WINDOWS
	;push	ecx
	;push	[con_handle]
	;call	[GetStdHandle]
	;pop	ecx
	;push	0
	;push	bytes_count
	;push	ecx
	;push	esi
	;push	eax
	;call	[WriteFile]
	; LINUX
	;push	ebx
	;mov	eax,4
	;mov	ebx,[con_handle]
	;mov	edx,ecx
	;mov	ecx,esi
	;int	0x80
	;pop	ebx
	; DOS
        ;display_character:
	;lods	byte [esi]
	;mov	dl,al
	;mov	ah,2
	;int	21h
	;loopd	display_character
	;ret
	; TRDOS 386
	; sys _msg, esi, ecx, 07h
	; ecx = character/byte count
	;mov	ebx,esi ; buffer
	;mov	edx,07h ; color
	;mov	eax,35 ; sysmsg
	;int	0x40 ; TRDOS 386 system call	

	; TRDOS 386 v2.0.9 and later
	; systdio - write a char to STDERR
	mov	ebx,3	; write to STDERR
      write_to_stderr_loop:
	push	ecx
	lods	byte [esi] ; lodsb	
	mov	cl,al
	mov	eax,46	; sysstdio
	;mov	ebx,3	; write to STDERR
	;sys	_stdio,3	
	int	0x40	; TRDOS 386 system call
	pop	ecx
	loop	write_to_stderr_loop

      block_displayed:
	ret

end if

fatal_error:
	; [esp] = error message address
	; TRDOS 386
	;mov	[con_handle],2
	mov	esi,error_prefix
	call	display_string
	pop	esi
	call	display_string
	mov	esi,error_suffix
	call	display_string
	mov	al,0FFh
	jmp	exit_program
assembler_error:
	; TRDOS 386
	;mov	[con_handle],2
	call	display_user_messages
	mov	ebx,[current_line]
	test	ebx,ebx
	jz	display_error_message
	pushd	0
      get_error_lines:
	mov	eax,[ebx]
	cmp	byte [eax],0
	je	get_next_error_line
	push	ebx
	test	byte [ebx+7],80h
	jz	display_error_line
	mov	edx,ebx
      find_definition_origin:
	mov	edx,[edx+12]
	test	byte [edx+7],80h
	jnz	find_definition_origin
	push	edx
      get_next_error_line:
	mov	ebx,[ebx+8]
	jmp	get_error_lines
      display_error_line:
	mov	esi,[ebx]
	call	display_string
	mov	esi,line_number_start
	call	display_string
	mov	eax,[ebx+4]
	and	eax,7FFFFFFFh
	call	display_number
	mov	dl,']'
	call	display_character
	pop	esi
	cmp	ebx,esi
	je	line_number_ok
	mov	dl,20h
	call	display_character
	push	esi
	mov	esi,[esi]
	movzx	ecx,byte [esi]
	inc	esi
	call	display_block
	mov	esi,line_number_start
	call	display_string
	pop	esi
	mov	eax,[esi+4]
	and	eax,7FFFFFFFh
	call	display_number
	mov	dl,']'
	call	display_character
      line_number_ok:
	mov	esi,line_data_start
	call	display_string
	mov	esi,ebx
	mov	edx,[esi]
	call	open
	mov	al,2
	xor	edx,edx
	call	lseek
	mov	edx,[esi+8]
	sub	eax,edx
	jz	line_data_displayed
	push	eax
	xor	al,al
	call	lseek
	;mov	ecx,[esp]
	; TRDOS 386
	pop	ecx
	mov	edx,[additional_memory]
	lea	eax,[edx+ecx]
	cmp	eax,[additional_memory_end]
	ja	out_of_memory
	; TRDOS 386
	;push	ecx
	call	read
	call	close
	;pop	ecx
	mov	esi,[additional_memory]
      get_line_data:
	mov	al,[esi]
	cmp	al,0Ah
	je	display_line_data
	cmp	al,0Dh
	je	display_line_data
	cmp	al,1Ah
	je	display_line_data
	or	al,al
	jz	display_line_data
	inc	esi
	loop	get_line_data
      display_line_data:
	mov	ecx,esi
	mov	esi,[additional_memory]
	sub	ecx,esi
	call	display_block
      line_data_displayed:
	; LINUX
	;mov	esi,lf
	; WINDOWS & TRDOS 386
	mov	esi,cr_lf
	call	display_string
	pop	ebx
	or	ebx,ebx
	jnz	display_error_line
	cmp	[preprocessing_done],0
	je	display_error_message
	mov	esi,preprocessed_instruction_prefix
	call	display_string
	mov	esi,[current_line]
	add	esi,16
	mov	edi,[additional_memory]
	xor	dl,dl
      convert_instruction:
	lodsb
	cmp	al,1Ah
	je	copy_symbol
	cmp	al,22h
	je	copy_symbol
	cmp	al,3Bh
	je	instruction_converted
	stosb
	or	al,al
	jz	instruction_converted
	xor	dl,dl
	jmp	convert_instruction
      copy_symbol:
	or	dl,dl
	jz	space_ok
	mov	byte [edi],20h
	inc	edi
      space_ok:
	cmp	al,22h
	je	quoted
	lodsb
	movzx	ecx,al
	rep	movsb
	or	dl,-1
	jmp	convert_instruction
      quoted:
	mov	al,27h
	stosb
	lodsd
	mov	ecx,eax
	jecxz	quoted_copied
      copy_quoted:
	lodsb
	stosb
	cmp	al,27h
	jne	quote_ok
	stosb
      quote_ok:
	loop	copy_quoted
      quoted_copied:
	mov	al,27h
	stosb
	or	dl,-1
	jmp	convert_instruction
      instruction_converted:
	xor	al,al
	stosb
	mov	esi,[additional_memory]
	call	display_string
	;mov	esi,lf
	; TRDOS 386
	mov	esi,cr_lf
	call	display_string
      display_error_message:
	mov	esi,error_prefix
	call	display_string
	pop	esi
	call	display_string
	mov	esi,error_suffix
	call	display_string
	mov	al,2
	jmp	exit_program

make_timestamp:
	mov	eax,13
	; LINUX
	;mov	ebx,timestamp
	;int	0x80
	;mov	eax,dword [timestamp]
	;mov	edx,dword [timestamp+4]
	; TRDOS 386
	;mov	ebx,0
	xor 	ebx,ebx ; get UNIX/EPOCH timestamp
	int	0x40	; eax = 13 -> systime
	; eax = timestamp
	xor	edx,edx
	ret

error_prefix db 'error: ',0
error_suffix db '.'
;lf db 0xA,0
; TRDOS 386 (& WINDOWS)
cr_lf db 0Dh,0Ah,0
line_number_start db ' [',0
;line_data_start db ':',0xA,0
line_data_start db ':',0Dh,0Ah,0
preprocessed_instruction_prefix db 'processed: ',0
