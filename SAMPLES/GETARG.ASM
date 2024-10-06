; -----------------------------------------------------------
; Small C Compiler for TRDOS 386 (v2.0.9 and later)
; Erdogan Tan - 2024
; Beginning: 05/09/2024
; Last Update: 14/09/2024
; -----------------------------------------------------------
; Derived from 'getarg.asm' file of KolibriOS SCC source code
; 2024

; Get command line argument. 
; Entry: n    = Number of the argument.
;        s    = Destination string pointer.
;        size = Size of destination string.
;        argc = Argument count from main().
;        argv = Argument vector(s) from main().
; Returns number of characters moved on success,
; else EOF.

_getarg:	; int n; char *s; int size,argc,argv[];
PUSH EBP
MOV EBP,ESP
ADD ESP,-8	; char *str; int i;
LEA EAX,[EBP+24] ; n
MOV EBX,[EAX]	; if(n<0 | n>=argc)
XOR EAX,EAX	; 0
CALL __lt	; if(n<0
PUSH EAX	; 0 (false) or 1 (true)
;LEA EBX,[EBP+24]
;MOV EAX,[EBX]
;PUSH EAX
PUSH EBX	; n
LEA EBX,[EBP+12] ; argc
MOV EAX,[EBX]
POP EBX
CALL __ge	; | n>=argc)
POP EBX
OR EAX,EBX	; (condition 1 or condition 2)
;OR EAX,EAX
;JNZ short _0_3
JZ short _0_2	; }
_0_3:		; {*s=NULL;
LEA EAX,[EBP+20] ; pointer to *s address
MOV EBX,[EAX]	; (ebx = address of *s)
XOR EAX,EAX	; NULL
MOV [EBX],AL	; *s=NULL;  ; ([ebx] = s value)
MOV EAX,-1	; return EOF;
MOV ESP,EBP
POP EBP
RETN
_0_2:		; }
LEA EBX,[EBP-8]
;XOR EAX,EAX
;eax = 0
MOV [EBX],EAX	; i=0;
LEA EAX,[EBP-4]
PUSH EAX	; str
LEA EBX,[EBP+8] ; pointer to argv[]
MOV EAX,[EBX]
PUSH EAX	; argv[] (address)
LEA EBX,[EBP+24] ; n
MOV EAX,[EBX]
POP EBX
SHL EAX,1
SHL EAX,1	; n*4
ADD EBX,EAX	; argv[0]+4*n
MOV EAX,[EBX]	; argv[n]
POP EBX		; str (address)
MOV [EBX],EAX	; str = argv[n]
_0_4:		; while(i<size)
LEA EBX,[EBP-8]
MOV EAX,[EBX]
PUSH EAX	; i
LEA EBX,[EBP+16] ; pointer to size
MOV EAX,[EBX]
POP EBX
CALL __lt	; is i<size ?
OR EAX,EAX
JZ short _0_5	; false, jump to s[i]=NULL;
_0_6:		; true, if((s[i]=str[i])==NULL) break;
LEA EBX,[EBP+20]
MOV EAX,[EBX]
PUSH EAX	; s (address)
LEA EBX,[EBP-8]
MOV EAX,[EBX]	; i (value)
POP EBX
ADD EAX,EBX	; (i offset from start of s)
PUSH EAX	; s[i]
LEA EBX,[EBP-4]	; pointer to of *str address
MOV EAX,[EBX]	; str
PUSH EAX
LEA EBX,[EBP-8]
MOV EAX,[EBX]
POP EBX		; str (address)
ADD EBX,EAX	; (i offset from start of str)
MOVSX EAX,BYTE [EBX] ; char str[i]
POP EBX		; s[i]
MOV [EBX],AL	; s[i] = str[i]
OR EAX,EAX	; if((s[i]=str[i])==NULL
JZ short _0_5	; break;
_0_7:		; else, ++i;
LEA EBX,[EBP-8]
;MOV EAX,[EBX]
;INC EAX
;MOV [EBX],EAX
INC DWORD [EBX] ; ++i
JMP short _0_4  ; jump to while(i<size)
_0_5:
LEA EBX,[EBP+20]
MOV EAX,[EBX]
PUSH EAX	; s
LEA EBX,[EBP-8] 
MOV EAX,[EBX]	; i
POP EBX
ADD EBX,EAX	; start of s + i = s[i]
;PUSH EAX	; i
;XOR EAX,EAX	; NULL
;MOV [EBX],AL	; s[i]=NULL;
MOV BYTE [EBX],0
;;LEA EBX,[EBP-8]
;;MOV EAX,[EBX]
;POP EAX	; return i;
MOV ESP,EBP
POP EBP
RETN
