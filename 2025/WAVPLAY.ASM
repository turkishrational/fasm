; ****************************************************************************
; WAVPLAY.EXE - WAVE PLAYER 1.0 for WINDOWS (console)
; ----------------------------------------------------------------------------
;
; Erdogan Tan - 22/10/2024
;
; [ Last Modification: 26/10/2024 ]
;
; ****************************************************************************
; Derived from:
;   * MP3PLAY.ASM (Erdogan Tan, 22/10/2024, Windows Console Program, FASM)
;     ((Based on NOCASH MP3 DECODER/PLAYER v1.4 source code by Martin Korth))
;   * MP3PLAY2.ASM (Erdogan Tan, 22/10/2024,TRDOS 386 Program, FASM)
;   * PLAYWAV6.S (Erdogan Tan, 01/06/2024, TRDOS 386 program, NASM)
;
; Note: 
; Writing purpose of this program is to correct defects on MP3PLAY2.ASM.
; (In order to understand whats must be done to play mp3 file correctly.)
;
; Assembly language syntax: Flat Assembler (FASM)
; -------------------------
; command: fasm wavplay.asm
; -------------------------

                format PE console
                use32
                entry start

; ---------------------------------------------------------------------------

struc		wavehdr_tag a
 {
   .lpData          dd a
   .dwBufferLength  dd a
   .dwBytesRecorded dd a
   .dwUser          dd a
   .dwFlags         dd a
   .dwLoops         dd a
   .lpNext          dd a
   .reserved        dd a
 }

; ---------------------------------------------------------------------------

struc		WAVEFORMATEX a,b,c,d,e,f,g
 { 
   .wFormatTag      dw a
   .nChannels       dw b
   .nSamplesPerSec  dd c
   .nAvgBytesPerSec dd d
   .nBlockAlign     dw e
   .wBitsPerSample  dw f
   .cbSize          dw g
 }


; ---------------------------------------------------------------------------

struc		WAVFILEHDR
 {
   .riff	resd 1	; "RIFF"
   .filesize	resd 1	; Overall file size - 8 bytes
   .wave	resd 1	; "WAVE"  
   .fmt		resd 1	; "fmt "
   .lriffhdr	resd 1	; 16 (length of format data listed above)
   .pcm		resw 1	; 1 = PCM
   .channels	resw 1	; number of channels (2 = stereo)
   .samplerate	resd 1	; sample rate (44100, 48000 ...) in Hertz
   .blocksize	resd 1	; (Sample Rate * BitsPerSample * Channels) / 8
   .bytesps	resw 1	; (BytesPerSample * Channels) -> 4 = 16 bit stereo
   .bits	resw 1	; BitsPerSample -> 16 or 8
   .data	resd 1	; "data" (chunk header, beginning of data section)
   .datasize	resd 1	; data size (file size - header size)
   .size		; 44 bytes
 }

; ===========================================================================

section '.text' code readable executable

start:
                push    0FFFFFFF5h      ; nStdHandle
                call    [GetStdHandle]
                ;invoke GetStdHandle, STD_OUTPUT_HANDLE
                mov     [std_out], eax
                mov     edx, txt_hello
                call    wrstr_edx

                call    get_commandline
                jc      .exit

                call    open_and_mmap_input_file
                jc      .exit

                call    detect_cpu_386_and_up

		; If input is a PCM file, sample rate, bits per sample
		; and number of channels will be set according to
                ; /F:,/B:,/C: switches.
		; If input is a WAV file, parameters will be set
		; according to the file header.
		call	read_wav_file_header
		jc	.unmap_close_exit

		call	prepare_output_parms

		call	input_file_info

		;call   xmit_get_priority_defaults

                call    [GetTickCount]
                neg     eax
                mov     [millisecond_count], eax

                cmp     [option_test], 0
                jnz     short .done

.no_benchmark_test:
		cmp	dword [wav_dst_fname], 0
		jz	short .no_wav_output 
		cmp	byte [wav_output], 0
		jnz	short .wav_output
.pcm_output:
                call    cast_to_pcm_file
                jmp     short .done

.wav_output:
                call    cast_to_wav_file
                jmp     short .done

.no_wav_output:
		;call   xmit_force_highest_priority

                call    cast_to_speaker

		;call   xmit_resume_normal_priority
.done:
                call    [GetTickCount]
                add     [millisecond_count], eax
                mov     edx, txt_pefform_timing1 ; "audio duration "
                call    wrstr_edx
		; 26/10/2024
                mov     eax, [wav_total_input_size]
                mov     edx, 1000
                mul     edx
                div     [wav_input_sample_rate]
                xor     edx, edx
                div     [wav_input_num_channels]
                xor     edx, edx
                div     [wav_input_bytes_per_sample]
                mov     [output_milliseconds], eax
                call    wr_decimal_eax_with_thousands_seperator
                mov     edx, txt_perform_timing2 ; " milliseconds, performed in "
                call    wrstr_edx
                mov     eax, [millisecond_count]
                call    wr_decimal_eax_with_thousands_seperator
                mov     edx, txt_decode_timing3 ; " milliseconds\r\n"
                call    wrstr_edx
                mov     edx, txt_clks_per_second ; " clock cycles per second:\r\n"
                call    wrstr_edx
                mov     esi, rdtsc_interpolat ; rdtsc_list_start

.timelog_lop:
                call    wrspc
                lea     edx, [esi+8]
                call    wrstr_edx
                call    wrspc
                mov     eax, [esi]
                mov     ebx, [esi+4]

		add	[rdtsc_total], eax
		adc	[rdtsc_total+4], ebx

                mov     edx, 1000
                imul    ebx, edx
                mul     edx
                add     edx, ebx
                cmp     edx, [output_milliseconds]
                jnb     short .timelog_oops
                div     [output_milliseconds]
                call    wr_decimal_eax_with_thousands_seperator

.timelog_oops:
                call    wrcrlf
                add     esi, rdtsc_element_size
                cmp     esi, rdtsc_interpolat+rdtsc_list_size
                jb      short .timelog_lop

.unmap_close_exit:
		call	unmap_and_close_input

.exit:
                push    0               ; uExitCode
                call    [ExitProcess]


; =============== S U B R O U T I N E =======================================


detect_cpu_386_and_up:
                mov     [detected_cpu], 3
                mov     ebx, esp
                and     esp, not 3
                pushf
                pop     eax
                mov     ecx, eax
                xor     eax, 40000h
                push    eax
                popf
                pushf
                pop     eax
                xor     eax, ecx
                push    ecx
                popf
                mov     esp, ebx
                test    eax, 40000h
                jz      short .no_id
                inc     [detected_cpu]
                call    @@get_id_flag
                jnz     short .yep_id
                call    @@get_id_flag
                jz      short .no_id

.yep_id:
                mov     eax, 1
                cpuid
                and     ah, 0Fh
                mov     [detected_cpu], ah
                mov     [cpuid_exists], 1
                mov     [cpuid_flags], edx

.no_id:
                retn

; =============== S U B R O U T I N E =======================================


@@get_id_flag:
                pushf
                pop     eax
                or      eax, 200000h
                push    eax
                popf
                pushf
                pop     eax
                test    eax, 200000h
                retn

; =============== S U B R O U T I N E =======================================

if 0

xmit_get_priority_defaults:
                pusha
                call    [GetCurrentProcess]
                mov     [hProcess], eax
                call    [GetCurrentThread]
                mov     [hThread], eax
                push    [hProcess]   ; hProcess
                call    [GetPriorityClass]
                mov     [dwPriorityClass], eax
                push    [hThread]    ; hThread
                call    [GetThreadPriority]
                mov     [nPriority], eax
                popa
                retn

end if

; =============== S U B R O U T I N E =======================================

if 0

xmit_resume_normal_priority:
                pusha
                push    [dwPriorityClass] ; dwPriorityClass
                push    [hProcess]   ; hProcess
                call    [SetPriorityClass]
                push    [nPriority]  ; nPriority
                push    [hThread]    ; hThread
                call    [SetThreadPriority]
                popa
                retn
end if

; =============== S U B R O U T I N E =======================================

if 0

xmit_force_highest_priority:
                pusha
                push    100h            ; dwPriorityClass
                push    [hProcess]   ; hProcess
                call    [SetPriorityClass]
                cmp     eax, 1
                jnz     short .error
                push    0Fh             ; nPriority
                push    [hThread]    ; hThread
                call    [SetThreadPriority]
                cmp     eax, 1
                jnz     short .error
                popa
                retn
.error:
                ;jmp    fatalunexpected

; ---------------------------------------------------------------------------

fatalunexpected:
		xor	ebx, ebx
                div     ebx
hang:
                jmp     short hang

end if

; =============== S U B R O U T I N E =======================================


read_wav_file_header:
		; If input is a PCM file, sample rate, bits per sample
		; and number of channels will be set according to
                ; /F:,/B:,/C: switches.
		; If input is a WAV file, parameters will be set
		; according to the file header.

		cmp	byte [wav_input], 1
		jb	short .set_pcm_parms

		mov	esi, [stream_start]
		cmp	dword [esi],'RIFF'
		jne	.not_valid_wav_file

		cmp	dword [esi+8],'WAVE'
		jne	.not_valid_wav_file

		cmp	word  [esi+20], 1
		jne	.not_proper_wav_file

		mov	eax, [esi+24]	  	  	
		call	is_valid_frequency
		jc	.not_proper_wav_file
		mov	[wav_input_sample_rate], eax

		movzx	eax, word [esi+22]
		call	is_valid_channels
		jc	.not_proper_wav_file
		;mov	[wav_input_num_channels], eax
		mov	ecx, eax

		mov	ax, word [esi+34]
		mov	[wav_input_bits_per_sample],eax				
		call	is_valid_bits
		jc	.not_proper_wav_file
		;mov	[wav_input_bits_per_sample],eax
		mov	ebx, eax
		;shr	eax, 3
		;mov	[wav_input_bytes_per_sample],eax

		;mov	eax, 44
		mov	al, 44
		add	dword [stream_pos], eax ; 44
					; wav header size
		sub	dword [bytes_left], eax ; 44

		mov	eax, [wav_input_sample_rate] 
		jmp	short .set_block_size

.set_pcm_parms:
		mov	eax, [pcm_channels]
		mov	ecx, eax
		mov	ebx, [pcm_bits]
		; ebx = bytes per sample
		mul	ebx ; * channels
		shr	eax, 3
		dec	eax ; 16 bit stereo = 3
			    ; 16 bit mono = 1
			    ; 8 bit stereo = 1
			    ; 8 bit mono = 0
		test	byte [input_file_size], al
		jnz	short .not_proper_pcm_file

		mov	eax, [pcm_frequency]
		mov	[wav_input_sample_rate], eax
.set_block_size:
		mov	[wav_input_num_channels], ecx
		mov	[wav_input_bits_per_sample], ebx
		shr	ebx, 3
		mov	[wav_input_bytes_per_sample], ebx

		mov	edx, [bytes_left]
                mov	[wav_total_input_size], edx

		; 24/10/2024
		;mov	eax, 32768
		mov	[block_size], 32768
			; example: (8192*2*2) = 32768 bytes

		;add	dword [stream_pos], 0
		
		retn

.not_valid_wav_file:
		mov	edx, txt_invalid_wavf
.write_err_msg:
		call	wrstr_edx
 		stc
		retn

.not_proper_wav_file:
		mov	edx, txt_improper_wavf
		jmp	short .write_err_msg

.not_proper_pcm_file:
		mov	edx, txt_improper_pcmf
		jmp	short .write_err_msg

; =============== S U B R O U T I N E =======================================


prepare_output_parms:
		mov	eax, [wav_input_sample_rate]
		mov	[wav_output_sample_rate], eax
		mov	eax, [wav_input_num_channels]
		mov	[wav_output_num_channels], eax
		mov	eax, [wav_input_bytes_per_sample]
		mov	[wav_output_bytes_per_sample], eax
		mov	eax, [wav_input_bits_per_sample]
		mov	[wav_output_bits_per_sample], eax

		mov	al, 1
		cmp	byte [option_channels], al ; 1
		ja	short .1
		jb	short .2
		cmp	byte [wav_input_num_channels], al ; 1
		je	short .1
		mov	byte [wav_output_num_channels], al ; 1
		mov	byte [convert], al ; 1 ; mono flag
		jmp	short .2
.1:
		inc	al  ; 2
		cmp	byte [wav_input_num_channels], al ; 2
		je	short .2
		mov	byte [wav_output_num_channels], al ; 2
		mov	byte [convert], al ; 2
.2:
		mov	al, 8
		cmp	byte [option_bits], al ; 8
		ja	short .3
		jb	short .4
		cmp	byte [wav_input_bits_per_sample], al ; 8
		je	short .3
		mov	byte [wav_output_bits_per_sample], al ; 8
		mov	byte [wav_output_bytes_per_sample], 1
		or	byte [convert], al ; 8
		jmp	short .4
.3:
		;mov	al, 16
		shl	eax, 1
		cmp	byte [wav_input_bits_per_sample], al ; 16
		je	short .4
		mov	byte [wav_output_bits_per_sample], al ; 16
		mov	byte [wav_output_bytes_per_sample], 2
		or	byte [convert], 16 ; 16
.4:
		mov	eax, [wav_input_sample_rate]
		cmp	byte [option_rate_shift], 0
		jna	short .6
		cmp	eax, 16000
		jb	short .6
		shr	eax, 1
		or	byte [convert], 32
		cmp	byte [option_rate_shift], 1
		jna	short .5
		cmp	eax, 16000
		jb	short .5
		shr	eax, 1
		or	byte [convert], 64
.5:
		mov	[wav_output_sample_rate], eax
.6:
		cmp	byte [option_fast], 0
		jna	short .7
		cmp	eax, 24000
		ja	short .7
		or	byte [convert], 4
.7:
		; 25/10/2024
		mov	eax, [block_size]
		test	byte [convert], not 4
		jz	short .done ; [block_size] = 32768
		; PCM out block size must not be > 32768
		;	(sample_buffer limit)
		;mov	[block_size], 32768
		test	byte [convert], 2  ; mono to stereo ?
		jz	short .8
		shr	eax, 1
		; [block_size] is 16384 here
.8:	
		test	byte [convert], 16  ; 8 to 16 bit ?
		jz	short .done
		shr	eax, 1
		; [block_size] is 8192 or 16384 here
.done:
		mov	[block_size], eax
		mov	[pcm_samples_output_size], eax
		
		retn


; =============== S U B R O U T I N E =======================================

input_file_info:
                mov     edx, txt_file_size ; "file size: "
                call    wrstr_edx
                mov     eax, [input_file_size]
                call    wr_decimal_eax_with_thousands_seperator
                mov     edx, txt_bytes ; " bytes"
                call    wrstr_edx
		mov     edx, txt_input ; "input: "
                call    wrstr_edx
                mov     eax, [wav_input_sample_rate]
                call    wr_decimal_eax
                mov     edx, txt_hz ; " hz, "
                call    wrstr_edx
                mov     eax, [wav_input_num_channels]
                call    wr_decimal_eax
                mov     edx, txt_channels ; " channels, "
                call    wrstr_edx
 		mov     eax, [wav_input_bytes_per_sample]
                shl     eax, 3
                call    wr_decimal_eax
                mov     edx, txt_bit ; " bit"
                call    wrstr_edx
                call    wrcrlf
                mov     edx, txt_output ; "output: "
                call    wrstr_edx
                mov     eax, [wav_output_sample_rate]
                call    wr_decimal_eax
                mov     edx, txt_hz ; " hz, "
                call    wrstr_edx
                mov     eax, [wav_output_num_channels]
                call    wr_decimal_eax
                mov     edx, txt_channels ; " channels, "
                call    wrstr_edx
                mov     eax, [wav_output_bytes_per_sample]
                shl     eax, 3
                call    wr_decimal_eax
                mov     edx, txt_bit ; " bit"
                call    wrstr_edx
                ;call   wrcrlf
 		;retn
		jmp	short wrcrlf


; =============== S U B R O U T I N E =======================================


wrchr:
                pusha
                mov     [wrchr_buf], al
                push    0            ; lpOverlapped
                push    diskresult   ; lpNumberOfBytesWritten
                push    1            ; nNumberOfBytesToWrite
                push    wrchr_buf    ; lpBuffer
                push    [std_out]    ; hFile
                call    [WriteFile]
                popa
                retn


; =============== S U B R O U T I N E =======================================


wrstr_edx:
                push    eax
.lop:
                mov     al, [edx]
                inc     edx
                cmp     al, 0
                jz      short .done
                call    wrchr
                jmp     short .lop
.done:
                pop     eax
                retn

; =============== S U B R O U T I N E =======================================


wrcrlf:
                push    eax
                mov     al, 0Dh
                call    wrchr
                mov     al, 0Ah
                call    wrchr
                pop     eax
                retn

; =============== S U B R O U T I N E =======================================


wrspc:
                push    eax
                mov     al, 20h
                call    wrchr
                pop     eax
                retn

; =============== S U B R O U T I N E =======================================


wrcomma:
                push    eax
                mov     al, ','
                call    wrchr
                pop     eax
                retn

; =============== S U B R O U T I N E =======================================


wr_decimal_eax_with_thousands_seperator:
                push    ecx
                mov     cx, 2
                jmp     short wr_decimal_eax_inj

; =============== S U B R O U T I N E =======================================


wr_decimal_eax:
                push    ecx
                xor     ecx, ecx

wr_decimal_eax_inj:
                push    eax
                push    ebx
                push    edx
                mov     ebx, 1000000000 ; nine zeroes (32bit max 4.294.967.296)

.dezlop:
                dec     cl
                jnz     short .no_thousands
                mov     cl, 3
                cmp     ch, 0
                jz      short .no_thousands
                call    wrcomma

.no_thousands:
                xor     edx, edx
                div     ebx
                cmp     ebx, 1
                jz      short .force_last_zero
                or      ch, al
                jz      short .skip_lead_zero

.force_last_zero:
                add     al, 30h
                call    wrchr

.skip_lead_zero:
                push    edx
                mov     eax, ebx
                mov     ebx, 10
                xor     edx, edx
                div     ebx
                cmp     eax, 0
                mov     ebx, eax
                pop     eax
                jnz     short .dezlop
                pop     edx
                pop     ebx
                pop     eax
                pop     ecx
                retn

; =============== S U B R O U T I N E =======================================


wrdigital:
                push    eax
                and     al, 0Fh
                cmp     al, 9
                jbe     short .this
                add     al, 7

.this:
                add     al, 30h
                call    wrchr
                pop     eax
                retn


; =============== S U B R O U T I N E =======================================


get_commandline:
                call    [GetCommandLineA]
                mov     esi, eax
                mov     edi, cmdline_buf
                mov     ecx, 1024       ; cmdline_max

.get_cmdline_lop:
                lodsb
                cmp     al, 0
                stosb
                loopne  .get_cmdline_lop
                mov     byte [edi-1], 0
                mov     esi, cmdline_buf
                mov     edi, cmdline_buf
                call    _@@get_item     ; get/skip name of the executable itself

.get_items_lop:
                call    _@@get_item
                mov     al, [ebx]
                cmp     al, 0
                jz      .done
                cmp     al, '/'
                jz      .switch
                cmp     al, '-'
                jz      .switch
                mov     eax, [edi-5]
                or      eax, 20202000h
                cmp     eax, '.wav'     ; FASM & NASM syntax
                jnz     short .not_wav_name
		cmp	dword [wav_src_fname], 0
		ja	short .dest_wav_file
		mov     [wav_src_fname], ebx
		mov	byte [wav_input], 1
                jmp     short .get_items_lop
.dest_wav_file:
		cmp	dword [wav_dst_fname], 0
		ja	.help
                mov     [wav_dst_fname], ebx
		mov	byte [wav_output], 1
                jmp     short .get_items_lop

.not_wav_name:
                mov     eax, [edi-5]
                or      eax, 20202000h
                cmp     eax, '.pcm'     ; FASM & NASM syntax
                jnz     .not_pcm_name

		cmp	dword [wav_src_fname], 0
		ja	short .dest_pcm_file
		mov     [wav_src_fname], ebx
		;mov	byte [wav_input], 0
                jmp    .get_items_lop
.dest_pcm_file:
		cmp	dword [wav_dst_fname], 0 
		ja	.help	
                mov     [wav_dst_fname], ebx
		;mov	byte [wav_output], 0
                jmp     .get_items_lop

.switch:
                cmp     dword [ebx+1], 'mono'
                jnz     short .not_switch_mono
		cmp	byte [option_channels], 0
		ja	.help
                mov     byte [option_channels], 1
                jmp     .get_items_lop

.not_switch_mono:
                cmp     dword [ebx+1], 'ster'
                jnz     short .not_switch_stereo
                cmp     word [ebx+5], 'eo'
                jnz     short .not_switch_stereo
		cmp	byte [option_channels], 0
		ja	.help
		mov	byte [option_channels], 2
                jmp     .get_items_lop
		
.not_switch_stereo:
                cmp     dword [ebx+1], 'fast' ; FASM & NASM syntax
                jnz     short .not_fast_option
                mov     byte [option_fast], 1
                jmp     .get_items_lop

.not_fast_option:
                cmp     dword [ebx+1], '8bit'
                jnz     short .not_switch_8bit
		cmp	byte [option_bits], 0
		ja	.help
                mov     byte [option_bits], 8
                jmp     .get_items_lop

.not_switch_8bit:
                cmp     dword [ebx+1], '16bi'
                jnz     short .not_switch_16bit
		cmp	byte  [ebx+5],'t'
		jnz     short .not_switch_16bit
		cmp	byte [option_bits], 0
		ja	.help
		mov	byte [option_bits], 16
                jmp     .get_items_lop

.not_switch_16bit:
                cmp     dword [ebx+1], 'half'
                jnz     short .not_switch_half
		cmp	byte [option_rate_shift], 2
		je	.help
                mov     [option_rate_shift], 1
                jmp     .get_items_lop

.not_switch_half:
                cmp     dword [ebx+1], 'quar'
                jnz     short .not_switch_quarter
                cmp     word [ebx+5], 'te'
                jnz     short .not_switch_quarter
                cmp     byte [ebx+7], 'r'
                jnz     short .not_switch_quarter
		cmp	byte [option_rate_shift], 1
		je	.help
                mov     [option_rate_shift], 2
                jmp     .get_items_lop

.not_switch_quarter:
                cmp     dword [ebx+1], 'test'
                jnz     short .not_switch_test
                mov     [option_test], 1
                jmp     .get_items_lop

.not_switch_test:
		; 25/10/2024
		mov	ax, [ebx+1]
		and 	al, 0DFh
		cmp	ax, 'F:'
		;cmp	word [ebx+1], 'F:'
		jne	short .not_switch_pcm_f
		mov	eax, [ebx+3]
		mov	edx, [ebx+7]
		call	convert_to_number
		call	is_valid_frequency
		jc	short .help
		mov	[pcm_frequency], eax
                jmp     .get_items_lop
.not_switch_pcm_f:
		mov	ax, [ebx+1]
		and 	al, 0DFh
		cmp	ax, 'B:'
		;cmp	word [ebx+1], 'B:'
		jne	short .not_switch_pcm_b
		mov	eax, [ebx+3]
		xor	edx, edx
		call	convert_to_number
		call	is_valid_bits
		jc	short .help
		mov	[pcm_bits], eax
                jmp     .get_items_lop

.not_switch_pcm_b:
		mov	ax, [ebx+1]
		and 	al, 0DFh
		cmp	ax, 'C:'
		;cmp	word [ebx+1], 'C:'
		;jne	short .not_switch_pcm_c
		jne	short .help
		mov	eax, [ebx+3]
		xor	edx, edx
		call	convert_to_number
		call	is_valid_channels
		jc	short .help
		mov	[pcm_channels], eax
		jmp     .get_items_lop

;.not_switch_pcm_c:
;               jmp     short .help

.not_pcm_name:
.help:
                ;;; Erdogan Tan - 22/10/2024
                mov     edx, txt_about
                call    wrstr_edx
                ;;;
                mov     edx, txt_help ; "usage: wavplay input.wav ["...
                call    wrstr_edx
                stc
                retn

.done:
                cmp     [wav_src_fname], 0
                jz      short .help
                ;;; Erdogan Tan - 17/10/2024
                mov     edx, txt_ctrlc
                call    wrstr_edx
                ;;;
                mov     edx, txt_file ; "file: "
                call    wrstr_edx
                mov     edx, [wav_src_fname]
                call    wrstr_edx
                call    wrcrlf
                clc
                retn

; ---------------------------------------------------------------------------

		; 22/10/2024
convert_to_number:
		; edx:eax = decimal/numeric string
		push	edx ; *
		mov	ecx, eax
		xor	eax, eax
		mov	ebx, 10
.ctn_next:
		; cl = digit 1 
		call	mul_eax_ebx_add_cl
		jc	short .pop_ok
		shr	ecx, 8
		; cl = digit 2
		call	mul_eax_ebx_add_cl
		jc	short .pop_ok
		shr	ecx, 8
		; cl = digit 3
		and	cl, cl
		call	mul_eax_ebx_add_cl
		jc	short .pop_ok
		shr	ecx, 8
		; cl = digit 4
		call	mul_eax_ebx_add_cl
		jc	short .pop_ok
		pop	edx ; *
		or	edx, edx
		jz	short .ok
		mov	ecx, edx
		push	0   ; *	
		jmp	short .ctn_next		
.pop_ok:
		pop	edx ; *
.ok:
		retn

mul_eax_ebx_add_cl:
		; eax = previous total
		; cl = numeric character (digit)
		; ebx = 10
		and	cl, cl
		jz	short .mul_stc
		cmp	cl, '0'
		;jb	short .mul_stc
		jb	short .mul_ret
		cmp	cl, '9'
		ja	short .mul_stc
		sub	cl, '0'
		mul	ebx
		; edx = 0
		mov	dl, cl
		add	eax, edx
		retn
.mul_stc:
		stc
.mul_ret:
		retn

; ---------------------------------------------------------------------------

		; 22/10/2024
is_valid_frequency:
		cmp	eax, 44100
		je	short .ok
		cmp	eax, 48000
		je	short .ok
		ja	short .not_ok
		cmp	eax, 8000
		jna	short .ok
		cmp	eax, 24000
		je	short .ok
		cmp	eax, 22050
		je	short .ok
		cmp	eax, 16000
		je	short .ok
		cmp	eax, 11025
		je	short .ok
		cmp	eax, 12000
		jna	short .ok
		cmp	eax, 32000
		je	short .ok
.not_ok:
		stc
.ok:
		retn

; ---------------------------------------------------------------------------

		; 22/10/2024
is_valid_bits:
		cmp	eax, 16
		je	short .ok
		cmp	eax, 8
		je	short .ok
		stc
.ok:
		retn

; ---------------------------------------------------------------------------

		; 22/10/2024
is_valid_channels:
		cmp	eax, 1
		je	short .ok
		cmp	eax, 2
		je	short .ok
		stc
.ok:
		retn	

; =============== S U B R O U T I N E =======================================


_@@get_item:
                lodsb
                dec     al
                cmp     al, 1Fh         ; 20-1
                jbe     short _@@get_item ; _@@skip_spc_lop
                dec     esi
                mov     ebx, edi
                mov     ah, 0           ; flag initially not quoted

.char_lop:
                lodsb
                cmp     al, '"'
                jnz     short .no_quote
                xor     ah, 1
                jmp     short .char_lop

.no_quote:
                stosb
                cmp     al, 0
                jz      short .src_end
                cmp     al, 20h
                ja      short .char_lop
                cmp     ah, 0           ; ignore spaces if inside "quoted area"
                jnz     short .char_lop
                mov     byte [edi-1], 0 ; eol (replace space by 00h)
                retn

.src_end:
                dec     esi
                retn


; =============== S U B R O U T I N E =======================================


open_and_mmap_input_file:

		test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported1
                rdtsc
                sub     [rdtsc_read_input], eax
                sbb     [rdtsc_read_input+4], edx
.no_rdtsc_supported1:

                push    0               ; hTemplateFile
                push    0               ; dwFlagsAndAttributes
                push    3               ; dwCreationDisposition
                push    0               ; lpSecurityAttributes
                push    1               ; dwShareMode
                push    80000000h       ; dwDesiredAccess
                push    [wav_src_fname] ; lpFileName
                call    [CreateFileA]
                mov     [hFile], eax
                cmp     eax, 0FFFFFFFFh ; INVALID_HANDLE_VALUE
                jz      short .not_found
                push    0               ; lpFileSizeHigh
                push    [hFile]      ; hFile
                call    [GetFileSize]
                mov     [input_file_size], eax
                mov     [bytes_left], eax
		;;;
		; 25/10/2024
		cmp	byte [wav_input], 1
		je	short .wav_size_chk
.pcm_size_chk:
		cmp	eax, 16
		jnb	short .cont
		jmp	short .invalid	
.wav_size_chk:
		cmp	eax, 16+44 ; minimum 16 bytes data
		jb	short .invalid
.cont:
		;;;
                push    0               ; lpName
                push    0               ; dwMaximumSizeLow
                push    0               ; dwMaximumSizeHigh
                push    2               ; flProtect
                push    0               ; lpFileMappingAttributes
                push    [hFile]		; hFile
                call    [CreateFileMappingA]
                mov     [hMap], eax
                push    0               ; dwNumberOfBytesToMap
                push    0               ; dwFileOffsetLow
                push    0               ; dwFileOffsetHigh
                push    4               ; dwDesiredAccess
                push    [hMap]       	; hFileMappingObject
                call    [MapViewOfFile]
                mov     [stream_start], eax
                mov     [stream_pos], eax
                mov     esi, [stream_start]
                mov     ecx, [bytes_left]
.lll:
                lodsb
                loop    .lll
                clc
                ;retn
		jmp	short .done

.not_found:
                mov     edx, txt_not_found ; "cannot open source file\r\n"
.write_err_msg:
                call    wrstr_edx
                stc
                ;retn
		;jmp    short .done
.done:
		pushf
		test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported2
                rdtsc
                add     [rdtsc_read_input], eax
                adc     [rdtsc_read_input+4], edx
.no_rdtsc_supported2:
		popf
		retn

		; 25/10/2024
.invalid:	
		; invalid wav (or pcm) file
		; CloseHandle(hFile);
		push	[hFile]
		call	[CloseHandle]
		mov	edx, txt_invalid_wavf
		jmp	short .write_err_msg


; =============== S U B R O U T I N E =======================================


unmap_and_close_input:
		test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported1
                rdtsc
                sub     [rdtsc_read_input], eax
                sbb     [rdtsc_read_input+4], edx
.no_rdtsc_supported1:

		; UnmapViewOfFile(lpMapAddress);
		push	[stream_start]
                call    [UnmapViewOfFile]

		; CloseHandle(hMap); 
		push	[hMap]
		call	[CloseHandle]

		; CloseHandle(hFile);
		push	[hFile]
		call	[CloseHandle]

		test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported2
                rdtsc
                add     [rdtsc_read_input], eax
                adc     [rdtsc_read_input+4], edx
.no_rdtsc_supported2:

		retn

; =============== S U B R O U T I N E =======================================


read_pcm_data_block:
                xor	eax, eax
                cmp     [bytes_left], eax ; 0
                ;jna    short .done
		jng	short .done

		; 25/10/2024
		;;;
		test	byte [convert], not 4
				; conversion flags except /FAST flag
		jnz	short .read_data_and_convert
		;;;

		test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported1
                rdtsc
                sub     [rdtsc_read_input], eax
                sbb     [rdtsc_read_input+4], edx
.no_rdtsc_supported1:

	        mov     esi, [stream_pos]
                mov     ecx, [bytes_left]
                mov     eax, [block_size]
		cmp     ecx, eax
                jna     short .skip_decr
	        mov     ecx, eax 
.skip_decr:
		push	ecx

                add     [stream_pos], ecx
                sub     [bytes_left], ecx

		rep movsb
		
               	test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported2
                rdtsc
                add     [rdtsc_read_input], eax
                adc     [rdtsc_read_input+4], edx
.no_rdtsc_supported2:
		pop	eax

.done:
		retn

		; 25/10/2024
		;;;
.read_data_and_convert:
		test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported3
                rdtsc
                sub     [rdtsc_interpolat], eax
                sbb     [rdtsc_interpolat+4], edx
.no_rdtsc_supported3:
	        mov     esi, [stream_pos]
                mov     ecx, [bytes_left]
                mov     eax, [block_size]
		cmp     eax, ecx
                jna     short .skip_decrs
	        mov     eax, ecx 
.skip_decrs:
                add    [stream_pos], eax
                sub    [bytes_left], eax
		;***
		;pusha
		;call   convert function
                call	dword [convert_pcm_data]
		;popa
		;***
		;mov	eax, [block_size]
		;or	eax, eax
		;jz	short .zero
		;add    [stream_pos], eax
                ;sub    [bytes_left], eax
		mov	eax, [pcm_samples_output_size]
		and	eax, eax
		jnz	short .ok
.zero:
		mov	[bytes_left], eax ; 0
		and	byte [convert], 4 ; clear flags except /FAST
.ok:
		test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported4
                push	eax
		rdtsc
                add     [rdtsc_interpolat], eax
                adc     [rdtsc_interpolat+4], edx
		pop	eax
.no_rdtsc_supported4:
		retn
		;;;
	          		

; =============== S U B R O U T I N E =======================================


cast_to_wav_file:
		test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported1
                rdtsc
                sub     [rdtsc_write_output], eax
                sbb     [rdtsc_write_output+4], edx
.no_rdtsc_supported1:

                call    create_wav_file

cast_to_output_file:
		test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported2
                rdtsc
                add     [rdtsc_write_output], eax
                adc     [rdtsc_write_output+4], edx
.no_rdtsc_supported2:

		; 25/10/2024
		;;;
		test	byte [convert], not 4 ; except /FAST flag
		jz	short .lop
		; ***
		call	set_pcm_out_converter_function
		; ***
		test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported3
                rdtsc
                add     [rdtsc_interpolat], eax
                adc     [rdtsc_interpolat+4], edx
.no_rdtsc_supported3:
		;;;
.lop:
                ;mov    esi, [stream_pos]
                ;mov    ecx, [bytes_left]
                mov     edi, sample_buffer
                call    read_pcm_data_block

		push	eax ; * ; = [pcm_samples_output_size]

		test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported4
                rdtsc
                sub     [rdtsc_write_output], eax
                sbb     [rdtsc_write_output+4], edx
.no_rdtsc_supported4:
		pop	eax ; *
		
		or	eax, eax
		jz	short .exit

                push    0               ; lpOverlapped
                push    diskresult	; lpNumberOfBytesWritten
                ;push   [pcm_samples_output_size] ; *
		push	eax ; *		; nNumberOfBytesToWrite
                push    sample_buffer	; lpBuffer
                push    [output_file_handle] ; hFile
                call    [WriteFile]
                mov     eax, [pcm_samples_output_size]
                add     dword [wav_outf_header+4], eax
                add     dword [wav_outf_header+40], eax

		test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported5
                rdtsc
                add     [rdtsc_write_output], eax
                adc     [rdtsc_write_output+4], edx
.no_rdtsc_supported5:

                jmp     short .lop

.exit:
                call    close_output_file

		test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported6
                rdtsc
                add     [rdtsc_write_output], eax
                adc     [rdtsc_write_output+4], edx
.no_rdtsc_supported6:

                retn

; =============== S U B R O U T I N E =======================================

cast_to_pcm_file:
		test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported1
                rdtsc
                sub     [rdtsc_write_output], eax
                sbb     [rdtsc_write_output+4], edx
.no_rdtsc_supported1:

                call    create_pcm_file
		jmp	cast_to_output_file

; =============== S U B R O U T I N E =======================================


create_wav_file:
                mov     eax, [wav_output_sample_rate]
                mov     ecx, [wav_output_num_channels]
                mov     edx, [wav_output_bytes_per_sample]
                mov     word [wav_outf_header+22], cx
                mov     dword [wav_outf_header+24], eax
                imul    ecx, edx
                imul    eax, ecx
                shl     edx, 3
                mov     dword [wav_outf_header+28], eax
                mov     word [wav_outf_header+32], cx
                mov     word [wav_outf_header+34], dx
                ;push   0               ; hTemplateFile
                ;push   80h             ; dwFlagsAndAttributes
                ;push   2               ; dwCreationDisposition
                ;push   0               ; lpSecurityAttributes
                ;push   0               ; dwShareMode
                ;push   0C0000000h      ; dwDesiredAccess
                ;push   [wav_dst_fname] ; lpFileName
                ;call   [CreateFileA]
                ;mov    [output_file_handle], eax
                call	create_output_file
		
		;call   write_wav_header
                ;retn

; =============== S U B R O U T I N E =======================================


write_wav_header:
                push    0               ; lpOverlapped
                push    diskresult      ; lpNumberOfBytesWritten
                push    44 ; 2Ch        ; nNumberOfBytesToWrite
                push    wav_outf_header  ; lpBuffer
                push    [output_file_handle] ; hFile
                call    [WriteFile]
                retn

; =============== S U B R O U T I N E =======================================

create_pcm_file:
create_output_file:
		push    0               ; hTemplateFile
                push    80h             ; dwFlagsAndAttributes
                push    2               ; dwCreationDisposition
                push    0               ; lpSecurityAttributes
                push    0               ; dwShareMode
                push    0C0000000h      ; dwDesiredAccess
                push    [wav_dst_fname] ; lpFileName
                call    [CreateFileA]
                mov     [output_file_handle], eax
		retn


; =============== S U B R O U T I N E =======================================


close_output_file:
		cmp	byte [wav_output], 0
		jna	short .close

                push    0               ; dwMoveMethod
                push    0               ; lpDistanceToMoveHigh
                push    0               ; lDistanceToMove
                push    [output_file_handle] ; hFile
                call    [SetFilePointer]
                call    write_wav_header
.close:
                push    [output_file_handle] ; hObject
                call    [CloseHandle]
                retn


; =============== S U B R O U T I N E =======================================


prepare_wave_headers:
                mov     ebx, wave_block_headers
                mov     edi, ebx
		mov	ecx, 64	; BUFFER_COUNT*32/4
                xor     eax, eax
                rep stosd
                mov     edi, sample_buffer

.prepare_lop:
                mov     [ebx], edi
		;mov	eax, [block_size]
                ; 25/10/2024
		mov	eax, [pcm_samples_output_size] ; pcm out block size
		mov     [ebx+4], eax
                push    32              ; sizeof_WAVEHDR
                push    ebx             ; wavehdr
                push    esi             ; wave_out_handle
                call    [waveOutPrepareHeader]
                cmp     eax, 0          ; warn_error_eax macro txt
                jz      short .no_error
                pusha
                mov     edx, txt_waveout_error1 ; "\r\n  *** ERROR number "
                call    wrstr_edx
                call    wr_decimal_eax
                mov     edx, txt_waveout_error2 ; " in function "
                call    wrstr_edx
                mov     edx, warn_errmsg_1 ; "waveOutPrepareHeader"
                call    wrstr_edx
                mov     edx, txt_waveout_error3 ; "\r\n  ... bugdefect.@@@+critical"...
                call    wrstr_edx
                mov     [have_wave_error], 1
                popa

.no_error:
		;add	edi, [block_size] ; 24/10/2024
		add	edi, [pcm_samples_output_size] ; pcm out block size
		add     ebx, 32
                cmp     ebx, end_of_blocks ; waveout_headers+BUFFER_COUNT*32
                jb      short .prepare_lop
                retn


; =============== S U B R O U T I N E =======================================


unprepare_wave_headers:
                mov     ebx, wave_block_headers

.unprepare_lop:
                push    32              ; cbwh
                push    ebx             ; pwh
                push    [waveout_handle] ; hwo
                call    [waveOutUnprepareHeader]
                cmp     eax, 0
                jz      short .no_error
                pusha
                mov     edx, txt_waveout_error1 ; "\r\n  *** ERROR number "
                call    wrstr_edx
                call    wr_decimal_eax
                mov     edx, txt_waveout_error2 ; " in function "
                call    wrstr_edx
                mov     edx, warn_errmsg_2 ; "waveOutUnprepareHeader"
                call    wrstr_edx
                mov     edx, txt_waveout_error3 ; "\r\n  ... bugdefect.@@@+critical"...
                call    wrstr_edx
                mov     [have_wave_error], 1
                popa

.no_error:
                add     ebx, 32
                cmp     ebx, end_of_blocks
                jb      short .unprepare_lop
                retn


; =============== S U B R O U T I N E =======================================


try_enqueue_block:
                cmp     [bytes_left], 0
                ;jle    .enqueue_done
		ja	short .do
.done:
		retn
.do:
		push	esi
		push	ebx
                ;mov    esi, [stream_pos]
                ;mov    ecx, [bytes_left]
                mov     edi, [ebx]
                call    read_pcm_data_block
                pop	ebx
		pop	esi

                mov     [ebx+4], eax	; block size

		; 25/10/2024
		;and	eax, eax
		;jz	short .done

                cmp     [have_wave_error], 0 ; warn_error_destroyer_wavehdr_ebx macro
                jz      short .no_destroyer
                pusha
                mov     edi, [ebx]
                test    word [edi], 103h
                jnz     short .scratch_skip
                mov     ecx, [ebx+4]    ; bufsize
                shr     ecx, 3          ; div 8 (4 words)
                mov     ax, 5234h

.scratch_lop:
                ror     ax, 1
                add     [edi], ax
                add     [edi+2], ax
                add     [edi+4], ax
                add     [edi+6], ax
                add     edi, 8
                loop    .scratch_lop

.scratch_skip:
                and     eax, 7
                add     eax, 4
                mov     ecx, eax

.random_chr_lop:
                or      al, 20h
                call    wrchr
                add     al, 53h
                loop    .random_chr_lop
                mov     edx, txt_ERROR ; "ERROR"
                call    wrstr_edx
                popa

.no_destroyer:
                push    32              ; cbwh ; sizeof_WAVEHDR
                push    ebx             ; pwh ; wavehdr
                push    esi             ; hwo ; waveout_handle
                call    [waveOutWrite]
                cmp     eax, 0          ; warn_error_eax <'waveOutWrite'>
                jz      short .no_error
                pusha
                mov     edx, txt_waveout_error1 ; "\r\n   *** ERROR number "
                call    wrstr_edx
                call    wr_decimal_eax
                mov     edx, txt_waveout_error2 ; " in function "
                call    wrstr_edx
                mov     edx, warn_errmsg_3 ; "waveOutWrite"
                call    wrstr_edx
                mov     edx, txt_waveout_error3 ; "\r\n    ... bugdefect.@@@+critical\\&&&"...
                call    wrstr_edx
                mov     [have_wave_error], 1
                popa

.no_error:
                inc     [num_enqueued_blocks]

                retn

;.enqueue_done:
                ;mov     [bytes_left], 0
                ;retn


; =============== S U B R O U T I N E =======================================


try_enqueue_all_blocks:
		test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported1
                rdtsc
                sub     [rdtsc_write_output], eax
                sbb     [rdtsc_write_output+4], edx
.no_rdtsc_supported1:

                mov     ebx, wave_block_headers

.enqueue_initial_lop:                 
                call    try_enqueue_block
                add     ebx, 32
 		cmp     ebx, end_of_blocks
			; wave_block_headers+BUFFER_COUNT*32
                jb      short .enqueue_initial_lop

		test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported2
                rdtsc
                add     [rdtsc_write_output], eax
                adc     [rdtsc_write_output+4], edx
.no_rdtsc_supported2:

                retn


; =============== S U B R O U T I N E =======================================

; Attributes: bp-based frame

AudioCallback:

@@waveout_handle equ 8
@@uMsg          equ 12
@@param1        equ 20

                push    ebp
                mov     ebp, esp
                cmp     dword [ebp+@@uMsg], 3BDh ; MM_WOM_DONE
                jnz     short .exit
                pusha
                mov     esi, [ebp+@@waveout_handle]
                mov     ebx, [ebp+@@param1]
                call    try_enqueue_block
                popa
                dec     [num_enqueued_blocks]

.exit:
                leave
                retn    20              ; 5*4 ; remove five dwords on stack


; =============== S U B R O U T I N E =======================================


cast_to_speaker:
                mov     eax, [wav_output_sample_rate]
		test	byte [convert], 4 ; [option_fast], "/fast" switch
		jz	short .do
		shl	eax, 1 ; frequency = 2*frequency
.do:
                mov     ecx, [wav_output_num_channels]
                mov     edx, [wav_output_bytes_per_sample]
                mov     [wfx.nChannels], cx ; [wfx+2]
                mov     [wfx.nSamplesPerSec], eax ; [wfx+4]
                imul    ecx, edx
                imul    eax, ecx
                shl     edx, 3
                mov     [wfx.nAvgBytesPerSec], eax ; [wfx+8]
                mov     [wfx.nBlockAlign], cx ; [wfx+12]
                mov     [wfx.wBitsPerSample], dx ; [wfx+14]
                push    30000h          ; fdwOpen ; CALLBACK_FUNCTION
                push    0               ; dwInstance ; NULL ; user_data
                push    AudioCallback   ; dwCallback
                push    wfx             ; wave_format
                push    0FFFFFFFFh      ; uDeviceID ; WAVE_MAPPER
                push    waveout_handle  ; phwo
                call    [waveOutOpen]
                cmp     eax, 0          ; MMSYSERR_NOERROR
                jz      short .wave_open_okay
                mov     edx, txt_waveopen_failed ; "  ERROR: cannot open wave output!\r\n"
                ;call   wrstr_edx
                ;jmp    .done_quit
		;retn
		jmp	wrstr_edx

.wave_open_okay:
		; 25/10/2024
		;;;
		test	byte [convert], not 4 ; except /FAST flag
		jz	short .no_convert
		; ***
		call	set_pcm_out_converter_function
		; ***
		test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported
                rdtsc
                add     [rdtsc_interpolat], eax
                adc     [rdtsc_interpolat+4], edx
.no_rdtsc_supported:
.no_convert:
		;;;
                mov     esi, [waveout_handle]
                call    prepare_wave_headers
                push    [waveout_handle] ; hwo
                call    [waveOutPause]   ; warn_error_eax <'waveOutPause'>
                cmp     eax, 0
                jz      short .no_error
                pusha
                mov     edx, txt_waveout_error1 ; "\r\n  *** ERROR number "
                call    wrstr_edx
                call    wr_decimal_eax
                mov     edx, txt_waveout_error2 ; " in function "
                call    wrstr_edx
                mov     edx, warn_errmsg_5 ; "waveOutPause"
                call    wrstr_edx
                mov     edx, txt_waveout_error3 ; "\r\n  ... bugdefect.@@@+critical"...
                call    wrstr_edx
                mov     [have_wave_error], 1
                popa

.no_error:
		; 25/10/2024
		test	byte [convert], 4 ; [option_fast], "/fast" switch
		jz	short .not_fast
		mov	edx, txt_fast	; "fast play"
		call    wrstr_edx
.not_fast:
                call    try_enqueue_all_blocks
                push    [waveout_handle] ; hwo
                call    [waveOutRestart]
                cmp     eax, 0          ; warn_error_eax <'waveOutRestart'>
                jz      short .playback_wait_lop
                pusha
                mov     edx, txt_waveout_error1 ; "\r\n  *** ERROR number "
                call    wrstr_edx
                call    wr_decimal_eax
                mov     edx, txt_waveout_error2 ; " in function "
                call    wrstr_edx
                mov     edx, warn_errmsg_6 ; "waveOutRestart"
                call    wrstr_edx
                mov     edx, txt_waveout_error3 ; "\r\n  ... bugdefect.@@@+critical"...
                call    wrstr_edx
                mov     [have_wave_error], 1
                popa

.playback_wait_lop:
		mov     eax, [num_enqueued_blocks]
		or      eax, [bytes_left]
		jz      short .ok
                ;mov    eax, [num_enqueued_blocks]
                ;imul   eax, 10
		mov	eax, 10
		push    eax             ; dwMilliseconds
                call    [Sleep]
		;mov    eax, [num_enqueued_blocks]
		;or     eax, [bytes_left]
		;jnz    short .playback_wait_lop
		jmp	short .playback_wait_lop
.ok:
                push    [waveout_handle] ; hwo
                call    [waveOutReset]
                cmp     eax, 0          ; warn_error_eax <'waveOutReset'>
                jz      short .no_error@
                pusha
                mov     edx, txt_waveout_error1 ; "\r\n  *** ERROR number "
                call    wrstr_edx
                call    wr_decimal_eax
                mov     edx, txt_waveout_error2 ; " in function "
                call    wrstr_edx
                mov     edx, warn_errmsg_7 ; "waveOutReset"
                call    wrstr_edx
                mov     edx, txt_waveout_error3 ; "\r\n  ... bugdefect.@@@+critical"...
                call    wrstr_edx
                mov     [have_wave_error], 1
                popa

.no_error@:
                call    unprepare_wave_headers
                push    [waveout_handle] ; hwo
                call    [waveOutClose]
                cmp     eax, 0          ; warn_error_eax <'waveOutClose'>
                jz      short .no_error@@
                pusha
                mov     edx, txt_waveout_error1 ; "\r\n  *** ERROR number "
                call    wrstr_edx
                call    wr_decimal_eax
                mov     edx, txt_waveout_error2 ; " in function "
                call    wrstr_edx
                mov     edx, warn_errmsg_8 ; "waveOutClose"
                call    wrstr_edx
                mov     edx, txt_waveout_error3 ; "\r\n  ... bugdefect.@@@+critical"...
                call    wrstr_edx
                mov     [have_wave_error], 1
                popa

.no_error@@:
                cmp     [have_wave_error], 0 ; warn_error_crash macro
                jz      short .done_quit ; .no_crash

                xor     ecx, ecx        ; trigger div0 exception
                div     ecx
.done_quit:
                retn


; =============== S U B R O U T I N E =======================================

; CONVERT PCM DATA (AVERAGE POINT & PEAK POINT INTERPOLATIONS)
; CONVERSION (INTERPOLATION) SUB FUNCTIONS: (by Erdogan Tan - 24/10/2024)
; .........................................
; 01 - stereo to stereo, quarter, 16to8 ; example: 48000 kHz to 12000 kHz
; 02 - stereo to stereo, quarter, 8to16
; 03 - stereo to stereo, half, 16to8	; example: 44100 kHz to 22050 kHz
; 04 - stereo to stereo, half, 8to16
; 05 - mono to mono, quarter, 16to8
; 06 - mono to mono, quarter, 8to16
; 07 - mono to mono, half, 16to8
; 08 - mono to mono, half, 8to16
; -------------------------------------
; 09 - stereo to stereo, quarter, 16bit
; 10 - stereo to stereo, quarter, 8bit
; 11 - mono to mono, quarter, 16bit
; 12 - mono to mono, quarter, 8bit
; 13 - stereo to stereo, half, 16bit
; 14 - stereo to stereo, half, 8bit
; 15 - mono to mono, half, 16bit
; 16 - mono to mono, half, 8bit
; -------------------------------------
; 17 - stereo to stereo, same frequency, 16to8
; 18 - stereo to stereo, same frequency, 8to16
; 19 - mono to mono, same frequency, 16to8
; 20 - mono to mono, same frequency, 8to16
; -------------------------------------
; ...
; -------------------------------------
; 21 - stereo to mono, same frequency, 16to8
; 22 - stereo to mono, same frequency, 8to16
; 23 - mono to stereo, same frequency, 16to8
; 24 - mono to stereo, same frequency, 8to16
; 25 - stereo to mono, same frequency, 16bit
; 26 - stereo to mono, same frequency, 8bit
; 27 - mono to stereo, same frequency, 16bit
; 28 - mono to stereo, same frequency, 8bit
; -------------------------------------
; 29 - stereo to mono, quarter, 16to8
; 30 - stereo to mono, quarter, 8to16
; 31 - mono to stereo, quarter, 16to8
; 32 - mono to stereo, quarter, 8to16
; 33 - stereo to mono, quarter, 16bit
; 34 - stereo to mono, quarter, 8bit
; 35 - mono to stereo, quarter, 16bit
; 36 - mono to stereo, quarter, 8bit
; -------------------------------------
; 37 - stereo to mono, half, 16to8
; 38 - stereo to mono, half, 8to16
; 39 - mono to stereo, half, 16to8
; 40 - mono to stereo, half, 8to16
; 41 - stereo to mono, half, 16bit
; 42 - stereo to mono, half, 8bit
; 43 - mono to stereo, half, 16bit
; 44 - mono to stereo, half, 8bit

; ---------------------------------------------------------------------------

		; 25/10/2024
set_pcm_out_converter_function:
		; input:
		;     [convert] flags
		;     [wav_input_num_channels]
		;     [wav_input_bits_per_sample]
		;     [block_size]  ; pcm in block size   		
		; output:
		;     [convert_pcm_data]
		;     [pcm_samples_output_size] ; pcm out block size  		     
		;
		; modified registers: eax, ebx, ecx, edx, esi, edi, ebp

		test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported
                rdtsc
                sub     [rdtsc_interpolat], eax
                sbb     [rdtsc_interpolat+4], edx
.no_rdtsc_supported:
		;;; default function ("nothing to do")
		mov	dword [convert_pcm_data], .default

		mov	eax, [block_size] 
		;mov	[pcm_samples_output_size], eax
		;;;

		test	byte [convert], 2 ; stereo flag
		jnz	.m_to_s_chk_quar

		test	byte [convert], 1 ; mono flag
		jnz	.s_to_m_chk_quar

		cmp	byte [wav_input_num_channels], 1
		jna	.m_chk_quar
.s_chk_quar:
		; stereo input, stereo output
		test	byte [convert], 64 ; quarter flag
		jz	short .s_chk_half

		; stereo input, stereo output, quarter frequency
		test	byte [convert], 16 ; 16bit flag
		jz	short .s_chk_q_8bit
.s_chk_q_16bit:
		; stereo input, stereo output, quarter frequency
		; 8bit input, 16bit output

		and	al, NOT 7 ; clear bit 0 to 2
				; (truncate the end of file -or block-
				;  to a multiple of eight)
		;mov	[block_size], eax

		shr	eax, 1 ; frequency 4 to 1, bits 8 to 16
		mov	[pcm_samples_output_size], eax
		;jz	short .default
		mov	dword [convert_pcm_data], stereo_quarter_8to16bit
		retn
.default:
		and 	byte [convert], 4 ; clear flags except /FAST flag
		retn

.s_chk_q_8bit:
		test	byte [convert], 8 ; 8bit flag
		jz	short .s_quarter_chk_bits

		; stereo input, stereo output, quarter frequency
		; 16bit input, 8bit output

		and	al, NOT 15 ; clear bit 0 to 3
				; (truncate the end of file -or block-
				;  to a multiple of sixteen)
		;mov	[block_size], eax
		
		shr	eax, 3 ; frequency 4 to 1, bits 16 to 8
		mov	[pcm_samples_output_size], eax
		;jz	short .default
		mov	dword [convert_pcm_data], stereo_quarter_16to8bit
		retn

.s_quarter_chk_bits:
		cmp	byte [wav_input_bits_per_sample], 16
		jnz	short .s_quarter_8bit
.s_quarter_16bit:
		; stereo input, stereo output, quarter frequency
		; 16bit input, 16bit output

		and	al, NOT 15 ; clear bit 0 to 3
				; (truncate the end of file -or block-
				;  to a multiple of sixteen)
		;mov	[block_size], eax

		shr	eax, 2 ; frequency 4 to 1
		mov	[pcm_samples_output_size], eax
		;jz	short .default
		mov	dword [convert_pcm_data], stereo_quarter_16bit
		retn

.s_quarter_8bit:
		; stereo input, stereo output, quarter frequency
		; 8bit input, 8bit output

		and	al, NOT 7 ; clear bit 0 to 2
				; (truncate the end of file -or block-
				;  to a multiple of eight)
		;mov	[block_size], eax

		shr	eax, 2 ; frequency 4 to 1
		mov	[pcm_samples_output_size], eax
		;jz	short .default
		mov	dword [convert_pcm_data], stereo_quarter_8bit
		retn

.s_chk_half:
		test	byte [convert], 32 ; half flag
		jz	.s_chk_bits
		; stereo input, stereo output, half frequency

		; stereo input, stereo output, half frequency
		test	byte [convert], 16 ; 16bit flag
		jz	short .s_chk_h_8bit
.s_chk_h_16bit:
		; stereo input, stereo output, half frequency
		; 8bit input, 16bit output

		and	al, NOT 3 ; clear bit 0 & 1
				; (truncate the end of file -or block-
				;  to a multiple of four)
		;mov	[block_size], eax

		;shr	eax, 0 ; frequency 2 to 1, bits 8 to 16
		mov	[pcm_samples_output_size], eax
		;or	eax, eax
		;jz	short .default
		mov	dword [convert_pcm_data], stereo_half_8to16bit
		retn

.s_chk_h_8bit:
		test	byte [convert], 8 ; 8bit flag
		jz	short .s_chk_h_16bps

		; stereo input, stereo output, half frequency
		; 16bit input, 8bit output

		and	al, NOT 7 ; clear bit 0 to 2
				; (truncate the end of file -or block-
				;  to a multiple of eight)
		;mov	[block_size], eax

		shr	eax, 2 ; frequency 2 to 1, bits 16 to 8
		mov	[pcm_samples_output_size], eax
		;jz	.default
		mov	dword [convert_pcm_data], stereo_half_16to8bit
		retn

.s_chk_h_16bps:
		cmp	byte [wav_input_bits_per_sample], 16
		jne	short .s_chk_h_8bps

		; stereo input, stereo output, half frequency
		; 16bit input, 16bit output

		and	al, NOT 7 ; clear bit 0 to 2
				; (truncate the end of file -or block-
				;  to a multiple of eight)
		;mov	[block_size], eax

		shr	eax, 1 ; frequency 2 to 1
		mov	[pcm_samples_output_size], eax
		;jz	.default
		mov	dword [convert_pcm_data], stereo_half_16bit
		retn

.s_chk_h_8bps:
		; stereo input, stereo output, half frequency
		; 8bit input, 8bit output

		and	al, NOT 3 ; clear bit 0 & 1
				; (truncate the end of file -or block-
				;  to a multiple of four)
		;mov	[block_size], eax

		shr	eax, 1 ; frequency 2 to 1
		mov	[pcm_samples_output_size], eax
		;jz	.default
		mov	dword [convert_pcm_data], stereo_half_8bit
		retn

.m_chk_quar:
		; mono input, mono output
		test	byte [convert], 64 ; quarter flag
		jz	short .m_chk_half
		; mono input, mono output, quarter frequency
		test	byte [convert], 16 ; 16bit flag
		jz	short .m_chk_q_8bit
.m_chk_q_16bit:
		; mono input, mono output, quarter frequency
		; 8bit input, 16bit output

		and	al, NOT 3 ; clear bit 0 & 1
				; (truncate the end of file -or block-
				;  to a multiple of four)
		;mov	[block_size], eax

		shr	eax, 1 ; frequency 4 to 1, bits 8 to 16
		mov	[pcm_samples_output_size], eax
		;jz	.default
		mov	dword [convert_pcm_data], mono_quarter_8to16bit
		retn

.m_chk_q_8bit:
		test	byte [convert], 8 ; 8bit flag
		jz	short .m_chk_q_16bps

		; mono input, mono output, quarter frequency
		; 16bit input, 8bit output

		and	al, NOT 7 ; clear bit 0 to 2
				; (truncate the end of file -or block-
				;  to a multiple of eight)
		;mov	[block_size], eax
		
		shr	eax, 3 ; frequency 4 to 1, bits 16 to 8
		mov	[pcm_samples_output_size], eax
		;jz	.default
		mov	dword [convert_pcm_data], mono_quarter_16to8bit
		retn

.m_chk_q_16bps:
		cmp	byte [wav_input_bits_per_sample], 16
		jne	short .m_chk_q_8bps

		; mono input, mono output, same frequency
		; 16bit input, 16bit output

		and	al, NOT 7 ; clear bit 0 to 2
				; (truncate the end of file -or block-
				;  to a multiple of eight)
		;mov	[block_size], eax

		shr	eax, 2 ; frequency 4 to 1
		mov	[pcm_samples_output_size], eax
		;jz	.default
		mov	dword [convert_pcm_data], mono_quarter_16bit
		retn

.m_chk_q_8bps:
		; mono input, mono output, same frequency
		; 8bit input, 8bit output

		and	al, NOT 3 ; clear bit 0 & 1
				; (truncate the end of file -or block-
				;  to a multiple of four)
		;mov	[block_size], eax

		shr	eax, 2 ; frequency 4 to 1
		mov	[pcm_samples_output_size], eax
		;jz	.default
		mov	dword [convert_pcm_data], mono_quarter_8bit
		retn

.m_chk_half:
		test	byte [convert], 32 ; half flag
		jz	short .m_chk_bits
		; mono input, mono output, half frequency

		; mono input, mono output, half frequency
		test	byte [convert], 16 ; 16bit flag
		jz	short .m_chk_h_8bit
.m_chk_h_16bit:
		; mono input, mono output, half frequency
		; 8bit input, 16bit output

		and	al, NOT 1 ; clear bit 0
				; (truncate the end of file -or block-
				;  to an even number)
		;mov	[block_size], eax

		;shr	eax, 0 ; frequency 2 to 1, bits 8 to 16
		mov	[pcm_samples_output_size], eax
		;or	eax, eax
		;jz	.default
		mov	dword [convert_pcm_data], mono_half_8to16bit
		retn

.m_chk_h_8bit:
		;test	byte [convert], 8 ; 8bit flag
		;jz	short .m_chk_nothing_to_do

		; mono input, mono output, half frequency
		; 16bit input, 8bit output

		and	al, NOT 3 ; clear bit 0 & 1
				; (truncate the end of file -or block-
				;  to a multiple of four)
		;mov	[block_size], eax
		
		shr	eax, 2 ; frequency 2 to 1, bits 16 to 8
		mov	[pcm_samples_output_size], eax
		;jz	.default
		mov	dword [convert_pcm_data], mono_half_16to8bit
		retn

.m_chk_h_16bps:
		cmp	byte [wav_input_bits_per_sample], 16
		jne	short .m_chk_h_8bps

		; mono input, mono output, half frequency
		; 16bit input, 16bit output

		and	al, NOT 3 ; clear bit 0 & 1
				; (truncate the end of file -or block-
				;  to a multiple of for)
		;mov	[block_size], eax

		shr	eax, 1 ; frequency 2 to 1
		mov	[pcm_samples_output_size], eax
		;jz	.default
		mov	dword [convert_pcm_data], mono_half_16bit
		retn

.m_chk_h_8bps:
		; mono input, mono output, half frequency
		; 8bit input, 8bit output

		and	al, NOT 1 ; clear bit 0
				; (truncate the end of file -or block-
				;  to an even number)
		;mov	[block_size], eax

		shr	eax, 1 ; frequency 2 to 1
		mov	[pcm_samples_output_size], eax
		;jz	.default
		mov	dword [convert_pcm_data], mono_half_8bit
		retn

.m_chk_bits:
		test	byte [convert], 16  ; 16bit?
		jz	short .m_m_8bit
.m_m_16bit:
		; mono input, mono output, same frequency
		; 8bit input, 16bit output
		
		;mov	[block_size], eax

		shl	eax, 1 ; bits 8 to 16
		mov	[pcm_samples_output_size], eax
		mov	dword [convert_pcm_data], mono_same_8to16bit
		retn

.m_m_8bit:
		;test	byte [convert], 8 ; 8bit flag
		;jz	short .m_chk_nothing_to_do

		; mono input, mono output, same frequency
		; 16bit input, 8bit output

		and	al, NOT 1 ; clear bit 0
				; (truncate the end of file -or block-
				;  to an even number)
		;mov	[block_size], eax

		shr	eax, 1 ; bits 16 to 8
		mov	[pcm_samples_output_size], eax
		mov	dword [convert_pcm_data], mono_same_16to8bit
		retn

.s_chk_bits:
		test	byte [convert], 16  ; 16bit?
		jz	short .s_s_8bit
.s_s_16bit:
		; stereo input, streo output, same frequency
		; 8bit input, 16bit output
		
		;mov	[block_size], eax

		shl	eax, 1 ; bits 8 to 16
		mov	[pcm_samples_output_size], eax
		mov	dword [convert_pcm_data], stereo_same_8to16bit
		retn

.s_s_8bit:
		;test	byte [convert], 8 ; 8bit flag
		;jz	short .m_chk_nothing_to_do

		; stereo input, streo output, same frequency
		; 16bit input, 8bit output

		and	al, NOT 1 ; clear bit 0
				; (truncate the end of file -or block-
				;  to an even number)
		;mov	[block_size], eax

		shr	eax, 1 ; bits 16 to 8
		mov	[pcm_samples_output_size], eax
		mov	dword [convert_pcm_data], stereo_same_16to8bit
		retn
		
.m_to_s_chk_quar:
.s_to_m_chk_quar:
		jmp	.default


; ---------------------------------------------------------------------------

; [convert_pcm_data] functions
;      input:
;	     eax = pcm in block size in bytes
;            esi = pcm in block address
;            edi = pcm out block address  
;      output:
;	     pcm out buffer is filled with converted pcm data
;	     [pcm_samples_output_size] will be changed if the last block
;	     (If pcm in block size is not compatible with pcm out block
;	      a few bytes will be discarded.
;	      It is better to set pcm in block size to multiple of 16 or 8.)
;	     If [pcm_samples_output_size] = 0, audio playing must be ended.	 
;	     		
;      modified registers: eax, ebx, ecx, edx, esi, edi, ebp	

; ==========
; Functions:
; ==========

; ---01----------------------------------------------------------------------

stereo_quarter_16to8bit:
		; convert 16bit stereo block 
		;	to 8bit quarter frequency

		and	al, NOT 15 ; clear bit 0 to 3
				; (truncate the end of file -or block-
				;  to a multiple of sixteen)
		;mov	[block_size], eax

		shr	eax, 3 ; frequency 4 to 1, bits 16 to 8
		mov	[pcm_samples_output_size], eax
		jnz	short .do
		retn
.do:
		mov	ecx, eax ; bytes in the block
		shr	ecx, 4	; 16bit samples, stereo
		; 4 to 1 interpolation (peak point method)
		xor	eax, eax
.s_q_16to8_loop:
		xor	ebx, ebx
		xor	edx, edx
		xor	ebp, ebp
		;;; 4 to 1, left channel
		push	ecx ; **
		push	esi ; *
		;***L***
		mov	ecx, 4	; 4 to 1, interpolation
.s_q_16to8_l0:
		lodsw	; left channel
		sub	ax, 8000h
		add	ebp, eax ; total
		cmp	edx, eax ; max. (positive peak point)
		jnb	short .s_q_16to8_l1
		mov	edx, eax
.s_q_16to8_l1:
		cmp	ebx, eax ; min. (negative peak point)
		jna	short .s_q_16to8_l2
		mov	ebx, eax
.s_q_16to8_l2:
		lodsw		; skip right channel
		loop	.s_q_16to8_l0
		;;;;
		shr	ebp, 2	; total/4 = average
		mov	eax, ebp
		neg	eax	; - average
		add	eax, edx ; positive peak - average ; delta p
		neg	ebx	 ; - negative peak
		add	ebx, ebp ; average - negative peak ; delta n
		; Use the peak point closer to the 4-point mean
		cmp	eax, ebx ; delta p < delta n
		jb	short .s_q_16to8_l3 ; use positive peak
		sub	eax, ebx
		jz	short .s_q_16to8_l3 ; use average/mean
		mov	eax, ebx	; use negative peak
		neg	eax	; convert to negative value
.s_q_16to8_l3:
		add	eax, ebp ; one of peak (max. or min.) points
		
		shr	eax, 8	; use high byte of 16bit volume level
		stosb		; save as 8bit sound volume level
		;;;;
		pop	esi ; *
		;***R***
		;;; 4 to 1, right channel
		;xor	eax, eax
		xor	ebx, ebx
		xor	edx, edx
		xor	ebp, ebp
		mov	cl, 4	; 4 to 1, interpolation
.s_q_16to8_l4:
		lodsw		; skip left channel
		lodsw	; right channel
		sub	ax, 8000h
		add	ebp, eax ; total
		cmp	edx, eax ; max. (positive peak point)
		jnb	short .s_q_16to8_l5
		mov	edx, eax
.s_q_16to8_l5:
		cmp	ebx, eax ; min. (negative peak point)
		jna	short .s_q_16to8_l6
		mov	ebx, eax
.s_q_16to8_l6:
		loop	.s_q_16to8_l4
		;;;;
		shr	ebp, 2	; total/4 = average
		mov	eax, ebp
		neg	eax	; - average
		add	eax, edx ; positive peak - average ; delta p
		neg	ebx	 ; - negative peak
		add	ebx, ebp ; average - negative peak ; delta n
		; Use the peak point closer to the 4-point mean
		cmp	eax, ebx ; delta p < delta n
		jb	short .s_q_16to8_l7 ; use positive peak
		sub	eax, ebx
		jz	short .s_q_16to8_l7 ; use average/mean
		mov	eax, ebx
		neg	eax	; convert to negative value
.s_q_16to8_l7:
		add	eax, ebp ; one of peak (max. or min.) points
		shr	eax, 8	; use high byte of 16bit volume level
		stosb		; save as 8bit sound volume level
		;;;;
		pop	ecx ; **
		;loop	.s_q_16to8_loop
		dec	ecx
		jnz	.s_q_16to8_loop
		
		retn

; ---02----------------------------------------------------------------------

stereo_quarter_8to16bit:
		; convert 8bit stereo block 
		;	to 16bit quarter frequency

		and	al, NOT 7 ; clear bit 0 to 2
				; (truncate the end of file -or block-
				;  to a multiple of eight)
		;mov	[block_size], eax

		shr	eax, 1 ; frequency 4 to 1, bits 8 to 16
		mov	[pcm_samples_output_size], eax
		jnz	short .do
		retn
.do:
		mov	ecx, eax ; bytes in the block
		shr	ecx, 3	; 8bit samples, stereo
		; 4 to 1 interpolation (peak point method)
.s_q_8to16_loop:
		xor	eax, eax
		xor	ebx, ebx
		xor	edx, edx
		xor	ebp, ebp
		;;; 4 to 1, left channel
		push	ecx ; **
		push	esi ; *
		;***L***
		mov	ecx, 4	; 4 to 1, interpolation
.s_q_8to16_l0:
		lodsb	; left channel
		add	ebp, eax ; total
		cmp	edx, eax ; max. (positive peak point)
		jnb	short .s_q_8to16_l1
		mov	edx, eax
.s_q_8to16_l1:
		cmp	ebx, eax ; min. (negative peak point)
		jna	short .s_q_8to16_l2
		mov	ebx, eax
.s_q_8to16_l2:
		lodsb		; skip right channel
		loop	.s_q_8to16_l0
		;;;;
		shr	ebp, 2	; total/4 = average
		mov	eax, ebp
		neg	eax	; - average
		add	eax, edx ; positive peak - average ; delta p
		neg	ebx	 ; - negative peak
		add	ebx, ebp ; average - negative peak ; delta n
		; Use the peak point closer to the 4-point mean
		cmp	eax, ebx ; delta p < delta n
		jb	short .s_q_8to16_l3 ; use positive peak
		sub	eax, ebx
		jz	short .s_q_8to16_l3 ; use average/mean
		mov	eax, ebx
		neg	eax	; convert to negative value
.s_q_8to16_l3:
		add	eax, ebp ; one of peak (max. or min.) points
		shl	eax, 8	; convert 8bit peak point to 16bit
		add	ax, 8000h ; origin is 8000h (-,+) for 16bit
		stosw		; save as 16bit sound volume level
		;;;;
		pop	esi ; *
		;***R***
		;;; 4 to 1, right channel
		xor	eax, eax
		xor	ebx, ebx
		xor	edx, edx
		xor	ebp, ebp
		mov	cl, 4	; 4 to 1, interpolation
.s_q_8to16_l4:
		lodsb		; skip left channel
		lodsb	; right channel
		add	ebp, eax ; total
		cmp	edx, eax ; max. (positive peak point)
		jnb	short .s_q_8to16_l5
		mov	edx, eax
.s_q_8to16_l5:
		cmp	ebx, eax ; min. (negative peak point)
		jna	short .s_q_8to16_l6
		mov	ebx, eax
.s_q_8to16_l6:
		loop	.s_q_8to16_l4
		;;;;
		shr	ebp, 2	; total/4 = average
		mov	eax, ebp
		neg	eax	; - average
		add	eax, edx ; positive peak - average ; delta p
		neg	ebx	 ; - negative peak
		add	ebx, ebp ; average - negative peak ; delta n
		cmp	eax, ebx ; delta p < delta n
		jb	short .s_q_8to16_l7 ; use positive peak
		sub	eax, ebx
		jz	short .s_q_8to16_l7 ; use average/mean
		mov	eax, ebx
		neg	eax	; convert to negative value
.s_q_8to16_l7:
		add	eax, ebp ; one of peak (max. or min.) points
		shl	eax, 8	; convert 8bit peak point to 16bit
		add	ax, 8000h ; origin is 8000h (-,+) for 16bit
		stosw		; save as 16bit sound volume level
		;;;;
		pop	ecx ; **
		;loop	.s_q_8to16_loop
		dec	ecx
		jnz	.s_q_8to16_loop
		
		retn

; ---03----------------------------------------------------------------------

stereo_half_16to8bit:
		; convert 16bit stereo block 
		;	to 8bit half frequency

		and	al, NOT 7 ; clear bit 0 to 2
				; (truncate the end of file -or block-
				;  to a multiple of eight)
		;mov	[block_size], eax

		shr	eax, 2 ; frequency 2 to 1, bits 16 to 8
		mov	[pcm_samples_output_size], eax
		jnz	short .do
		retn
.do:
		mov	ecx, eax ; bytes in the block
		shr	ecx, 3	; 16bit samples, stereo
		xor	eax, eax
		;;; 2 to 1, interpolation (average method)
.s_h_16to8_loop:
		lodsw	; sample 1, left channel
		sub	ax, 8000h
		mov	edx, eax
		lodsw	; sample 1, right channel
		sub	ax, 8000h
		mov	ebx, eax
		lodsw	; sample 2, left channel
		sub	ax, 8000h
		add	edx, eax
		lodsw	; sample 2, right channel
		sub	ax, 8000h
		add	ebx, eax
		; left channel sample
		mov	eax, edx
		shr	eax, 1	; sum/2 = average
		shr	eax, 8	; use high byte of 16bit volume level
		stosb		; save as 8bit sound volume level
		; right channel sample
		mov	eax, ebx
		shr	eax, 1	; sum/2 = average
		shr	eax, 8	; use high byte of 16bit volume level
		stosb		; save as 8bit sound volume level
		loop	.s_h_16to8_loop

		retn

; ---04----------------------------------------------------------------------

stereo_half_8to16bit:
		; convert 8bit stereo block 
		;	to 16bit half frequency

		and	al, NOT 3 ; clear bit 0 & 1
				; (truncate the end of file -or block-
				;  to a multiple of four)
		;mov	[block_size], eax

		;shr	eax, 0 ; frequency 2 to 1, bits 8 to 16
		mov	[pcm_samples_output_size], eax
		or	eax, eax
		jnz	short .do
		retn
.do:
		mov	ecx, eax ; bytes in the block
		shr	ecx, 2	; 8bit samples, stereo
		;;; 2 to 1, interpolation (average method)
.s_h_8to16_loop:
		xor	eax, eax
		lodsb	; sample 1, left channel
		mov	edx, eax
		lodsb	; sample 1, right channel
		mov	ebx, eax
		lodsb	; sample 2, left channel
		add	edx, eax
		lodsb	; sample 2, right channel
		add	ebx, eax
		; left channel sample
		mov	eax, edx
		shr	eax, 1	; sum/2 = average
		shl	eax, 8	; convert 8bit sample to 16bit
		add	ax, 8000h ; origin is 8000h (-,+) for 16bit
		stosw		; save as 16bit sound volume level
		; right channel sample
		mov	eax, ebx
		shr	eax, 1	; sum/2 = average
		shl	eax, 8	; convert 8bit sample to 16bit
		add	ax, 8000h ; origin is 8000h (-,+) for 16bit
		stosw		; save as 16bit sound volume level
		loop	.s_h_8to16_loop

		retn

; ---05----------------------------------------------------------------------

mono_quarter_16to8bit:
		; convert 16bit mono block 
		;	to 8bit quarter frequency

		and	al, NOT 7 ; clear bit 0 to 2
				; (truncate the end of file -or block-
				;  to a multiple of eight)
		;mov	[block_size], eax
		
		shr	eax, 3 ; frequency 4 to 1, bits 16 to 8
		mov	[pcm_samples_output_size], eax
		jnz	short .do
		retn
.do:
		mov	ecx, eax ; bytes in the block
		shr	ecx, 3	; 16bit samples, mono
		xor	eax, eax
		; 4 to 1 interpolation (peak point method)
.m_q_16to8_loop:
		xor	ebx, ebx
		xor	edx, edx
		xor	ebp, ebp
		;;;
		push	ecx ; *
		mov	ecx, 4	; 4 to 1, interpolation
.m_q_16to8_l0:
		lodsw
		sub	ax, 8000h
		add	ebp, eax ; total
		cmp	edx, eax ; max. (positive peak point)
		jnb	short .m_q_16to8_l1
		mov	edx, eax
.m_q_16to8_l1:
		cmp	ebx, eax ; min. (negative peak point)
		jna	short .m_q_16to8_l2
		mov	ebx, eax
.m_q_16to8_l2:
		loop	.m_q_16to8_l0
		;;;;
		shr	ebp, 2	; total/4 = average
		mov	eax, ebp
		neg	eax	; - average
		add	eax, edx ; positive peak - average ; delta p
		neg	ebx	 ; - negative peak
		add	ebx, ebp ; average - negative peak ; delta n
		; Use the peak point closer to the 4-point mean
		cmp	eax, ebx ; delta p < delta n
		jb	short .m_q_16to8_l3 ; use positive peak
		sub	eax, ebx
		jz	short .m_q_16to8_l3 ; use average/mean
		mov	eax, ebx
		neg	eax	; convert to negative value
.m_q_16to8_l3:
		add	eax, ebp ; one of peak (max. or min.) points
		shr	eax, 8	; use high byte of 16bit volume level
		stosb		; save as 8bit sound volume level
		;;;;
		pop	ecx ; *
		loop	.m_q_16to8_loop
		
		retn

; ---06----------------------------------------------------------------------

mono_quarter_8to16bit:
		; convert 8bit mono block 
		;	to 16bit quarter frequency

		and	al, NOT 3 ; clear bit 0 & 1
				; (truncate the end of file -or block-
				;  to a multiple of four)
		;mov	[block_size], eax

		shr	eax, 1 ; frequency 4 to 1, bits 8 to 16
		mov	[pcm_samples_output_size], eax
		jnz	short .do
		retn
.do:
		mov	ecx, eax ; bytes in the block
		shr	ecx, 2	; 8bit samples, mono
		; 4 to 1 interpolation (peak point method)
.m_q_8to16_loop:
		xor	eax, eax
		xor	ebx, ebx
		xor	edx, edx
		xor	ebp, ebp
		;;;
		push	ecx ; *
		mov	ecx, 4	; 4 to 1, interpolation
.m_q_8to16_l0:
		lodsb
		add	ebp, eax ; total
		cmp	edx, eax ; max. (positive peak point)
		jnb	short .m_q_8to16_l1
		mov	edx, eax
.m_q_8to16_l1:
		cmp	ebx, eax ; min. (negative peak point)
		jna	short .m_q_8to16_l2
		mov	ebx, eax
.m_q_8to16_l2:
		loop	.m_q_8to16_l0
		;;;;
		shr	ebp, 2	; total/4 = average
		mov	eax, ebp
		neg	eax	; - average
		add	eax, edx ; positive peak - average ; delta p
		neg	ebx	 ; - negative peak
		add	ebx, ebp ; average - negative peak ; delta n
		; Use the peak point closer to the 4-point mean
		cmp	eax, ebx ; delta p < delta n
		jb	short .m_q_8to16_l3 ; use positive peak
		sub	eax, ebx
		jz	short .m_q_8to16_l3 ; use average/mean
		mov	eax, ebx
		neg	eax	; convert to negative value
.m_q_8to16_l3:
		add	eax, ebp ; one of peak (max. or min.) points
		shl	eax, 8	; convert 8bit peak point to 16bit
		add	ax, 8000h ; origin is 8000h (-,+) for 16bit
		inc	edi	; skip left channel
		inc	edi	; 16bit
		stosw		; save as 16bit sound volume level
		;;;;
		pop	ecx ; ***
		loop	.m_q_8to16_loop
		
		retn

; ---07----------------------------------------------------------------------

mono_half_16to8bit:
		; convert 16bit mono block 
		;	to 8bit half frequency

		and	al, NOT 3 ; clear bit 0 & 1
				; (truncate the end of file -or block-
				;  to a multiple of four)
		;mov	[block_size], eax
		
		shr	eax, 2 ; frequency 2 to 1, bits 16 to 8
		mov	[pcm_samples_output_size], eax
		jnz	short .do
		retn
.do:
		mov	ecx, eax ; bytes in the block
		shr	ecx, 2	; 16bit samples, mono
		xor	eax, eax
		;;; 2 to 1, interpolation (average method)
.m_h_16to8_loop:
		lodsw	; sample 1
		sub	ax, 8000h
		mov	edx, eax
		lodsw	; sample 2
		sub	ax, 8000h
		add	eax, edx ; sample1 + sample2
		shr	eax, 1	; sum/2 = average
		shr	eax, 8	; use high byte of 16bit volume level
		stosb		; save as 8bit sound volume level
		loop	.m_h_16to8_loop

		retn

; ---08----------------------------------------------------------------------

mono_half_8to16bit:
		; convert 8bit mono block 
		;	to 16bit half frequency

		and	al, NOT 1 ; clear bit 0
				; (truncate the end of file -or block-
				;  to an even number)
		;mov	[block_size], eax

		;shr	eax, 0 ; frequency 2 to 1, bits 8 to 16
		mov	[pcm_samples_output_size], eax
		or	eax, eax
		jnz	short .do
		retn
.do:
		mov	ecx, eax ; bytes in the block
		shr	ecx, 1	; 8bit samples, mono
		;;; 2 to 1, interpolation (average method)
.m_h_8to16_loop:
		xor	eax, eax
		lodsb	; sample 1
		mov	edx, eax
		lodsb	; sample 2
		add	eax, edx ; sample1 + sample2
		shr	eax, 1	; sum/2 = average
		shl	eax, 8	; convert 8bit sample to 16bit
		add	ax, 8000h ; origin is 8000h (-,+) for 16bit
		stosw		; save as 16bit sound volume level
		loop	.m_h_8to16_loop

		retn

; ---09----------------------------------------------------------------------

stereo_quarter_16bit:
		; convert 16bit stereo block 
		;	to 16bit quarter frequency

		and	al, NOT 15 ; clear bit 0 to 3
				; (truncate the end of file -or block-
				;  to a multiple of sixteen)
		;mov	[block_size], eax

		shr	eax, 2 ; frequency 4 to 1
		mov	[pcm_samples_output_size], eax
		jnz	short .do
		retn
.do:
		mov	ecx, eax ; bytes in the block
		shr	ecx, 4	; 16bit samples, stereo
		; 4 to 1 interpolation (peak point method)
.s_q_16bit_loop:
		xor	eax, eax
		xor	ebx, ebx
		xor	edx, edx
		xor	ebp, ebp
		;;; 4 to 1, left channel
		push	ecx ; ***
		push	edi ; **
		push	esi ; *
		;***L***
		mov	ecx, 4	; 4 to 1, interpolation
.s_q_16bit_l0:
		lodsw	; left channel
		sub	ax, 8000h
		add	ebp, eax ; total
		cmp	edx, eax ; max. (positive peak point)
		jnb	short .s_q_16bit_l1
		mov	edx, eax
.s_q_16bit_l1:
		cmp	ebx, eax ; min. (negative peak point)
		jna	short .s_q_16bit_l2
		mov	ebx, eax
.s_q_16bit_l2:
		lodsw		; skip right channel
		loop	.s_q_16bit_l0
		;;;;
		shr	ebp, 2	; total/4 = average
		mov	eax, ebp
		neg	eax	; - average
		add	eax, edx ; positive peak - average ; delta p
		neg	ebx	 ; - negative peak
		add	ebx, ebp ; average - negative peak ; delta n
		; Use the peak point closer to the 4-point mean
		cmp	eax, ebx ; delta p < delta n
		jb	short .s_q_16bit_l3 ; use positive peak
		sub	eax, ebx
		jz	short .s_q_16bit_l3 ; use average/mean
		mov	eax, ebx
		neg	eax	; convert to negative value
.s_q_16bit_l3:
		add	eax, ebp ; one of peak (max. or min.) points
		add	ax, 8000h ; origin is 8000h (-,+) for 16bit
		stosw		; save as 16bit sound volume level
		inc	edi	; skip right channel
		inc	edi	; 16bit
		;;;;

		pop	esi ; *
		pop	edi ; **
		;***R***
		;;; 4 to 1, right channel
		xor	eax, eax
		xor	ebx, ebx
		xor	edx, edx
		xor	ebp, ebp
		mov	cl, 4	; 4 to 1, interpolation
.s_q_16bit_l4:
		lodsw		; skip left channel
		lodsw	; right channel
		sub	ax, 8000h
		add	ebp, eax ; total
		cmp	edx, eax ; max. (positive peak point)
		jnb	short .s_q_16bit_l5
		mov	edx, eax
.s_q_16bit_l5:
		cmp	ebx, eax ; min. (negative peak point)
		jna	short .s_q_16bit_l6
		mov	ebx, eax
.s_q_16bit_l6:
		loop	.s_q_16bit_l4
		;;;;
		shr	ebp, 2	; total/4 = average
		mov	eax, ebp
		neg	eax	; - average
		add	eax, edx ; positive peak - average ; delta p
		neg	ebx	 ; - negative peak
		add	ebx, ebp ; average - negative peak ; delta n
		; Use the peak point closer to the 4-point mean
		cmp	eax, ebx ; delta p < delta n
		jb	short .s_q_16bit_l7 ; use positive peak
		sub	eax, ebx
		jz	short .s_q_16bit_l7 ; use average/mean
		mov	eax, ebx
		neg	eax	; convert to negative value
.s_q_16bit_l7:
		add	eax, ebp ; one of peak (max. or min.) points
		add	ax, 8000h ; origin is 8000h (-,+) for 16bit
		inc	edi	; skip left channel
		inc	edi	; 16bit
		stosw		; save as 16bit sound volume level
		;;;;
		pop	ecx ; ***
		;loop	.s_q_16bit_loop
		dec	ecx
		jnz	.s_q_16bit_loop
		
		retn

; ---10----------------------------------------------------------------------

stereo_quarter_8bit:
		; convert 8bit stereo block 
		;	to 8bit quarter frequency

		and	al, NOT 7 ; clear bit 0 to 2
				; (truncate the end of file -or block-
				;  to a multiple of eight)
		;mov	[block_size], eax

		shr	eax, 2 ; frequency 4 to 1
		mov	[pcm_samples_output_size], eax
		jnz	short .do
		retn
.do:
		mov	ecx, eax ; bytes in the block
		shr	ecx, 3	; 8bit samples, stereo
		; 4 to 1 interpolation (peak point method)
		xor	eax, eax
.s_q_8bit_loop:
		xor	ebx, ebx
		xor	edx, edx
		xor	ebp, ebp
		;;; 4 to 1, left channel
		push	ecx ; ***
		push	edi ; **
		push	esi ; *
		;***L***
		mov	ecx, 4	; 4 to 1, interpolation
.s_q_8bit_l0:
		lodsb	; left channel
		add	ebp, eax ; total
		cmp	edx, eax ; max. (positive peak point)
		jnb	short .s_q_8bit_l1
		mov	edx, eax
.s_q_8bit_l1:
		cmp	ebx, eax ; min. (negative peak point)
		jna	short .s_q_8bit_l2
		mov	ebx, eax
.s_q_8bit_l2:
		lodsb		; skip right channel
		loop	.s_q_8bit_l0
		;;;;
		shr	ebp, 2	; total/4 = average
		mov	eax, ebp
		neg	eax	; - average
		add	eax, edx ; positive peak - average ; delta p
		neg	ebx	 ; - negative peak
		add	ebx, ebp ; average - negative peak ; delta n
		; Use the peak point closer to the 4-point mean
		cmp	eax, ebx ; delta p < delta n
		jb	short .s_q_8bit_l3 ; use positive peak
		sub	eax, ebx
		jz	short .s_q_8bit_l3 ; use average/mean
		mov	eax, ebx
		neg	eax	; convert to negative value
.s_q_8bit_l3:
		add	eax, ebp ; one of peak (max. or min.) points
		stosb		; save as 8bit sound volume level
		inc	edi	; skip right channel
		;;;;

		pop	esi ; *
		pop	edi ; **
		;***R***
		;;; 4 to 1, right channel
		xor	eax, eax
		xor	ebx, ebx
		xor	edx, edx
		xor	ebp, ebp
		mov	cl, 4	; 4 to 1, interpolation
.s_q_8bit_l4:
		lodsb		; skip left channel
		lodsb	; right channel
		add	ebp, eax ; total
		cmp	edx, eax ; max. (positive peak point)
		jnb	short .s_q_8bit_l5
		mov	edx, eax
.s_q_8bit_l5:
		cmp	ebx, eax ; min. (negative peak point)
		jna	short .s_q_8bit_l6
		mov	ebx, eax
.s_q_8bit_l6:
		loop	.s_q_8bit_l4
		;;;;
		shr	ebp, 2	; total/4 = average
		mov	eax, ebp
		neg	eax	; - average
		add	eax, edx ; positive peak - average ; delta p
		neg	ebx	 ; - negative peak
		add	ebx, ebp ; average - negative peak ; delta n
		; Use the peak point closer to the 4-point mean
		cmp	eax, ebx ; delta p < delta n
		jb	short .s_q_8bit_l7 ; use positive peak
		sub	eax, ebx
		jz	short .s_q_8bit_l7 ; use average/mean
		mov	eax, ebx
		neg	eax	; convert to negative value
.s_q_8bit_l7:
		add	eax, ebp ; one of peak (max. or min.) points
		inc	edi	; skip left channel
		stosb		; save as 8bit sound volume level
		;;;;
		pop	ecx ; ***
		loop	.s_q_8bit_loop
		
		retn

; ---11----------------------------------------------------------------------

mono_quarter_16bit:
		; convert 16bit mono block 
		;	to 16bit quarter frequency
		
		mov	ecx, eax ; bytes in the block
		shr	ecx, 3	; 16bit samples, mono
		; 4 to 1 interpolation (peak point method)
.m_q_16bit_loop:
		xor	eax, eax
		xor	ebx, ebx
		xor	edx, edx
		xor	ebp, ebp
		;;;
		push	ecx ; *
		mov	ecx, 4	; 4 to 1, interpolation
.m_q_16bit_l0:
		lodsw
		sub	ax, 8000h
		add	ebp, eax ; total
		cmp	edx, eax ; max. (positive peak point)
		jnb	short .m_q_16bit_l1
		mov	edx, eax
.m_q_16bit_l1:
		cmp	ebx, eax ; min. (negative peak point)
		jna	short .m_q_16bit_l2
		mov	ebx, eax
.m_q_16bit_l2:
		loop	.m_q_16bit_l0
		;;;;
		shr	ebp, 2	; total/4 = average
		mov	eax, ebp
		neg	eax	; - average
		add	eax, edx ; positive peak - average ; delta p
		neg	ebx	 ; - negative peak
		add	ebx, ebp ; average - negative peak ; delta n
		; Use the peak point closer to the 4-point mean
		cmp	eax, ebx ; delta p < delta n
		jb	short .m_q_16bit_l3 ; use positive peak
		sub	eax, ebx
		jz	short .m_q_16bit_l3 ; use average/mean
		mov	eax, ebx
		neg	eax	; convert to negative value
.m_q_16bit_l3:
		add	eax, ebp ; one of peak (max. or min.) points
		add	ax, 8000h ; origin is 8000h (-,+) for 16bit
		stosw		; save as 16bit sound volume level
		;;;;
		pop	ecx ; *
		loop	.m_q_16bit_loop
		
		retn

; ---12----------------------------------------------------------------------

mono_quarter_8bit:
		; convert 8bit mono block 
		;	to 8bit quarter frequency
		
		mov	ecx, eax ; bytes in the block
		shr	ecx, 2	; 8bit samples, mono
		; 4 to 1 interpolation (peak point method)
		xor	eax, eax
.m_q_8bit_loop:
		xor	ebx, ebx
		xor	edx, edx
		xor	ebp, ebp
		;;;
		push	ecx ; *
		mov	ecx, 4	; 4 to 1, interpolation
.m_q_8bit_l0:
		lodsb
		add	ebp, eax ; total
		cmp	edx, eax ; max. (positive peak point)
		jnb	short .m_q_8bit_l1
		mov	edx, eax
.m_q_8bit_l1:
		cmp	ebx, eax ; min. (negative peak point)
		jna	short .m_q_8bit_l2
		mov	ebx, eax
.m_q_8bit_l2:
		loop	.m_q_8bit_l0
		;;;;
		shr	ebp, 2	; total/4 = average
		mov	eax, ebp
		neg	eax	; - average
		add	eax, edx ; positive peak - average ; delta p
		neg	ebx	 ; - negative peak
		add	ebx, ebp ; average - negative peak ; delta n
		; Use the peak point closer to the 4-point mean
		cmp	eax, ebx ; delta p < delta n
		jb	short .m_q_8bit_l3 ; use positive peak
		sub	eax, ebx
		jz	short .m_q_8bit_l3 ; use average/mean
		mov	eax, ebx
		neg	eax	; convert to negative value
.m_q_8bit_l3:
		add	eax, ebp ; one of peak (max. or min.) points
		stosb		; save as 8bit sound volume level
		;;;;
		pop	ecx ; ***
		loop	.m_q_8bit_loop
		
		retn

; ---13----------------------------------------------------------------------

stereo_half_16bit:
		; convert 16bit stereo block 
		;	to 16bit half frequency

		and	al, NOT 7 ; clear bit 0 to 7
				; (truncate the end of file -or block-
				;  to a multiple of eight)
		;mov	[block_size], eax

		shr	eax, 1 ; frequency 2 to 1
		mov	[pcm_samples_output_size], eax
		jnz	short .do
		retn
.do:
		mov	ecx, eax ; bytes in the block
		shr	ecx, 3	; 16bit samples, stereo
		;;; 2 to 1, interpolation (average method)
.s_h_16bit_loop:
		;xor	eax, eax
		lodsw	; sample 1, left channel
		sub	ax, 8000h
		mov	edx, eax

		lodsw	; sample 1, right channel
		sub	ax, 8000h
		mov	ebx, eax

		lodsw	; sample 2, left channel
	;sub	ax, 8000h
	;add	edx, eax

		lodsw	; sample 2, right channel
	;sub	ax, 8000h
	;add	ebx, eax

		; left channel sample
		mov	eax, edx
		;shr	eax, 1	; sum/2 = average
		add	ax, 8000h ; origin is 8000h (-,+) for 16bit
		stosw		; save as 8bit sound volume level
		; right channel sample
		mov	eax, ebx
		;shr	eax, 1	; sum/2 = average
		add	ax, 8000h ; origin is 8000h (-,+) for 16bit
		stosw		; save as 16bit sound volume level
		loop	.s_h_16bit_loop

		retn

; ---14----------------------------------------------------------------------

stereo_half_8bit:
		; convert 8bit stereo block 
		;	to 8bit half frequency

		and	al, NOT 3 ; clear bit 0 & 1
				; (truncate the end of file -or block-
				;  to a multiple of four)
		;mov	[block_size], eax

		shr	eax, 1 ; frequency 2 to 1
		mov	[pcm_samples_output_size], eax
		jnz	short .do
		retn
.do:
		mov	ecx, eax ; bytes in the block
		shr	ecx, 2	; 8bit samples, stereo
		;;; 2 to 1, interpolation (average method)
		xor	eax, eax
.s_h_8bit6_loop:
		lodsb	; sample 1, left channel
		mov	edx, eax
		lodsb	; sample 1, right channel
		mov	ebx, eax
		lodsb	; sample 2, left channel
		add	edx, eax
		lodsb	; sample 2, right channel
		add	ebx, eax
		; left channel sample
		mov	eax, edx
		shr	eax, 1	; sum/2 = average
		stosb		; save as 8bit sound volume level
		; right channel sample
		mov	eax, ebx
		shr	eax, 1	; sum/2 = average
		stosb		; save as 8bit sound volume level
		loop	.s_h_8bit6_loop

		retn

; ---15----------------------------------------------------------------------

mono_half_16bit:
		; convert 16bit mono block 
		;	to 16bit half frequency

		and	al, NOT 3 ; clear bit 0 & 1
				; (truncate the end of file -or block-
				;  to a multiple of for)
		;mov	[block_size], eax

		shr	eax, 1 ; frequency 2 to 1
		mov	[pcm_samples_output_size], eax
		jnz	short .do
		retn
.do:
		mov	ecx, eax ; bytes in the block
		shr	ecx, 2	; 16bit samples, mono
		;;; 2 to 1, interpolation (average method)
.m_h_16bit_loop:
		xor	eax, eax
		lodsw	; sample 1
		add	ax, 8000h
		mov	edx, eax
		lodsw	; sample 2
		add	ax, 8000h
		add	eax, edx ; sample1 + sample2
		shr	eax, 1	; sum/2 = average
		sub	ax, 8000h ; origin is 8000h (-,+) for 16bit
		stosw		; save as 16bit sound volume level
		loop	.m_h_16bit_loop

		retn

; ---16----------------------------------------------------------------------

mono_half_8bit:
		; convert 8bit mono block 
		;	to 8bit half frequency

; 27/10/2024
and al, not 3
;		and	al, NOT 1 ; clear bit 0
				; (truncate the end of file -or block-
				;  to an even number)
		;mov	[block_size], eax

		shr	eax, 1 ; frequency 2 to 1
		mov	[pcm_samples_output_size], eax
		jnz	short .do
		retn
.do:
		mov	ecx, eax ; bytes in the block
shr ecx, 2
		shr	ecx, 1	; 8bit samples, mono
		;;; 2 to 1, interpolation (average method)
		xor	eax, eax
.m_h_8bit_loop:
		lodsb	; sample 1
		mov	edx, eax
		lodsb	; sample 2
mov ebx, eax
lodsb  ; add sample 3 to sample 1
 
		add	eax, edx ; sample1 + sample2

		shr	eax, 1	; sum/2 = average
		stosb		; save as 8bit sound volume level
lodsb
add eax, ebx  ; add sample 4 to sample 2
shr eax, 1
stosb
		loop	.m_h_8bit_loop

		retn

;; ---17----------------------------------------------------------------------

stereo_same_16to8bit:
		; convert 16bit stereo block to 8bit
		
		mov	ecx, eax ; bytes in the block
		shr	ecx, 2	; 16bit samples, stereo
		;xor	eax, eax
.s_sf_16to8_loop:
		lodsw	; left channel
		sub	ax, 8000h  ; change origin to 0
		shr	eax, 8 ; convert to 8bit sample
		stosb
		lodsw	; right channel
		sub	ax, 8000h  ; change origin to 0
		shr	eax, 8 ; convert to 8bit sample
		stosb
		loop	.s_sf_16to8_loop

		retn

; ---18----------------------------------------------------------------------

stereo_same_8to16bit:
		; convert 8bit stereo block to 16bit
		
		mov	ecx, eax ; bytes in the block
		shr	ecx, 1	; 8bit samples, stereo
		;;; 2 to 1, interpolation (average method)
.s_sf_8to16_loop:
		;xor	eax, eax
		lodsb	; left channel
		shl	eax, 8	; convert to 16bit sample
		add	ax, 8000h ; convert origin to 8000h
		stosw		; save as 16bit sample (L)
		lodsb	; right channel
		shl	eax, 8 ; convert to 16bit sample
		add	ax, 8000h ; convert origin to 8000h
		stosw		; save as 16bit sample (R)
		loop	.s_sf_8to16_loop

		retn

; ---19----------------------------------------------------------------------

mono_same_16to8bit:
		; convert 16bit mono block to 8bit
		
		mov	ecx, eax ; bytes in the block
		shr	ecx, 1	; 16bit samples, mono
		;xor	eax, eax
.m_sf_16to8_loop:
		lodsw	; 16bit sample
		sub	ax, 8000h
		shr	eax, 8 ; convert to 8bit sample
		stosb
		loop	.m_sf_16to8_loop

		retn

; ---20----------------------------------------------------------------------

mono_same_8to16bit:
		; convert 8bit mono block to 16bit
		
		mov	ecx, eax ; bytes in the block
.m_sf_8to16_loop:
		;xor	eax, eax
		lodsb
		shl	eax, 8	; convert to 16bit sample
		add	ax, 8000h
		stosw
		loop	.m_sf_8to16_loop

		retn

; ===========================================================================

section '.data' data readable writeable

cpuid_flags     dd 0
cpuid_exists    db 0
detected_cpu    db 0

option_test     db 0
option_channels db 0
option_bits     db 0
option_rate_shift db 0
option_fast     db 0

		align 4

; HANDLE hProcess
;hProcess       dd 0
; HANDLE hThread
;hThread        dd 0
; DWORD dwPriorityClass
;dwPriorityClass dd 0
; int nPriority
;nPriority      dd 0

rdtsc_interpolat dd 0, 0
		db ' interpolation     ',0
		db 0
rdtsc_element_size = $ - rdtsc_interpolat
rdtsc_read_input dd 0, 0
                db ' read input file   ',0
                db 0 
rdtsc_write_output dd 0, 0
                db ' write output file ',0
		db 0
rdtsc_total     dd 0, 0
                db ' total             ',0
		db 0
rdtsc_list_size = $ - rdtsc_interpolat
wrchr_buf       db 0
                align 4
; LPCSTR mp3_src_fname
wav_src_fname   dd 0
; LPCSTR mp3_dst_fname
wav_dst_fname   dd 0
wav_outf_header db 'RIFF$',0,0,0,'WAVEfmt ',10h,0,0,0,1,0,2,0,0,0,0,0,0,0,0,0,4,0,10h,0,'data',0,0,0,0
have_wave_error dd 0
num_enqueued_blocks dd 0
; const WAVEFORMATEX wfx
wfx WAVEFORMATEX 1,2,0,0,4,10h,0 ; 22/10/2024
		align 4
; struct wavehdr_tag wave_block_headers
wave_block_headers wavehdr_tag 0  ; 22/10/2024
                db 224 dup(0)
end_of_blocks   dd 0
txt_pefform_timing1 db 'audio duration ',0
txt_perform_timing2 db ' milliseconds, performed in ',0
txt_decode_timing3 db ' milliseconds',0Dh,0Ah,0
txt_clks_per_second db ' clock cycles:',0Dh,0Ah,0

;txt_hello      db 'nocash mp3 decoder v1.4, 2024 martin korth, press ctrl+c to quit,'
;               db ' BDS now',0Dh,0Ah,0
; Erdogan Tan - 22/10/2024
txt_hello:      db 13,10,'WAV PLAYER v1.0 for Windows ',0
txt_file        db 'file: ',0
txt_file_size   db 'file size: ',0
txt_input       db 'input: ',0
txt_output      db 'output: ',0
txt_hz          db ' hz, ',0
txt_channels    db ' channels, ',0
txt_bit         db ' bit',0
txt_bytes       db ' bytes',0Dh,0Ah,0
txt_not_found   db 'cannot open source file',0Dh,0Ah,0
txt_help        db 'usage: wavplay input.wav [output.wav] [output.pcm] [/test]',0Dh,0Ah
                db '                         [/mono|/stereo] [/8bit|16bit] [/fast] [/half|/quarter]',0Dh,0Ah
		db '		(example: wavplay input.wav /mono /8bit /half)',0Dh,0Ah
		db '			          default options: same with input file', 0Dh,0Ah
		db 0Dh,0Ah
		db '    or wavplay input.pcm [output.wav] [/test]',0Dh,0Ah
		db '                         [/F:Hertz] [/B:8|B:16] [/C:2|C:1]',0Dh,0Ah
		db '		(example: wavplay input.pcm /F:22050 /B:16 /C:2)',0Dh,0Ah
		db '		                   default: /F:44100 /B:16 /C:2',0Dh,0Ah
		db 0Dh,0Ah,0
txt_waveout_error1 db 0Dh,0Ah
                db '   *** ERROR number ',0
txt_waveout_error2 db ' in function ',0
txt_waveout_error3 db 0Dh,0Ah
                db '    ... bugdefect.@@@+critical\&&&-kaputt_###~F:A:I:L:U:R:E',0Dh,0Ah
                db 0Dh,0Ah,0
txt_ERROR       db 'ERROR',0
txt_waveopen_failed db '  ERROR: cannot open wave output!',0Dh,0Ah,0
warn_errmsg_1   db 'waveOutPrepareHeader',0
warn_errmsg_2   db 'waveOutUnprepareHeader',0
warn_errmsg_3   db 'waveOutWrite',0
warn_errmsg_4   db 'waveOutOpen',0
warn_errmsg_5   db 'waveOutPause',0
warn_errmsg_6   db 'waveOutRestart',0
warn_errmsg_7   db 'waveOutReset',0
warn_errmsg_8   db 'waveOutClose',0

; 23/10/2024
txt_invalid_wavf db 'Not a valid WAV file !',0Dh,0Ah,0
txt_improper_wavf db 'Not a proper WAV file for this program !',0Dh,0Ah,0
txt_improper_pcmf db 'Not a proper PCM file !',0Dh,0Ah,0
txt_fast        db '*** fast play (twice the frequency) *** ',0Dh,0Ah,0

wav_input:	db 0
wav_output:	db 0
convert:	db 0

; Erdogan Tan - 22/10/2024
               ;db 'WAV PLAYER v1.0 for Windows ',0
txt_ctrlc       db '(press CTRL+C to quit)', 13,10',0
txt_about       db 13,10
                db '---------------------------',13,10
                db 'by Erdogan Tan - 26/10/2024', 13,10
                db 13,10,0

; ===========================================================================

section '.bss' data readable writeable

input_file_size dd ?
wav_total_input_size dd ?

; HANDLE hFile
hFile           dd ?
; HANDLE hMap
hMap            dd ?
stream_start    dd ?
stream_pos      dd ?
bytes_left      dd ?
; DWORD diskresult
diskresult      dd ?
; HANDLE std_out
std_out         dd ?
waveout_handle	dd ?
; HANDLE output_file_handle
output_file_handle dd ?
; HANDLE input_file_handle
input_file_handle  dd ?
wav_output_sample_rate dd ?
wav_output_num_channels dd ?
wav_output_bytes_per_sample dd ?
wav_output_bits_per_sample dd ?
wav_input_sample_rate dd ?
wav_input_num_channels dd ?
wav_input_bytes_per_sample dd ?
wav_input_bits_per_sample dd ?
output_milliseconds dd ? 
millisecond_count dd ?
pcm_frequency   dd ?
pcm_bits        dd ?
pcm_channels    dd ?
block_size      dd ?
pcm_samples_output_size dd ?
; 25/10/2024
convert_pcm_data dd ?
cmdline_buf     db 1024 dup(?)
		align 16
sample_buffer   db 8*(8192*2*2) dup(?) ; max. possible size

; ===========================================================================

section '.idata' import data readable writeable

  dd 0,0,0,rva kernel_name,rva kernel_table
  dd 0,0,0,rva winmm_name,rva winmm_table
  dd 0,0,0,0,0

  kernel_table:
    ;GetCurrentProcess dd rva _GetCurrentProcess
    ;GetCurrentThread dd rva _GetCurrentThread
    ;GetPriorityClass dd rva _GetPriorityClass
    ;GetThreadPriority dd rva _GetThreadPriority
    ;SetPriorityClass dd rva _SetPriorityClass
    ;SetThreadPriority dd rva _SetThreadPriority
    GetCommandLineA dd rva _GetCommandLineA
    WriteFile dd rva _WriteFile
    CreateFileA dd rva _CreateFileA
    GetFileSize dd rva _GetFileSize
    CreateFileMappingA dd rva _CreateFileMappingA
    MapViewOfFile dd rva _MapViewOfFile
    SetFilePointer dd rva _SetFilePointer
    CloseHandle dd rva _CloseHandle
    ReadFile dd rva _ReadFile
    Sleep dd rva _Sleep
    GetStdHandle dd rva _GetStdHandle
    GetTickCount dd rva _GetTickCount
    ExitProcess dd rva _ExitProcess
    UnmapViewOfFile dd rva _UnmapViewOfFile
    dd 0

  kernel_name db 'KERNEL32.DLL',0

  ;_GetCurrentProcess dw 0
  ; db 'GetCurrentProcess',0
  ;_GetCurrentThread dw 0
  ; db 'GetCurrentThread',0
  ;_GetPriorityClass dw 0
  ; db 'GetPriorityClass',0
  ;_GetThreadPriority dw 0
  ; db 'GetThreadPriority',0
  ;_SetPriorityClass dw 0
  ; db 'SetPriorityClass',0
  ;_SetThreadPriority dw 0
  ; db 'SetThreadPriority',0
  _GetFileSize dw 0
   db 'GetFileSize',0
  _CreateFileMappingA dw 0
   db 'CreateFileMappingA',0
  _MapViewOfFile dw 0
   db 'MapViewOfFile',0
  _Sleep dw 0
   db 'Sleep',0
  _ExitProcess dw 0
    db 'ExitProcess',0
  _CreateFileA dw 0
    db 'CreateFileA',0
  _ReadFile dw 0
    db 'ReadFile',0
  _WriteFile dw 0
    db 'WriteFile',0
  _CloseHandle dw 0
    db 'CloseHandle',0
  _GetCommandLineA dw 0
    db 'GetCommandLineA',0
  _SetFilePointer dw 0
    db 'SetFilePointer',0
  _GetStdHandle dw 0
    db 'GetStdHandle',0
  _GetTickCount dw 0
    db 'GetTickCount',0
  _UnmapViewOfFile dw 0
    db 'UnmapViewOfFile',0

  winmm_table:
    waveOutPrepareHeader dd rva _waveOutPrepareHeader
    waveOutUnprepareHeader dd rva _waveOutUnprepareHeader
    waveOutWrite dd rva _waveOutWrite
    waveOutOpen dd rva _waveOutOpen
    waveOutPause dd rva _waveOutPause
    waveOutRestart dd rva _waveOutRestart
    waveOutReset dd rva _waveOutReset
    waveOutClose dd rva _waveOutClose
    dd 0

  winmm_name db 'WINMM.DLL',0

  _waveOutUnprepareHeader dw 0
    db 'waveOutUnprepareHeader',0
  _waveOutRestart dw 0
    db 'waveOutRestart',0
  _waveOutReset dw 0
    db 'waveOutReset',0
  _waveOutPrepareHeader dw 0
    db 'waveOutPrepareHeader',0
  _waveOutPause dw 0
    db 'waveOutPause',0
  _waveOutOpen dw 0
    db 'waveOutOpen',0
  _waveOutWrite dw 0
    db 'waveOutWrite',0
  _waveOutClose dw 0
    db 'waveOutClose',0

; ===========================================================================
; end
