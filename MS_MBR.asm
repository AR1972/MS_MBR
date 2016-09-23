;
; begin MS-MBR - dissasembled by untermensch 4/3/2010
; assemble with FASM - flatassembler.net
;
;  =======================================================
; | >>>>   caution do not copy and paste this code   <<<< |
; | >>>> over your MBR you will loose your partition <<<< |
; | >>>>     table and will not be able to boot      <<<< |
;  =======================================================
;
; this is a nearly byte for byte dissasembly of the MBR that
; shipped with Windows 7 meaning when assembled with FASM there will
; be very few diffrences from the one that shipped with Windows 7.
;
;----------------------------------------------------------------------------
;||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||
;----------------------------------------------------------------------------

use16				      ; generate 16 bit code

reloc_addr = 600h		      ; address that the code will be relocated to
partition_table = reloc_addr + 1BEh   ; the partition table is located reloc_addr + 446 bytes

;----------------------------------------------------------------------------
loader:
;----------------------------------------------------------------------------
; we need load the volume boot sector at 7C00h
; loader will move the MBR code from where the BIOS
; loaded it (7C00h) to reloc_addr then start
; execution at reloc_addr + entry_point
;----------------------------------------------------------------------------

		xor	ax, ax
		mov	ss, ax
		mov	sp, 7C00h
		mov	es, ax
		mov	ds, ax
		mov	si, 7C00h	 ; move from
		mov	di, reloc_addr	 ; move to
		mov	cx, 200h	 ; length to move 200h = 512 bytes
		cld
		rep movsb		 ; do the move
		push	ax			  ; setup RETF - this will be popped to CS
		push	reloc_addr+entry_point	  ; setup RETF - execution will start at this offset
		retf

;----------------------------------------------------------------------------
;||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||
;----------------------------------------------------------------------------
entry_point:
;----------------------------------------------------------------------------

		sti				; start interupts
		mov	cx, 4			; set to loop 4 times
		mov	bp, partition_table

find_partition:

		cmp	byte [bp+0], 0
		jl	start_disk_operation
		jnz	error_invalid		; jump to invalid partition table error
		add	bp, 10h
		loop	find_partition
		int	18h			; fail drop to BIOS

;----------------------------------------------------------------------------
;||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||
;----------------------------------------------------------------------------
start_disk_operation:
;----------------------------------------------------------------------------

		mov	[bp+0], dl		 ; DL = drive
		push	bp
		mov	byte [bp+11h], 5
		mov	byte [bp+10h], 0

check_extensions:

		mov	ah, 41h 		 ; AH = 41h: Check Extensions Present
		mov	bx, 55AAh		 ; BX =
		int	13h
		pop	bp
		jb	extended_read_sectors	 ; CF = 0 if extensions present
		cmp	bx, 0AA55h		 ; AA55h = extensions present
		jnz	extended_read_sectors
		test	cx, 1			 ; CX = 1 if extensions present
		jz	extended_read_sectors
		inc	byte [bp+10h]

;----------------------------------------------------------------------------
;||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||
;----------------------------------------------------------------------------
extended_read_sectors:
;----------------------------------------------------------------------------

		pushad
		cmp	byte [bp+10h], 0
		jz	read_sectors
		push	dword 0
		push	dword [bp+8]		; first sector of partition
		push	word 0
		push	7C00h
		push	word 1
		push	word 10h
		mov	ah, 42h 		; AH = 42h: Extended Read Sectors From Drive
		mov	dl, [bp+0]		; DL = drive
		mov	si, sp			; SI = pointer for output
		int	13h
		lahf
		add	sp, 10h
		sahf
		jmp	read_sectors_done

;----------------------------------------------------------------------------
;||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||
;----------------------------------------------------------------------------
read_sectors:
;----------------------------------------------------------------------------

		mov	ax, 201h		; AH = 02h: Read Sectors From Drive
		mov	bx, 7C00h		; BX = pointer for output
		mov	dl, [bp+0]		; DL = drive
		mov	dh, [bp+1]		; DH = head
		mov	cl, [bp+2]		; CL = sector
		mov	ch, [bp+3]		; CH = track
		int	13h

;----------------------------------------------------------------------------
;||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||
;----------------------------------------------------------------------------
read_sectors_done:
;----------------------------------------------------------------------------

		popad
		jnb	boot_sig_check
		dec	byte [bp+11h]
		jnz	reset_disk
		cmp	byte [bp+0], 80h	; check for bootable flag
		jz	near error_loading_os
		mov	dl, 80h
		jmp	start_disk_operation

;----------------------------------------------------------------------------
;||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||
;----------------------------------------------------------------------------
reset_disk:
;----------------------------------------------------------------------------

		push	bp
		xor	ah, ah			; AH = 0
		mov	dl, [bp+0]		; DL = drive
		int	13h
		pop	bp
		jmp	extended_read_sectors

;----------------------------------------------------------------------------
;||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||
;----------------------------------------------------------------------------
boot_sig_check:
;----------------------------------------------------------------------------
; bootsector is at 7C00h
; check the last word with the boot sig (AA55)
;----------------------------------------------------------------------------

		cmp	word [7C00h+200h-2h], 0AA55h	; bootsector is at 7C00h, 200h is 512b - 2h is 2b
		jnz	error_missing_os
		push	word [bp+0]
		call	A20_controller_int
		jnz	TPM_check

;----------------------------------------------------------------------------
;||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||
;----------------------------------------------------------------------------
A20_enable:
;----------------------------------------------------------------------------

		cli
		mov	al, 0D1h
		out	64h, al
		call	A20_controller_int
		mov	al, 0DFh
		out	60h, al
		call	A20_controller_int
		mov	al, 0FFh
		out	64h, al
		call	A20_controller_int
		sti

;----------------------------------------------------------------------------
;||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||
;----------------------------------------------------------------------------
TPM_check:
;----------------------------------------------------------------------------

		mov	ax, 0BB00h		 ; check for TPM (trusted platform module)
		int	1Ah
		and	eax, eax
		jnz	jump_to_bootsector
		cmp	ebx, 'TCPA'
		jnz	jump_to_bootsector
		cmp	cx, 102h
		jb	jump_to_bootsector
		push	dword 0BB07h
		push	dword 200h
		push	dword 8
		push	ebx
		push	ebx
		push	ebp
		push	dword 0
		push	dword 7C00h
		popad
		push	word 0
		pop	es
		int	1Ah

; ---------------------------------------------------------------------------
;||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||
; ---------------------------------------------------------------------------
jump_to_bootsector:
; ---------------------------------------------------------------------------
; at this point the bootsector is loaded at 7C00h
; so now we will jump to it and start executing
; ---------------------------------------------------------------------------

		pop	dx
		xor	dh, dh
		jmp	far 0:7C00h
		int	18h	       ; fail drop to BIOS

;----------------------------------------------------------------------------
;||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||
;----------------------------------------------------------------------------
error_missing_os:
;----------------------------------------------------------------------------

		mov	al, [missing_addr+reloc_addr]
		jmp	display_error

;----------------------------------------------------------------------------
;||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||
;----------------------------------------------------------------------------
error_loading_os:
;----------------------------------------------------------------------------

		mov	al, [error_addr+reloc_addr]
		jmp	display_error

;----------------------------------------------------------------------------
;||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||
;----------------------------------------------------------------------------
error_invalid:
;----------------------------------------------------------------------------

		mov	al, [invalid_addr+reloc_addr]

;----------------------------------------------------------------------------
;||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||
; ---------------------------------------------------------------------------
display_error:
;----------------------------------------------------------------------------

		xor	ah, ah
		add	ax, 700h
		mov	si, ax

display_error_loop:

		lodsb
		cmp	al, 0
		jz	stop
		mov	bx, 7
		mov	ah, 0Eh
		int	10h
		jmp	display_error_loop

stop:

		hlt
		jmp	stop


;----------------------------------------------------------------------------
;||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||
;----------------------------------------------------------------------------
A20_controller_int:
;----------------------------------------------------------------------------

		sub	cx, cx

A20_controller_int_loop:

		in	al, 64h
		jmp	short $+2
		and	al, 2
		loopne	A20_controller_int_loop
		and	al, 2
		retn

;----------------------------------------------------------------------------
;||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||
;----------------------------------------------------------------------------
; data section
;----------------------------------------------------------------------------

invalid 		db 'Invalid partition table',0
error			db 'Error loading operating system',0
missing 		db 'Missing operating system',0
			dw 0
invalid_addr		db invalid  - 0100h
error_addr		db error    - 0100h
missing_addr		db missing  - 0100h
disk_sig		dd 0		       ; 4 bytes = optional disk signature
null_bytes		dw 0		       ; 2 bytes = null (00h)

;----------------------------------------------------------------------------
; four 16 byte primary partition tables
;----------------------------------------------------------------------------
;           >>>>   caution do not copy and paste this code   <<<<
;           >>>> over your MBR you will loose your partition <<<<
;           >>>>     table and will not be able to boot      <<<<
;----------------------------------------------------------------------------

times  10h		db 0AAh    ; partition 1
times  10h		db 0BBh    ; partition 2
times  10h		db 0CCh    ; partition 3
times  10h		db 0DDh    ; partition 4

;----------------------------------------------------------------------------

times 200h-2-($-$$)	db 0	   ; pad to 510b then add the signature
MBR_signature		dw 0AA55h  ; MBR signature

;----------------------------------------------------------------------------
;||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||
;----------------------------------------------------------------------------
;
; end of MS-MBR
;