format PE64 GUI
entry start

section '.text' code readable executable

  start:
        sub     rsp,8*5         ; reserve stack for API use and make stack dqword aligned

        mov     r9d,0
        lea     r8,[_caption]
        lea     rdx,[_message]
        mov     rcx,0
        call    [myMessageBoxW]

        mov     ecx,eax
        call    [myExitProcess]

section '.data' data readable writeable

  _caption du 'Win64 assembly program',0
  _message du 'Hello World!',0
align 16
  myMessageBoxA dq 0x000000007729E96C
  myMessageBoxW dq 0x000000007729E9C4
  myExitProcess dq 0x0000000077320290



section '.idata' import data readable writeable

  dd 0,0,0,RVA kernel_name,RVA kernel_table
  dd 0,0,0,RVA user_name,RVA user_table
  dd 0,0,0,0,0

  kernel_table:
    ExitProcess dq RVA _ExitProcess
    dq 0
  user_table:
    MessageBoxA dq RVA _MessageBoxA
    dq 0

  kernel_name db 'KERNEL32.DLL',0
  user_name db 'USER32.DLL',0

  _ExitProcess dw 0
    db 'ExitProcess',0
  _MessageBoxA dw 0
    db 'MessageBoxA',0   