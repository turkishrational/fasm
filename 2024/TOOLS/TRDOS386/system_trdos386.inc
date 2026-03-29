; -----------------------------------------------------------
; LISTING.PRG - FLAT Assembler Listing for TRDOS 386 (v2.0.9)
; Erdogan Tan - 2024
; Beginning: 08/10/2024
; Last Update: 09/10/2024
; -----------------------------------------------------------
; Modified from 'tools/libc/system.inc' file of
; 'flat assembler 1.73.32 for Linux' source code
; 2024

;extrn malloc
;extrn getenv
;extrn fopen
;extrn fclose
;extrn fread
;extrn fwrite
;extrn fseek
;extrn ftell
;extrn time
;extrn exit
;extrn 'free' as libc_free
;extrn 'write' as libc_write

alloc:
	;ccall	malloc,eax
	push	ebx eax
	;sys _break,-1  ; get u.break address
	mov	ebx,-1
	mov	eax,17	; sysbreak
	int	40h
	pop 	ebx  ; allocation size
  	jc	malloc_error

	;;;
	; ! (not necessary) !
	;sysalloc ; allocate (contiguous) memory pages
	push	ecx
	push	ebx
	push	eax
	xchg	eax,ebx
	; ebx = current [u.break]
	;     = start (virtual) addr to be allocated 
	mov	ecx,eax ; allocation byte count
	mov	eax,42  ; sysalloc
	int	40h
	; result not important !
	; (TRDOS 386 kernel will allocate memory pages
	; to this program/process when a write access
	; to an unallocated page causes a page fault.)
	; (Demand Paging principle.)
	pop	eax
	pop	ebx
	pop	ecx
	;;;

	; eax = [u.break]
	add 	eax,3
	and	al,not 3
	push	eax
	add	ebx,eax
	; ebx = new [u.break]
	;sys _break
	mov	eax,17	; sysbreak
	int	40h
	pop	eax
	;jc	malloc_error
	;test	eax,eax
	;jz	allocation_failed
	;clc
	;ret
      ;allocation_failed:
	;stc
	;ret
      malloc_error:
	pop	ebx
	ret
free:
	;ccall	libc_free,eax
	push	ebx eax
	;sys _break,-1	; get u.break address
	mov	ebx,-1
	mov	eax,17	; sysbreak
	int	40h
	pop 	ebx  ; old [u.break]
  	jc	malloc_error
	; eax = current [u.break]

	cmp	eax, ebx
	jna	short already_free ; nothing to do

	;;;
	; ! (not necessary) !
	;sysdalloc ; deallocate user's memory pages
	push	ecx
	mov	ecx,eax
	sub	ecx,ebx ; deallocation byte count
	; ebx = virtual (start) addr to be deallocated
	mov	eax,43  ; sysdalloc
	int	40h
	; result not important !
	; (TRDOS 386 kernel will deallocate this
	; program's mem pages when this program/process
	; is terminated.)
	pop	ecx
	;;;

	;sys _break
	; ebx = new [u.break] 
	mov	eax,17 ; sysbreak
	int	0x40

      already_free:
	pop	ebx
      string_displayed:
	ret

display_string:
	lodsb
	or	al,al
	jz	string_displayed
	;mov	dl,al
	call	display_character
	jmp	display_string
      ;string_displayed:
	;ret
    display_character:
	;mov	[character],dl
	;ccall	libc_write,[display_handle],character,1
	;mov	cl,dl
	mov	cl,al
	mov	ebx,2	; STDOUT
	mov	eax,46  ; sysstdio
	int	40h
	ret
open:
	mov	eax,5	; sysopen
open_create_@:
	;push	esi edi ebp
	push	esi edi
	push	eax
	call	adapt_path
	;ccall	fopen,buffer,open_mode
	;mov	eax,5	; sysopen
	pop	eax
	mov	ebx,buffer
	sub	ecx,ecx ; open for read
	int	40h
	;pop	ebp edi esi
	pop	edi esi
	;or	eax,eax
	;jz	file_error
	jc	file_error
	mov	ebx,eax
	;clc
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
	ja	not_enough_memory
    file_error:
	ret
create:
	mov	eax,8	; syscreat
	jmp	open_create_@
	;;push	esi edi ebp
	;push	esi edi
	;call	adapt_path
	;ccall	fopen,buffer,create_mode
	;mov	eax,8	; syscreat
	;mov	ebx,buffer
	;xor	ecx,ecx ; ordinary file
	;int	40h
	;;pop	ebp edi esi
	;pop	edi esi
	;;or	eax,eax
	;;jz	file_error
	;jc	file_error
	;mov	ebx,eax
	;;clc
	;ret
close:
	;ccall	fclose,ebx
	; ebx = file handle
	mov	eax,6	; sysclose
	int	40h
	ret
read:
	;push	ebx ecx edx esi edi
	push	ecx edx
	;ccall	fread,edx,1,ecx,ebx
	; edx = buffer
	; ecx = byte count
	; ebx = file handle
	mov	eax,3	; sysread
	xchg	ecx,edx
	int	40h
	;pop	edi esi edx ecx ebx
	pop	edx ecx
	jc	file_error
	cmp	eax,ecx
	;jne	file_error ; eax < ecx
	;;clc
	;ret
    ;file_error:
	;stc
	ret
write:
	;push	ebx ecx edx esi edi
	push	ecx edx
	;ccall	fwrite,edx,1,ecx,ebx
	; edx = buffer
	; ecx = byte count
	; ebx = file handle
	mov	eax,4	; syswrite
	xchg	ecx,edx
	int	40h
	;pop	edi esi edx ecx ebx
	pop	edx ecx
	cmp	eax,ecx
	;jne	file_error ; eax < ecx
	;clc
	ret
lseek:
	;push	ebx
	movzx	eax,al
	;ccall	fseek,ebx,edx,eax
	mov	ecx,edx
	mov	edx,eax
	;mov	eax,19
	mov	al,19	; sysseek
	int	40h
	;mov	ebx,[esp]
	;ccall	ftell,ebx
	mov	eax,20	; systell
	int	40h
	;pop	ebx
	ret

;open_mode db 'r',0
;create_mode db 'w',0
