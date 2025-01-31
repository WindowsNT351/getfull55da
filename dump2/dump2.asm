;Copyright (c) 2023-2024 akm
;This content is under the MIT License.
;351 forked for 2nd ROM

;directive for NASM
[BITS 16]
SIZE equ 4096

	section .text
	global start
start:
	;set offset address for the COM program
	org	0x100
	;init variables
	mov	byte [isVGADisabled], 0
	;print credit
	mov	dx, Msg_Version
	call	print
	;check the current video mode is PS/55 text
	mov	ah, 0x0F
	int	0x10
	;mov	dx, Msg_CurVidMode
	;call	print
	;mov	dh, al
	;call	printhex
	;save current video mode
	mov	byte [curVidMode], al
	cmp	al, 8
	je	readFont_start
	cmp	al, 0xE
	je	readFont_start
	cmp	al, 0xA
	je	VidmodeIsGraph
	cmp	al, 0xD
	je	VidmodeIsGraph
	cmp	al, 0xF
	je	VidmodeIsGraph
	jmp	VidmodeIsOthers
VidmodeIsGraph:
	mov	dx, Msg_ErrVidmode
	jmp	err
VidmodeIsOthers:
	mov	dx, Msg_WarnVidmode
	call	print
	mov	ah, 1
	int	0x21
	mov	dx, Msg_CrLf
	call	print
	cmp	al, 'y'
	je	enableda
	cmp	al, 'Y'
	je	enableda
	jmp	exit
enableda:
	mov	bh, 0x08
enableda_search:
	;check POS ID of each MicroChannel adapters
	cli;Prevent interrupts
	;enable card setup and get POS ID
	mov	dx, 0x96
	in	al, dx
	and	al, 0x70
	or	al, bh
	out	dx, al
	jmp	$+2
	jmp	$+2
	mov	dx, 0x101
	in	al, dx
	xchg	al, ah
	mov	dx, 0x100
	in	al, dx
	mov	cx, ax
	;disable card setup
	mov	dx, 0x96
	in	al, dx
	and	al, 0x70
	out	dx, al
	jmp	$+2
	jmp	$+2
	sti;Allow interrupts
	;compare POS ID
	cmp	cx, 0xEFFE;Display Adapter II, III, V
	mov	dx, Msg_DANameDA2
	jz	enableda_daFound
	cmp	cx, 0xE013;Layout Display Terminal
	mov	dx, Msg_DANameLDT
	jz	enableda_daFound
	cmp	cx, 0xECCE;Display Adapter IV
	mov	dx, Msg_DANameDA4
	jz	enableda_daFound
	cmp	cx, 0xECEC;Display Adapter IV, B1
	mov	dx, Msg_DANameDB1
	jz	enableda_daFound
	cmp	cx, 0xEFD8;Display Adapter/J
	mov	dx, Msg_DANameDAJ
	jz	enableda_daFound
	and	cx, 0xFFE0
	cmp	cx, 0x9000;0x9000-0x901F Display Adapter A1, A2, Plasma
	mov	dx, Msg_DANameDA1
	jz	enableda_daFound
	inc	bh
	cmp	bh, 0x0f
	jg	enableda_daNotFound
	jmp	enableda_search
enableda_daNotFound:
	mov	dx, Msg_ErrDANotFound
	jmp	err
enableda_daFound:
	;print adapter detected message
	call	print
	mov	dx, Msg_DADetected
	call	print
	;ah bit 2-0: Channel Select
	mov	byte [cardNo], bh
	;enter video subsystem setup
	cli;Prevent interrupts
	mov	dx, 0x94
	in	al, dx
	and	al, 0xDF
	out	dx, al
	jmp	$+2
	jmp	$+2
	;disable VGA
	call	enableda_CardDisable
	;exit video subsystem setup
	mov	dx, 0x94
	in	al, dx
	or	al, 0x20
	out	dx, al
	jmp	$+2
	jmp	$+2
	mov	byte [isVGADisabled], 1
	;enter DA setup
	mov	bh, [cardNo]
	mov	dx, 0x96
	in	al, dx
	and	al, 0x70
	or	al, bh
	out	dx, al
	jmp	$+2
	jmp	$+2
	;enable DA
	call	enableda_CardEnable
	;exit DA setup
	mov	dx, 0x96
	in	al, dx
	and	al, 0x70
	out	dx, al
	jmp	$+2
	jmp	$+2
	sti;Allow interrupts
	jmp	readFont_start
readFont_start:
	xor	ax, ax
	xor	cx, cx
	mov	ah, 0x3c	;DOS 2+ - CREATE OR TRUNCATE FILE
				;ah = 3Ch, cx = file attribute, DS:DX = ASCIZ filename
	mov	dx, Name_Fontfile
	int	0x21
	mov	dx, Msg_ErrFileOpen
	jc	err

	mov	[hndl], ax
	mov	byte [bankNum], 8        ;---cheaged
loop_nextbank:
	call	ReadFont1Bank
	mov	dx, Msg_ErrFileWrite
	jc	err
nextbankif:
	mov	ah, [bankNum]
	cmp	ah, 15		;read until bank 7 (= 8 * 128k)x       bank15
	jge	loopEndRead
	inc	ah
	mov	[bankNum], ah
	jmp	loop_nextbank
loopEndRead:
	;close a file
	mov	bx, [hndl]
	mov	ah, 0x3e	;DOS: close a file
	int	0x21
	
	xor	ax, ax
	jmp	exit
;-----------------------------------------------
;
;[hndl] = file handler to write data
;[bankNum] = bank number to read (1 bank = 128 kb)
ReadFont1Bank:
	push	ax
	push	bx
	push	cx
	push	dx
	mov	word [fontAddrH], 0xA000
	;print "Reading font (bank x)..."
	mov	dx, Msg_Reading1
	call	print
	mov	dh, [bankNum]
	call	printhex
	mov	dx, Msg_Reading2
	call	print
readFont4k:
	;wait for idle
	mov	dx, 0x3E0	;sequencer register
wait3E0:
	sti
	jmp	$+2
	cli	;Prevent interrupts
	mov	al, 3
	out	dx, al
	jmp	$+2
	jmp	$+2
	inc	dx
	in	al, dx
	dec	dx
	test	al, 1
	jnz	wait3E0
	
	;setCGMemAccess
	mov	dx, 0x3E0
	mov	al, 8		;read bank register
	out	dx, al
	jmp	$+2
	jmp	$+2
	inc	dx
	in	al, dx
	mov	[bak3E0_8], al
	dec	dx
	mov	ax, 0x1008	;enable memory mapped i/o
	out	dx, ax
	jmp	$+2
	jmp	$+2
	
	;readFont
	mov	dx, 0x3E2	;font controller register
	mov	ax, 0x8008	;set linear access
	out	dx, ax
	jmp	$+2
	jmp	$+2
	mov	ax, 0x100B	;set access to font ROM
	out	dx, ax
	jmp	$+2
	jmp	$+2
	mov	ah, [bankNum]
	mov	al, 0x0A	;select bank
	out	dx, ax
	jmp	$+2
	jmp	$+2
	
	;xor	ax, ax
	;mov	si, ax
	push	0x0000
	pop	si
	push	ds
	pop	es
	mov	di, rdata
	mov	ax, [fontAddrH]
	mov	ds, ax
	mov	cx, SIZE / 2
	rep	movsw
	push	es
	pop	ds
	
	;restoreCGMemAccess
	mov	dx, 0x3E0
	mov	ah, [bak3E0_8]
	mov	al, 8
	out	dx, ax
	jmp	$+2
	jmp	$+2
	sti;Allow interrupts
	
	mov	ah, 0x40	;DOS 2+ - WRITE TO FILE OR DEVICE
	mov	bx, [hndl]
	mov	cx, SIZE
	mov	dx, rdata
	int	0x21
	jc	errReadFont
	cmp	ax, cx
	jb	errReadFont
	
	mov	ax, [fontAddrH]
	cmp	ax, 0xBF00
	jge	endReadFont
	add	ax, 0x0100
	mov	[fontAddrH], ax
	jmp	readFont4k
errReadFont:
	stc
endReadFont:
	pop	dx
	pop	cx
	pop	bx
	pop	ax
	ret
;-----------------------------------------------
print:;dx = address to the message
	push	ax
	push	ds
	;skip print if VGA is disabled
	mov	ah, [isVGADisabled]
	cmp	ah, 1
	je	print_end
	mov	ax, cs
	mov	ds, ax
	mov	ah, 9
	int	0x21
print_end:
	pop	ds
	pop	ax
	ret
;-----------------------------------------------
printhex:;dh = hexadecimal value
	push	ax
	push	cx
	push	dx
	push	ds
	mov	ah, [isVGADisabled]
	cmp	ah, 1
	je	printhex_end
	mov	ch, 1
	mov	ax, cs
	mov	ds, ax
	mov	dl, dh
	shr	dl, 4
printhex_toA:
	add	dl, 0x30
	cmp	dl, 0x39
	jbe	printhex_out
	add	dl, 7
printhex_out:
	mov	ah, 0x02
	int	0x21
	mov	dl, dh
	and	dl, 0xF
	cmp	ch, 0
	jz	printhex_end
	dec	ch
	jmp	printhex_toA
printhex_end:
	pop	ds
	pop	dx
	pop	cx
	pop	ax
	ret
;-----------------------------------------------
enableda_CardEnable:
	mov	dx, 0x102
	in	al, dx
	or	al, 0x01
	out	dx, al
	jmp	$+2
	jmp	$+2
	ret
;-----------------------------------------------
enableda_CardDisable:
	mov	dx, 0x102
	in	al, dx
	and	al, 0xFE
	out	dx, al
	jmp	$+2
	jmp	$+2
	ret
;-----------------------------------------------
err:
	call	print
	mov	al, 1
	jmp	exit
	
exit:
	mov	ah, [isVGADisabled]
	cmp	ah, 1
	je	disableda
	jmp	exit_PrintMes
disableda:
	;to save return code (AL)
	push	ax
	;enter DA setup
	cli;Prevent interrupts
	mov	bh, [cardNo]
	mov	dx, 0x96
	in	al, dx
	and	al, 0x70
	or	al, bh
	out	dx, al
	jmp	$+2
	jmp	$+2
	;disable DA
	call	enableda_CardDisable
	;exit DA setup
	mov	dx, 0x96
	in	al, dx
	and	al, 0x70
	out	dx, al
	jmp	$+2
	jmp	$+2
	;enter video subsystem setup
	mov	dx, 0x94
	in	al, dx
	and	al, 0xDF
	out	dx, al
	jmp	$+2
	jmp	$+2
	;enable VGA
	call	enableda_CardEnable
	;exit video subsystem setup
	mov	dx, 0x94
	in	al, dx
	or	al, 0x20
	out	dx, al
	jmp	$+2
	jmp	$+2
	sti;Allow interrupts
	;reset video mode
;	mov	ah, 0
;	mov	al, [curVidMode]
;	int	0x10
	pop	ax
	jmp	exit_PrintMes
exit_PrintMes:
	;to save return code (AL)
	push	ax
	cmp	al, 1
	jae	exit_err1
	mov	dx, Msg_Exit0
	jmp	exit_toDOS
exit_err1:
	mov	dx, Msg_Exit1
	jmp	exit_toDOS
exit_toDOS:
	call	print
	pop	ax
	mov	ah, 0x02
	mov	dl, 0x07	;buzz
	int	0x21
	mov	ah, 0x4c	;DOS: terminate with return code
	int	0x21

	section .data
Name_Fontfile:	db	"PS55FNTJ.BIN",0
Msg_Reading1:	db	"Reading font bank " ,"$"
Msg_Reading2:	db	" of 07 ..." ,0Dh,0Ah,"$"
Msg_CurVidMode:	db	"The current video mode is " ,"$"
Msg_ErrVidmode:	db	"Error: Must run in text mode (DOS K3.x, J4.0 or J5.0)." ,0Dh,0Ah,"$"
Msg_DANameDA2:	db	"Display Adapter II, III or V" ,"$"
Msg_DANameLDT:	db	"Layout Display Terminal" ,"$"
Msg_DANameDA4:	db	"Display Adapter IV" ,"$"
Msg_DANameDB1:	db	"Display Adapter IV or B1" ,"$"
Msg_DANameDAJ:	db	"Display Adapter /J" ,"$"
Msg_DANameDA1:	db	"Display Adapter A1, A2 or Plasma Display" ,"$"
Msg_DADetected:	db	" is detected." ,0Dh,0Ah,"$"
Msg_WarnVidmode:	db	"Warning: The current video adapter is VGA. The screen will be corrupt." ,0Dh,0Ah, \
				"If you want to continue, press Y: " ,"$"
Msg_CrLf:	db	0Dh,0Ah,"$"
Msg_ErrFileOpen:
Msg_ErrFileWrite:	db	"Error: Cannot write to PS55FNTJ.BIN" ,0Dh,0Ah, \
				"       This program requires 1024 KB of free drive space." ,0Dh,0Ah ,"$"
Msg_ErrDANotFound:	db	"Error: Unknown or missing Display Adapter." ,0Dh,0Ah,"$"
Msg_Exit0:	db	"Dump completed." ,0Dh,0Ah,"$"
Msg_Exit1:	db	"Program terminated." ,0Dh,0Ah,"$"
Msg_Version:	db	"Font ROM-2 Dump for PS/55 Version 0.05" ,0Dh,0Ah,"$"
METACREDIT:	db	"Copyright (c) 2024 akm.$"

	section .bss
hndl:	resw	1
fontAddrH:	resw	1
bak3E0_8:	resb	1
bankNum:	resb	1
cardNo:	resb	1
isVGADisabled:	resb	1
curVidMode:	resb	1
rdata:	resw	SIZE