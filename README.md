## Flat Assembler (FASM) for TRDOS 386 Operating System

TRDOS 386 adaptation/port of Tomasz Grysztar's Flat Assembler (v1.73.32)

.. FASM.PRG assembles itself ..

NOTE:
.PRG files are TRDOS 386 (32 bit, x86) flat binary executables. They start at virtual address 0 always.
(Similar to 16 bit MSDOS .COM files which start at 100h.) 
TRDOS 386 does not use segments. (Demand Paging method is used. The kernel page directory is set for 1 to 1
physical memory layout. Interrupts are set to run in the 1st 4MB -PDE entry 0- also with user's page directories.
User's segment selectors are set for 4MB base address with 4GB-4MB limit.)

(TRDOS 386 kernel handles memory as virtually -up to 4GB- flat memory by using system and user page tables.)
((In fact, TRDOS 386 programs start at 4MB physical base address but their page directories are set
  to provide virtual address 0 as start address. Maximum usable -virtual- memory for TRDOS 386 programs is 4GB-4MB.) 

How FASM assembles a TRDOS 386 binary: The answer is 'It is very easy!'.
fasm example.asm  -> creates EXAMPLE.BIN file (it will be able to run just after renaming it as EXAMPLE.PRG file) 
fasm example.asm example.prg -> creates EXAMPLE.PRG file.

Operating system depended files: FASM.ASM, SYSTEM.INC (other files are common source code files of FASM.)

Question: By using FASM.PRG in TRDOS 386 environment...
          Is it possible to assemble executable files for WINDOWS, LINUX, DOS or another operating system?
Answer: Yes. Just as FASM.EXE and Linux FASM do it.

Erdogan Tan - October 2024
