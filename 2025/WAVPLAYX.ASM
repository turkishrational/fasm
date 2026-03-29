; ****************************************************************************
; WAVPLAY.EXE - WAVE PLAYER 1.0 for WINDOWS (console)
; ----------------------------------------------------------------------------
;
; Erdogan Tan - 22/10/2024
;
; [ Last Modification: 24/10/2024 ]
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
                mov     eax, [wav_total_output_size]
                mov     edx, 1000
                mul     edx
                div     [wav_output_sample_rate]
                xor     edx, edx
                div     [wav_output_num_channels]
                xor     edx, edx
                div     [wav_output_bytes_per_sample]
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
		shr	ebx, 3
		; ebx = bytes per sample
		mul	ebx ; * channels
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
                mov	[wav_total_output_size], edx

		mov	edx, 4800
		xchg	eax, edx
		cmp	edx, 48000
		je	short .cont
		mov	eax, 4100
		cmp	edx, 44100
		je	short .cont
		cmp	edx, 22050
		je	short .cont
		mov	eax, 3675
		cmp	edx, 11025
		je	short .cont
		mov	eax, 4000
.cont:
		mul	ecx ; * 2 (or * 1)
		mul	ebx ; * 2 (or * 1)

		mov	[block_size], eax
			 ; example: (4800*2*2) = 19200 bytes

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
		jna	short .done
		cmp	eax, 24000
		ja	short .done
		or	byte [convert], 4
.done:
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
		cmp	word [ebx+1], 'F:'
		jne	short .not_switch_pcm_f
		mov	eax, [ebx+3]
		mov	edx, [ebx+7]
		call	convert_to_number
		call	is_valid_frequency
		jc	short .help
		mov	[pcm_frequency], eax
                jmp     .get_items_lop
.not_switch_pcm_f:
		cmp	word [ebx+1], 'B:'
		jne	short .not_switch_pcm_b
		mov	eax, [ebx+3]
		xor	edx, edx
		call	convert_to_number
		call	is_valid_bits
		jc	short .help
		mov	[pcm_bits], eax
                jmp     .get_items_lop 
.not_switch_pcm_b:
		cmp	word [ebx+1], 'C:'
		jne	short .not_switch_pcm_c
		mov	eax, [ebx+3]
		xor	edx, edx
		call	convert_to_number
		call	is_valid_channels
		jc	short .help
		mov	[pcm_channels], eax
.not_switch_pcm_c:
                jmp     short .help

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
		jb	short .mul_stc
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
		jna	short .ok
		stc
.ok:
		retn

; ---------------------------------------------------------------------------

		; 22/10/2024
is_valid_channels:
		cmp	eax, 1
		jna	short .ok
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
                push    0               ; lpName
                push    0               ; dwMaximumSizeLow
                push    0               ; dwMaximumSizeHigh
                push    2               ; flProtect
                push    0               ; lpFileMappingAttributes
                push    [hFile]      ; hFile
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
                call    wrstr_edx
                ;stc
                ;retn
		;jmp short .done
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
.lop:
                ;mov    esi, [stream_pos]
                ;mov    ecx, [bytes_left]
                mov     edi, sample_buffer
                call    read_pcm_data_block
		
		;cmp	byte [convert], 0
		test	byte [convert], not 4  ; except /FAST switch
		jz	short .skip_convert
                call	convert_pcm_data
.skip_convert:
		or	eax, eax
		jz	short .exit

		mov	[pcm_data_output_size], eax

                push    0               ; lpOverlapped
                push    diskresult ; lpNumberOfBytesWritten
                push    [pcm_samples_output_size] ; nNumberOfBytesToWrite
                push    sample_buffer ; lpBuffer
                push    [output_file_handle] ; hFile
                call    [WriteFile]
                mov     eax, [pcm_data_output_size]
                add     dword [wav_outf_header+4], eax
                add     dword [wav_outf_header+40], eax
                jmp     short .lop

.exit:
                call    close_output_file

		test    byte [cpuid_flags], 10h
                jz      short .no_rdtsc_supported2
                rdtsc
                add     [rdtsc_write_output], eax
                adc     [rdtsc_write_output+4], edx
.no_rdtsc_supported2:

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
		mov	eax, [block_size]
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
		add	edi, [block_size] ; 24/10/2024
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
		retn
.do:
		push	esi
		;push	ebx
                ;mov    esi, [stream_pos]
                ;mov    ecx, [bytes_left]
                mov     edi, [ebx]
                call    read_pcm_data_block
                ;pop	ebx
		pop	esi
                mov     [ebx+4], eax	; block size
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
		test	byte [convert], not 4  ; except /FAST switch
		jz	short .same
		; edi = block address
		; eax = block size
		; (new block size will be same)
		call	convert_pcm_data	
.same:
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
               ; retn


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
		mov	edx, txt_fast	; "fast play"
		call    wrstr_edx

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

		; 24/10/2024
convert_pcm_data:

return
		; edi = buffer/block address
		; eax = block size

		xor	ecx, ecx
		test	byte [convert], 2 ; stereo flag
		jz	short .not_to_stereo
		
		

.not_to_stereo:

		pusha
		test	byte [convert], 2 ; stereo flag
		jz	short .not_to_stereo

		;cmp	byte [wav_input_num_channels], 1 ; mono ?
		;jne	short .not_to_stereo


		mov	ecx, eax
		mov	esi, edi
		mov	ebx, esi

		xor 	eax, eax

		; mono to stereo
		test	byte [convert], 64 ; quarter flag	 		
		jz	short .not_mono_to_quar_ster

		shr	ecx, 1
		
		cmp	byte [wav_input_bits_per_sample], 8 ; 8 bit
		jne	short .16bit_mono_to_stereo

.8bit_mono_to_stereo:
		lodsb	; sample 1
		mov	edx, eax
		lodsb	; sample 2
		mov	ebx, eax
		lodsb	; sample 3
		; interpolation (average)
		add	eax, edx
		shr	eax, 1
		stosb	; new sample 1 left
		push	eax
		lodsb	; sample 4
		; interpolation (average)
		add	eax, ebx
		shr	eax, 1
		stosb	; new sample 1 right
		pop	edx
		
		loop	.8bit_mono_to_stereo
		; frequency and mono to stereo conversion finished
		jmp	short .check_8bit_to_16bit

.16bit_mono_to_stereo:
		lodsw	; sample 1
		sub	ax, 8000h
		mov	edx, eax
		lodsw	; sample 2
		sub	ax, 8000h
		mov	ebx, eax
		lodsw	; sample 3
		sub	ax, 8000h
		; interpolation (average)
		add	eax, edx
		shr	eax, 1
		stosb	; new sample 1 left
		lodsb	; sample 4
		; interpolation (average)
		add	eax, ebx
		shr	eax, 1
		stosb	; new sample 1 right
		loop	.8bit_mono_to_stereo
		; frequency and mono to stereo conversion finished		

.not_mono_to_quar_ster:
	

.not_to_stereo:

.check_8bit_to_16bit: 


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
                db 'by Erdogan Tan - 24/10/2024', 13,10
                db 13,10,0

; ===========================================================================

section '.bss' data readable writeable

input_file_size dd ?
wav_total_output_size dd ?
       
; DWORD pcm_data_output_size
pcm_data_output_size dd ?
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
cmdline_buf     db 1024 dup(?)
sample_buffer   db 8*(4800*2*2) dup(?) ; max. possible size

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
