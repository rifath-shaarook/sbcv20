;	SBCV20 NASCOM BASIC
;	Assembler: asm86.com/asm86.cmd
;
RAM	equ	0000h	;RAM top
ROM	equ	8000h	;Rom top
STACK	equ	0500h	;Stack top
EMEM	equ	0000h	;Memory top in emulation mode
EMROM	equ	8200h	;Start address in emulation mode
REGAD	equ	00h	;8251 data register
REGAC	equ	01h	;8251 control register
RTSHIG	equ	17h	;RTS high
RTSLOW	equ	37h	;RTS low
;
BUFSIZ	equ	128		;Buffer size(2^n, max128)
FULSIZ	equ	BUFSIZ*14/16	;Buffer almost full
;
;
	dseg
	org	RAM
;
;	Interrupt vector
DEVERR	rw	2	;Devide error
BRKFLG	rw	2	;Break flag
NMIREQ	rw	2	;Non maskable interrupt
BR3INS	rw	2	;BRK3 instruction
BRVINS	rw	2	;BRKV instruction
CHKINS	rw	2	;CHKIND instruction
	org	0400h-20
VGETCH	rw	2	;CALLN 251
VKBHIT	rw	2	;CALLN 252
VPUTCH	rw	2	;CALLN 253
VBRKEM	rw	2	;BRKEM 254
INTREQ	rw	2	;External interrupt
;
;	Receive buffer
RECBUF	rb	BUFSIZ	;Buffer
RBFRDP	rw	1	;Read address
RBFWTP	rw	1	;Write address
RBFCNT	rb	1	;Count of chars
;
	cseg
	org	ROM
;
;	8251 -> buffer by interrupt
;
intsr:	push	ax	;Save ax
	push	bx	;Save bx
	in	al,REGAD	;Get char
	mov	ah,al		;Save it
;
	mov	al,RBFCNT	;Get count of chars
	cmp	al,BUFSIZ	;Buffer full?
	jz	isext		;If yes, ignore
	inc	al		;Count up
	mov	RBFCNT,al	;Update
	cmp	al,FULSIZ	;Buffer almost full?
	jnz	isst1		;If no, skip flow control
	mov	al,RTSHIG	;RTS control
	out	REGAC,al	;Out it
;
isst1:	mov	bx,RBFWTP	;Get write point
	mov	al,ah		;Restore char
	mov	[bx],al		;Write char into buffer
;
	inc	bl		;Next write point
	and	bl,BUFSIZ-1	;Wrap
	mov	RBFWTP,bx	;Update
;
isext:	pop	bx	;Restore bx
	pop	ax	;Restore ax
	sti		;Enable interrupt
	iret
;
;	buffer -> al
getch:	push	bx	;Save bx
;
gcst1:	mov	al,RBFCNT	;Get count of chars
	cmp	al,0		;Buffer enpty?
	jz	gcst1		;If yes, wait
	cli			;Disable interrupt
;
	mov	al,RBFCNT	;Critical timing measures
	cmp	al,FULSIZ	;Need flow control?
	jnz	gcst2		;If no, skip flow control
	mov	ah,al		;Save char
	mov	al,RTSLOW	;RTS control
	out	REGAC,al	;Out it
	mov	al,ah		;Restore char
gcst2:	dec	al		;Count down
	mov	RBFCNT,al	;Update
;
	mov	bx,RBFRDP	;Get read point
	mov	al,[bx]		;Read char from buffer
;
	inc	bl		;Next read point
	and	bl,BUFSIZ-1	;Wrap
	mov	RBFRDP,bx	;Update
;
	pop	bx	;Restore bx
	sti		;Enable interrupt
	ret
;
;	al -> 8251
putch:	push	ax		;Save char
;
pcst1:	in	al,REGAC	;Get status
	and	al,01h		;check TxBUF enpty
	jz	pcst1		;wait for empty
;
	pop	ax		;Restore char
	out	REGAD,al	;Out it
	ret
;
;	put string
puts:	cld			;set DF for SI increment
ptst1:	lodsb			;get data to AL and SI++
	cmp	al,00h		;check tail
	jz	ptext		;if tail, return
	call	putch		;display a charactor
	jmp	ptst1		;loop until tail
ptext:	ret
;
;	message
ckcpu	db	13,10,'PROCESSOR: ',0
nec	db	'NEC V20(uPD70108)',13,10
	db	'It will soon be turned 8080 emulation mode.',13,10,0
intel	db	'Intel 8088',13,10
	db	'Sorry, It will soon be out of control',13,10,0
natv	db	'Returned to native mode.',13,10
	db	'There is no code to run, so please reset.',13,10,0
;
;	CALLN wrapping
ngetch:	call	getch		;Get a char
	iret
nkbhit:	mov	al,RBFCNT	;Get count of char
	iret
nputch:	call	putch		;Put a char
	iret
;
;	Start
start:	mov	ax,cs		;Set com model
	mov	ds,ax		;Overlay ds with cs
	mov	es,ax		;Overlay es with cs
	mov	ss,ax		;Overlay ss with cs
	mov	sp,STACK	;Set stack
;
;	Vector 251-255 setup
	mov	VGETCH,offset ngetch
	mov	VGETCH+2,ax
	mov	VKBHIT,offset nkbhit
	mov	VKBHIT+2,ax
	mov	VPUTCH,offset nputch
	mov	VPUTCH+2,ax
	mov	VBRKEM,EMROM
	mov	VBRKEM+2,ax
	mov	INTREQ,offset intsr
	mov	INTREQ+2,ax
;
;	8251 setup
	mov	dx,REGAC
	mov	al,00h	;Default mode or no operation
	out	dx,al	;Try command
	out	dx,al	;Try command
	out	dx,al	;Try command
	mov	al,40h	;reset
	out	dx,al	;Out it
	mov	CX,16	;Delay
	loop	$	;Delay
	mov	al,4eh	;mode
	out	dx,al	;Out it
	mov	al,37h	;command
	out	dx,al	;Out it
;
;	Buffer initialize
	xor	al,al			;Clear al
	mov	RBFCNT,al		;Set count of chars
	mov	ax,offset RECBUF	;Get buffer top
	mov	RBFRDP,ax		;Set read point
	mov	RBFWTP,ax		;Set write point
;
	sti		;Enable interrupt
;
;	Check CPU
	mov	si,offset ckcpu	;set message top
	call	puts		;display message
;
	mov	ax,0101h
	db	0d5h,10h	;aad 10h
	cmp	al,0bh		;NEC V20 ignores the argument
	je	isv20		;If V20, skip follw 3 step
	mov	si,offset intel	;8088 message
	call	puts		;Out it
	jmps	$		;Stop
isV20:	call	puts		;V20 message
;
;	Emulation sequence
	db	0fh,0ffh	;BRKEM
	db	offset VBRKEM/4	;Vector number
;
;	Returned native mode
	mov	si,offset natv	;8088 message
	call	puts		;Out it
	jmps	$		;Stop
;
;	Emulated 8080 code
;	See MSBASV20.ASM
	org	EMROM
	db	0c3h, 013h, 082h, 0edh, 0edh, 0fbh
	db	0c9h, 0edh, 0edh, 0fdh, 0c9h, 0edh
	db	0edh, 0fch, 0feh, 000h, 0c9h, 0edh
	db	0fdh, 021h, 066h, 005h, 0f9h, 0c3h
	db	01ah, 082h, 0c3h, 020h, 082h, 0c3h
	db	095h, 082h, 0c3h, 027h, 082h, 0ech
	db	08ah, 063h, 092h, 021h, 000h, 005h
	db	0f9h, 0c3h, 08dh, 09eh, 011h, 005h
	db	085h, 006h, 063h, 021h, 000h, 005h
	db	01ah, 077h, 023h, 013h, 005h, 0c2h
	db	036h, 082h, 0f9h, 0cdh, 006h, 087h
	db	0cdh, 0e2h, 08ch, 032h, 0aah, 005h
	db	032h, 0f9h, 005h, 021h, 05dh, 006h
	db	023h, 07ch, 0b5h, 0cah, 05dh, 082h
	db	07eh, 047h, 02fh, 077h, 0beh, 070h
	db	0cah, 04eh, 082h, 02bh, 011h, 05ch
	db	006h, 0cdh, 09ch, 088h, 0dah, 09eh
	db	082h, 011h, 0ceh, 0ffh, 022h, 0afh
	db	005h, 019h, 022h, 05ah, 005h, 0cdh
	db	0e1h, 086h, 02ah, 05ah, 005h, 011h
	db	0efh, 0ffh, 019h, 011h, 0f9h, 005h
	db	07dh, 093h, 06fh, 07ch, 09ah, 067h
	db	0e5h, 021h, 0b6h, 082h, 0cdh, 081h
	db	093h, 0e1h, 0cdh, 026h, 09ah, 021h
	db	0a7h, 082h, 0cdh, 081h, 093h, 031h
	db	066h, 005h, 0cdh, 006h, 087h, 0c3h
	db	01fh, 086h, 021h, 0f3h, 082h, 0cdh
	db	081h, 093h, 0c3h, 0a4h, 082h, 020h
	db	042h, 079h, 074h, 065h, 073h, 020h
	db	066h, 072h, 065h, 065h, 00dh, 00ah
	db	000h, 000h, 049h, 04eh, 054h, 045h
	db	04ch, 038h, 030h, 038h, 030h, 020h
	db	042h, 041h, 053h, 049h, 043h, 020h
	db	056h, 065h, 072h, 020h, 034h, 02eh
	db	037h, 062h, 00dh, 00ah, 043h, 06fh
	db	070h, 079h, 072h, 069h, 067h, 068h
	db	074h, 020h, 028h, 043h, 029h, 020h
	db	031h, 039h, 037h, 038h, 020h, 062h
	db	079h, 020h, 04dh, 069h, 063h, 072h
	db	06fh, 073h, 06fh, 066h, 074h, 00dh
	db	00ah, 000h, 000h, 04dh, 065h, 06dh
	db	06fh, 072h, 079h, 020h, 073h, 069h
	db	07ah, 065h, 020h, 06eh, 06fh, 074h
	db	020h, 065h, 06eh, 06fh, 075h, 067h
	db	068h, 00dh, 00ah, 054h, 068h, 065h
	db	020h, 073h, 079h, 073h, 074h, 065h
	db	06dh, 020h, 069h, 073h, 020h, 073h
	db	074h, 06fh, 070h, 070h, 065h, 064h
	db	02eh, 00dh, 00ah, 000h, 000h, 09bh
	db	098h, 05fh, 099h, 0b1h, 098h, 003h
	db	005h, 041h, 092h, 0c8h, 095h, 06fh
	db	092h, 025h, 09bh, 004h, 09ch, 040h
	db	097h, 073h, 09bh, 079h, 09ch, 07fh
	db	09ch, 0e0h, 09ch, 0f5h, 09ch, 01ch
	db	096h, 060h, 09dh, 051h, 005h, 0f3h
	db	094h, 00bh, 093h, 08dh, 095h, 002h
	db	095h, 013h, 095h, 082h, 09dh, 01fh
	db	09eh, 023h, 095h, 053h, 095h, 05dh
	db	095h, 0c5h, 04eh, 044h, 0c6h, 04fh
	db	052h, 0ceh, 045h, 058h, 054h, 0c4h
	db	041h, 054h, 041h, 0c9h, 04eh, 050h
	db	055h, 054h, 0c4h, 049h, 04dh, 0d2h
	db	045h, 041h, 044h, 0cch, 045h, 054h
	db	0c7h, 04fh, 054h, 04fh, 0d2h, 055h
	db	04eh, 0c9h, 046h, 0d2h, 045h, 053h
	db	054h, 04fh, 052h, 045h, 0c7h, 04fh
	db	053h, 055h, 042h, 0d2h, 045h, 054h
	db	055h, 052h, 04eh, 0d2h, 045h, 04dh
	db	0d3h, 054h, 04fh, 050h, 0cfh, 055h
	db	054h, 0cfh, 04eh, 0ceh, 055h, 04ch
	db	04ch, 0d7h, 041h, 049h, 054h, 0c4h
	db	045h, 046h, 0d0h, 04fh, 04bh, 045h
	db	0c4h, 04fh, 04bh, 045h, 0d3h, 043h
	db	052h, 045h, 045h, 04eh, 0cch, 049h
	db	04eh, 045h, 053h, 0c3h, 04ch, 053h
	db	0d7h, 049h, 044h, 054h, 048h, 0cdh
	db	04fh, 04eh, 049h, 054h, 04fh, 052h
	db	0d3h, 045h, 054h, 0d2h, 045h, 053h
	db	045h, 054h, 0d0h, 052h, 049h, 04eh
	db	054h, 0c3h, 04fh, 04eh, 054h, 0cch
	db	049h, 053h, 054h, 0c3h, 04ch, 045h
	db	041h, 052h, 0c3h, 04ch, 04fh, 041h
	db	044h, 0c3h, 053h, 041h, 056h, 045h
	db	0ceh, 045h, 057h, 0d4h, 041h, 042h
	db	028h, 0d4h, 04fh, 0c6h, 04eh, 0d3h
	db	050h, 043h, 028h, 0d4h, 048h, 045h
	db	04eh, 0ceh, 04fh, 054h, 0d3h, 054h
	db	045h, 050h, 0abh, 0adh, 0aah, 0afh
	db	0deh, 0c1h, 04eh, 044h, 0cfh, 052h
	db	0beh, 0bdh, 0bch, 0d3h, 047h, 04eh
	db	0c9h, 04eh, 054h, 0c1h, 042h, 053h
	db	0d5h, 053h, 052h, 0c6h, 052h, 045h
	db	0c9h, 04eh, 050h, 0d0h, 04fh, 053h
	db	0d3h, 051h, 052h, 0d2h, 04eh, 044h
	db	0cch, 04fh, 047h, 0c5h, 058h, 050h
	db	0c3h, 04fh, 053h, 0d3h, 049h, 04eh
	db	0d4h, 041h, 04eh, 0c1h, 054h, 04eh
	db	0d0h, 045h, 045h, 04bh, 0c4h, 045h
	db	045h, 04bh, 0d0h, 04fh, 049h, 04eh
	db	054h, 0cch, 045h, 04eh, 0d3h, 054h
	db	052h, 024h, 0d6h, 041h, 04ch, 0c1h
	db	053h, 043h, 0c3h, 048h, 052h, 024h
	db	0c8h, 045h, 058h, 024h, 0c2h, 049h
	db	04eh, 024h, 0cch, 045h, 046h, 054h
	db	024h, 0d2h, 049h, 047h, 048h, 054h
	db	024h, 0cdh, 049h, 044h, 024h, 080h
	db	084h, 08ah, 077h, 089h, 05ch, 08eh
	db	0d1h, 08bh, 063h, 08dh, 099h, 090h
	db	092h, 08dh, 0e8h, 08bh, 08eh, 08bh
	db	071h, 08bh, 060h, 08ch, 040h, 08ah
	db	07dh, 08bh, 0ach, 08bh, 0d3h, 08bh
	db	082h, 08ah, 0d4h, 095h, 042h, 08ch
	db	0c3h, 08ah, 0dah, 095h, 077h, 092h
	db	023h, 096h, 06bh, 09dh, 0d3h, 08bh
	db	04fh, 09dh, 042h, 09dh, 047h, 09dh
	db	011h, 082h, 054h, 005h, 057h, 005h
	db	084h, 08ch, 0b0h, 08ah, 0e8h, 088h
	db	02bh, 08bh, 0d3h, 08bh, 0d3h, 08bh
	db	0e0h, 086h, 079h, 00dh, 09ah, 079h
	db	041h, 096h, 07ch, 07fh, 097h, 07ch
	db	0e0h, 097h, 07fh, 02eh, 09bh, 050h
	db	0f2h, 08fh, 046h, 0f1h, 08fh, 04eh
	db	046h, 053h, 04eh, 052h, 047h, 04fh
	db	044h, 046h, 043h, 04fh, 056h, 04fh
	db	04dh, 055h, 04ch, 042h, 053h, 044h
	db	044h, 02fh, 030h, 049h, 044h, 054h
	db	04dh, 04fh, 053h, 04ch, 053h, 053h
	db	054h, 043h, 04eh, 055h, 046h, 04dh
	db	04fh, 048h, 058h, 042h, 04eh, 0c3h
	db	095h, 082h, 0c3h, 001h, 08bh, 0d3h
	db	000h, 0c9h, 0d6h, 000h, 06fh, 07ch
	db	0deh, 000h, 067h, 078h, 0deh, 000h
	db	047h, 03eh, 000h, 0c9h, 000h, 000h
	db	000h, 035h, 04ah, 0cah, 099h, 039h
	db	01ch, 076h, 098h, 022h, 095h, 0b3h
	db	098h, 00ah, 0ddh, 047h, 098h, 053h
	db	0d1h, 099h, 099h, 00ah, 01ah, 09fh
	db	098h, 065h, 0bch, 0cdh, 098h, 0d6h
	db	077h, 03eh, 098h, 052h, 0c7h, 04fh
	db	080h, 0dbh, 000h, 0c9h, 001h, 0ffh
	db	01ch, 000h, 000h, 014h, 000h, 014h
	db	000h, 000h, 000h, 000h, 000h, 0c3h
	db	019h, 088h, 0c3h, 000h, 000h, 0c3h
	db	000h, 000h, 0c3h, 000h, 000h, 05dh
	db	006h, 0feh, 0ffh, 0fah, 005h, 020h
	db	045h, 072h, 072h, 06fh, 072h, 000h
	db	020h, 069h, 06eh, 020h, 000h, 04fh
	db	06bh, 00dh, 00ah, 000h, 000h, 042h
	db	072h, 065h, 061h, 06bh, 000h, 021h
	db	004h, 000h, 039h, 07eh, 023h, 0feh
	db	081h, 0c0h, 04eh, 023h, 046h, 023h
	db	0e5h, 069h, 060h, 07ah, 0b3h, 0ebh
	db	0cah, 097h, 085h, 0ebh, 0cdh, 09ch
	db	088h, 001h, 00dh, 000h, 0e1h, 0c8h
	db	009h, 0c3h, 081h, 085h, 0cdh, 0bah
	db	085h, 0c5h, 0e3h, 0c1h, 0cdh, 09ch
	db	088h, 07eh, 002h, 0c8h, 00bh, 02bh
	db	0c3h, 0a6h, 085h, 0e5h, 02ah, 0dah
	db	005h, 006h, 000h, 009h, 009h, 03eh
	db	0e5h, 03eh, 0d0h, 095h, 06fh, 03eh
	db	0ffh, 09ch, 0dah, 0c9h, 085h, 067h
	db	039h, 0e1h, 0d8h, 01eh, 00ch, 0c3h
	db	0e8h, 085h, 02ah, 0c9h, 005h, 022h
	db	05ch, 005h, 01eh, 002h, 001h, 01eh
	db	014h, 001h, 01eh, 000h, 001h, 01eh
	db	012h, 001h, 01eh, 022h, 001h, 01eh
	db	00ah, 001h, 01eh, 018h, 0cdh, 006h
	db	087h, 032h, 045h, 005h, 0cdh, 0d5h
	db	08ch, 021h, 0dbh, 084h, 057h, 03eh
	db	03fh, 0cdh, 0adh, 088h, 019h, 07eh
	db	0cdh, 0adh, 088h, 0cdh, 030h, 08ah
	db	0cdh, 0adh, 088h, 021h, 065h, 085h
	db	0cdh, 081h, 093h, 02ah, 05ch, 005h
	db	011h, 0feh, 0ffh, 0cdh, 09ch, 088h
	db	0cah, 027h, 082h, 07ch, 0a5h, 03ch
	db	0c4h, 01eh, 09ah, 03eh, 0c1h, 0afh
	db	032h, 045h, 005h, 0cdh, 0d5h, 08ch
	db	021h, 071h, 085h, 0cdh, 081h, 093h
	db	021h, 0ffh, 0ffh, 022h, 05ch, 005h
	db	0cdh, 019h, 088h, 0dah, 02ch, 086h
	db	0cdh, 030h, 08ah, 03ch, 03dh, 0cah
	db	02ch, 086h, 0f5h, 0cdh, 006h, 08bh
	db	0d5h, 0cdh, 030h, 087h, 047h, 0d1h
	db	0f1h, 0d2h, 010h, 08ah, 0d5h, 0c5h
	db	0afh, 032h, 0cch, 005h, 0cdh, 030h
	db	08ah, 0b7h, 0f5h, 0cdh, 0c0h, 086h
	db	0dah, 065h, 086h, 0f1h, 0f5h, 0cah
	db	0a7h, 08bh, 0b7h, 0c5h, 0d2h, 07ch
	db	086h, 0ebh, 02ah, 0d6h, 005h, 01ah
	db	002h, 003h, 013h, 0cdh, 09ch, 088h
	db	0c2h, 06dh, 086h, 060h, 069h, 022h
	db	0d6h, 005h, 0d1h, 0f1h, 0cah, 0a3h
	db	086h, 02ah, 0d6h, 005h, 0e3h, 0c1h
	db	009h, 0e5h, 0cdh, 0a0h, 085h, 0e1h
	db	022h, 0d6h, 005h, 0ebh, 074h, 0d1h
	db	023h, 023h, 073h, 023h, 072h, 023h
	db	011h, 061h, 005h, 01ah, 077h, 023h
	db	013h, 0b7h, 0c2h, 09bh, 086h, 0cdh
	db	0ech, 086h, 023h, 0ebh, 062h, 06bh
	db	07eh, 023h, 0b6h, 0cah, 02ch, 086h
	db	023h, 023h, 023h, 0afh, 0beh, 023h
	db	0c2h, 0b4h, 086h, 0ebh, 073h, 023h
	db	072h, 0c3h, 0a8h, 086h, 02ah, 05eh
	db	005h, 044h, 04dh, 07eh, 023h, 0b6h
	db	02bh, 0c8h, 023h, 023h, 07eh, 023h
	db	066h, 06fh, 0cdh, 09ch, 088h, 060h
	db	069h, 07eh, 023h, 066h, 06fh, 03fh
	db	0c8h, 03fh, 0d0h, 0c3h, 0c3h, 086h
	db	0c0h, 02ah, 05eh, 005h, 0afh, 077h
	db	023h, 077h, 023h, 022h, 0d6h, 005h
	db	02ah, 05eh, 005h, 02bh, 022h, 0ceh
	db	005h, 02ah, 0afh, 005h, 022h, 0c3h
	db	005h, 0afh, 0cdh, 040h, 08ah, 02ah
	db	0d6h, 005h, 022h, 0d8h, 005h, 022h
	db	0dah, 005h, 0c1h, 02ah, 05ah, 005h
	db	0f9h, 021h, 0b3h, 005h, 022h, 0b1h
	db	005h, 0afh, 06fh, 067h, 022h, 0d4h
	db	005h, 032h, 0cbh, 005h, 022h, 0deh
	db	005h, 0e5h, 0c5h, 02ah, 0ceh, 005h
	db	0c9h, 03eh, 03fh, 0cdh, 0adh, 088h
	db	03eh, 020h, 0cdh, 0adh, 088h, 0c3h
	db	04eh, 005h, 0afh, 032h, 0aeh, 005h
	db	00eh, 005h, 011h, 061h, 005h, 07eh
	db	0feh, 020h, 0cah, 0b8h, 087h, 047h
	db	0feh, 022h, 0cah, 0d8h, 087h, 0b7h
	db	0cah, 0dfh, 087h, 03ah, 0aeh, 005h
	db	0b7h, 07eh, 0c2h, 0b8h, 087h, 0feh
	db	03fh, 03eh, 09eh, 0cah, 0b8h, 087h
	db	07eh, 0feh, 030h, 0dah, 063h, 087h
	db	0feh, 03ch, 0dah, 0b8h, 087h, 0d5h
	db	011h, 05ch, 083h, 0c5h, 001h, 0b4h
	db	087h, 0c5h, 006h, 07fh, 07eh, 0feh
	db	061h, 0dah, 07ch, 087h, 0feh, 07bh
	db	0d2h, 07ch, 087h, 0e6h, 05fh, 077h
	db	04eh, 0ebh, 023h, 0b6h, 0f2h, 07eh
	db	087h, 004h, 07eh, 0e6h, 07fh, 0c8h
	db	0b9h, 0c2h, 07eh, 087h, 0ebh, 0e5h
	db	013h, 01ah, 0b7h, 0fah, 0b0h, 087h
	db	04fh, 078h, 0feh, 088h, 0c2h, 09fh
	db	087h, 0cdh, 030h, 08ah, 02bh, 023h
	db	07eh, 0feh, 061h, 0dah, 0a8h, 087h
	db	0e6h, 05fh, 0b9h, 0cah, 08eh, 087h
	db	0e1h, 0c3h, 07ch, 087h, 048h, 0f1h
	db	0ebh, 0c9h, 0ebh, 079h, 0c1h, 0d1h
	db	023h, 012h, 013h, 00ch, 0d6h, 03ah
	db	0cah, 0c6h, 087h, 0feh, 049h, 0c2h
	db	0c9h, 087h, 032h, 0aeh, 005h, 0d6h
	db	054h, 0c2h, 039h, 087h, 047h, 07eh
	db	0b7h, 0cah, 0dfh, 087h, 0b8h, 0cah
	db	0b8h, 087h, 023h, 012h, 00ch, 013h
	db	0c3h, 0cfh, 087h, 021h, 060h, 005h
	db	012h, 013h, 012h, 013h, 012h, 0c9h
	db	03ah, 044h, 005h, 0b7h, 03eh, 000h
	db	032h, 044h, 005h, 0c2h, 0fch, 087h
	db	005h, 0cah, 019h, 088h, 0cdh, 0adh
	db	088h, 03eh, 005h, 02bh, 0cah, 010h
	db	088h, 07eh, 0cdh, 0adh, 088h, 0c3h
	db	022h, 088h, 005h, 02bh, 0cdh, 0adh
	db	088h, 0c2h, 022h, 088h, 0cdh, 0adh
	db	088h, 0cdh, 0e2h, 08ch, 0c3h, 019h
	db	088h, 021h, 061h, 005h, 006h, 001h
	db	0afh, 032h, 044h, 005h, 0cdh, 0d7h
	db	088h, 04fh, 0feh, 07fh, 0cah, 0e8h
	db	087h, 03ah, 044h, 005h, 0b7h, 0cah
	db	03bh, 088h, 03eh, 000h, 0cdh, 0adh
	db	088h, 0afh, 032h, 044h, 005h, 079h
	db	0feh, 007h, 0cah, 07fh, 088h, 0feh
	db	003h, 0cch, 0e2h, 08ch, 037h, 0c8h
	db	0feh, 00dh, 0cah, 0ddh, 08ch, 0feh
	db	015h, 0cah, 013h, 088h, 0feh, 040h
	db	0cah, 010h, 088h, 0feh, 05fh, 0cah
	db	008h, 088h, 0feh, 008h, 0cah, 008h
	db	088h, 0feh, 012h, 0c2h, 07ah, 088h
	db	0c5h, 0d5h, 0e5h, 036h, 000h, 0cdh
	db	09ch, 09eh, 021h, 061h, 005h, 0cdh
	db	081h, 093h, 0e1h, 0d1h, 0c1h, 0c3h
	db	022h, 088h, 0feh, 020h, 0dah, 022h
	db	088h, 078h, 0feh, 049h, 03eh, 007h
	db	0d2h, 094h, 088h, 079h, 071h, 032h
	db	0cch, 005h, 023h, 004h, 0cdh, 0adh
	db	088h, 0c3h, 022h, 088h, 0cdh, 0adh
	db	088h, 03eh, 008h, 0c3h, 08eh, 088h
	db	07ch, 092h, 0c0h, 07dh, 093h, 0c9h
	db	07eh, 0e3h, 0beh, 023h, 0e3h, 0cah
	db	030h, 08ah, 0c3h, 0d4h, 085h, 0f5h
	db	03ah, 045h, 005h, 0b7h, 0c2h, 0b6h
	db	093h, 0f1h, 0c5h, 0f5h, 0feh, 020h
	db	0dah, 0d1h, 088h, 03ah, 042h, 005h
	db	047h, 03ah, 0abh, 005h, 004h, 0cah
	db	0cdh, 088h, 005h, 0b8h, 0cch, 0e2h
	db	08ch, 03ch, 032h, 0abh, 005h, 0f1h
	db	0c1h, 0cdh, 007h, 082h, 0c9h, 0cdh
	db	003h, 082h, 0e6h, 07fh, 0feh, 00fh
	db	0c0h, 03ah, 045h, 005h, 02fh, 032h
	db	045h, 005h, 0afh, 0c9h, 0cdh, 006h
	db	08bh, 0c0h, 0c1h, 0cdh, 0c0h, 086h
	db	0c5h, 0cdh, 03eh, 089h, 0e1h, 04eh
	db	023h, 046h, 023h, 078h, 0b1h, 0cah
	db	01fh, 086h, 0cdh, 047h, 089h, 0cdh
	db	05bh, 08ah, 0c5h, 0cdh, 0e2h, 08ch
	db	05eh, 023h, 056h, 023h, 0e5h, 0ebh
	db	0cdh, 026h, 09ah, 03eh, 020h, 0e1h
	db	0cdh, 0adh, 088h, 07eh, 0b7h, 023h
	db	0cah, 0f4h, 088h, 0f2h, 014h, 089h
	db	0d6h, 07fh, 04fh, 011h, 05dh, 083h
	db	01ah, 013h, 0b7h, 0f2h, 026h, 089h
	db	00dh, 0c2h, 026h, 089h, 0e6h, 07fh
	db	0cdh, 0adh, 088h, 01ah, 013h, 0b7h
	db	0f2h, 030h, 089h, 0c3h, 017h, 089h
	db	0e5h, 02ah, 048h, 005h, 022h, 046h
	db	005h, 0e1h, 0c9h, 0e5h, 0d5h, 02ah
	db	046h, 005h, 011h, 0ffh, 0ffh, 07bh
	db	08dh, 06fh, 07ah, 08ch, 067h, 022h
	db	046h, 005h, 0d1h, 0e1h, 0f0h, 0e5h
	db	02ah, 048h, 005h, 022h, 046h, 005h
	db	0cdh, 003h, 082h, 0feh, 003h, 0cah
	db	06eh, 089h, 0e1h, 0c3h, 047h, 089h
	db	02ah, 048h, 005h, 022h, 046h, 005h
	db	0c3h, 098h, 082h, 03eh, 064h, 032h
	db	0cbh, 005h, 0cdh, 0e8h, 08bh, 0c1h
	db	0e5h, 0cdh, 0d1h, 08bh, 022h, 0c7h
	db	005h, 021h, 002h, 000h, 039h, 0cdh
	db	081h, 085h, 0d1h, 0c2h, 0a7h, 089h
	db	009h, 0d5h, 02bh, 056h, 02bh, 05eh
	db	023h, 023h, 0e5h, 02ah, 0c7h, 005h
	db	0cdh, 09ch, 088h, 0e1h, 0c2h, 08bh
	db	089h, 0d1h, 0f9h, 0ebh, 00eh, 008h
	db	0cdh, 0b1h, 085h, 0e5h, 02ah, 0c7h
	db	005h, 0e3h, 0e5h, 02ah, 05ch, 005h
	db	0e3h, 0cdh, 0aah, 08eh, 0cdh, 0a2h
	db	088h, 0a6h, 0cdh, 0a7h, 08eh, 0e5h
	db	0cdh, 0d8h, 098h, 0e1h, 0c5h, 0d5h
	db	001h, 000h, 081h, 051h, 05ah, 07eh
	db	0feh, 0abh, 03eh, 001h, 0c2h, 0e3h
	db	089h, 0cdh, 030h, 08ah, 0cdh, 0a7h
	db	08eh, 0e5h, 0cdh, 0d8h, 098h, 0cdh
	db	08ch, 098h, 0e1h, 0c5h, 0d5h, 0f5h
	db	033h, 0e5h, 02ah, 0ceh, 005h, 0e3h
	db	006h, 081h, 0c5h, 033h, 0cdh, 05bh
	db	08ah, 022h, 0ceh, 005h, 07eh, 0feh
	db	03ah, 0cah, 010h, 08ah, 0b7h, 0c2h
	db	0d4h, 085h, 023h, 07eh, 023h, 0b6h
	db	0cah, 08ch, 08ah, 023h, 05eh, 023h
	db	056h, 0ebh, 022h, 05ch, 005h, 0ebh
	db	0cdh, 030h, 08ah, 011h, 0f0h, 089h
	db	0d5h, 0c8h, 0d6h, 080h, 0dah, 0e8h
	db	08bh, 0feh, 025h, 0d2h, 0d4h, 085h
	db	007h, 04fh, 006h, 000h, 0ebh, 021h
	db	07ch, 084h, 009h, 04eh, 023h, 046h
	db	0c5h, 0ebh, 023h, 07eh, 0feh, 03ah
	db	0d0h, 0feh, 020h, 0cah, 030h, 08ah
	db	0feh, 030h, 03fh, 03ch, 03dh, 0c9h
	db	0ebh, 02ah, 05eh, 005h, 0cah, 055h
	db	08ah, 0ebh, 0cdh, 006h, 08bh, 0e5h
	db	0cdh, 0c0h, 086h, 060h, 069h, 0d1h
	db	0d2h, 0a7h, 08bh, 02bh, 022h, 0dch
	db	005h, 0ebh, 0c9h, 0cdh, 00bh, 082h
	db	0c8h, 0cdh, 003h, 082h, 0feh, 01bh
	db	0cah, 07dh, 08ah, 0feh, 003h, 0cah
	db	07dh, 08ah, 0feh, 013h, 0c0h, 0cdh
	db	003h, 082h, 0feh, 011h, 0c8h, 0feh
	db	003h, 0cah, 082h, 08ah, 0c3h, 06fh
	db	08ah, 03eh, 0ffh, 032h, 04dh, 005h
	db	0c0h, 0f6h, 0c0h, 022h, 0ceh, 005h
	db	021h, 0f6h, 0ffh, 0c1h, 02ah, 05ch
	db	005h, 0f5h, 07dh, 0a4h, 03ch, 0cah
	db	09fh, 08ah, 022h, 0d2h, 005h, 02ah
	db	0ceh, 005h, 022h, 0d4h, 005h, 0afh
	db	032h, 045h, 005h, 0cdh, 0d5h, 08ch
	db	0f1h, 021h, 077h, 085h, 0c2h, 008h
	db	086h, 0c3h, 01fh, 086h, 02ah, 0d4h
	db	005h, 07ch, 0b5h, 01eh, 020h, 0cah
	db	0e8h, 085h, 0ebh, 02ah, 0d2h, 005h
	db	022h, 05ch, 005h, 0ebh, 0c9h, 0cdh
	db	00bh, 096h, 0c0h, 032h, 041h, 005h
	db	0c9h, 0e5h, 02ah, 04ah, 005h, 006h
	db	000h, 04fh, 009h, 022h, 04ah, 005h
	db	0e1h, 0c9h, 07eh, 0feh, 041h, 0d8h
	db	0feh, 05bh, 03fh, 0c9h, 0cdh, 030h
	db	08ah, 0cdh, 0a7h, 08eh, 0cdh, 08ch
	db	098h, 0fah, 001h, 08bh, 03ah, 0e7h
	db	005h, 0feh, 090h, 0dah, 034h, 099h
	db	001h, 080h, 090h, 011h, 000h, 000h
	db	0e5h, 0cdh, 007h, 099h, 0e1h, 051h
	db	0c8h, 01eh, 008h, 0c3h, 0e8h, 085h
	db	02bh, 011h, 000h, 000h, 0cdh, 030h
	db	08ah, 0d0h, 0e5h, 0f5h, 021h, 098h
	db	019h, 0cdh, 09ch, 088h, 0dah, 0d4h
	db	085h, 062h, 06bh, 019h, 029h, 019h
	db	029h, 0f1h, 0d6h, 030h, 05fh, 016h
	db	000h, 019h, 0ebh, 0e1h, 0c3h, 00ah
	db	08bh, 0cah, 0f0h, 086h, 0cdh, 0e3h
	db	08ah, 02bh, 0cdh, 030h, 08ah, 0e5h
	db	02ah, 0afh, 005h, 0cah, 04eh, 08bh
	db	0e1h, 0cdh, 0a2h, 088h, 02ch, 0d5h
	db	0cdh, 0e3h, 08ah, 02bh, 0cdh, 030h
	db	08ah, 0c2h, 0d4h, 085h, 0e3h, 0ebh
	db	07dh, 093h, 05fh, 07ch, 09ah, 057h
	db	0dah, 0c9h, 085h, 0e5h, 02ah, 0d6h
	db	005h, 001h, 028h, 000h, 009h, 0cdh
	db	09ch, 088h, 0d2h, 0c9h, 085h, 0ebh
	db	022h, 05ah, 005h, 0e1h, 022h, 0afh
	db	005h, 0e1h, 0c3h, 0f0h, 086h, 0cah
	db	0ech, 086h, 0cdh, 0f0h, 086h, 001h
	db	0f0h, 089h, 0c3h, 08dh, 08bh, 00eh
	db	003h, 0cdh, 0b1h, 085h, 0c1h, 0e5h
	db	0e5h, 02ah, 05ch, 005h, 0e3h, 03eh
	db	08ch, 0f5h, 033h, 0c5h, 0cdh, 006h
	db	08bh, 0cdh, 0d3h, 08bh, 0e5h, 02ah
	db	05ch, 005h, 0cdh, 09ch, 088h, 0e1h
	db	023h, 0dch, 0c3h, 086h, 0d4h, 0c0h
	db	086h, 060h, 069h, 02bh, 0d8h, 01eh
	db	00eh, 0c3h, 0e8h, 085h, 0c0h, 016h
	db	0ffh, 0cdh, 07dh, 085h, 0f9h, 0feh
	db	08ch, 01eh, 004h, 0c2h, 0e8h, 085h
	db	0e1h, 022h, 05ch, 005h, 023h, 07ch
	db	0b5h, 0c2h, 0cbh, 08bh, 03ah, 0cch
	db	005h, 0b7h, 0c2h, 01eh, 086h, 021h
	db	0f0h, 089h, 0e3h, 03eh, 0e1h, 001h
	db	03ah, 00eh, 000h, 006h, 000h, 079h
	db	048h, 047h, 07eh, 0b7h, 0c8h, 0b8h
	db	0c8h, 023h, 0feh, 022h, 0cah, 0d7h
	db	08bh, 0c3h, 0dah, 08bh, 0cdh, 09eh
	db	090h, 0cdh, 0a2h, 088h, 0b4h, 0d5h
	db	03ah, 0adh, 005h, 0f5h, 0cdh, 0b9h
	db	08eh, 0f1h, 0e3h, 022h, 0ceh, 005h
	db	01fh, 0cdh, 0ach, 08eh, 0cah, 03bh
	db	08ch, 0e5h, 02ah, 0e4h, 005h, 0e5h
	db	023h, 023h, 05eh, 023h, 056h, 02ah
	db	05eh, 005h, 0cdh, 09ch, 088h, 0d2h
	db	02ah, 08ch, 02ah, 05ah, 005h, 0cdh
	db	09ch, 088h, 0d1h, 0d2h, 032h, 08ch
	db	021h, 0bfh, 005h, 0cdh, 09ch, 088h
	db	0d2h, 032h, 08ch, 03eh, 0d1h, 0cdh
	db	0e2h, 094h, 0ebh, 0cdh, 01bh, 093h
	db	0cdh, 0e2h, 094h, 0e1h, 0cdh, 0e7h
	db	098h, 0e1h, 0c9h, 0e5h, 0cdh, 0e4h
	db	098h, 0d1h, 0e1h, 0c9h, 0cdh, 00bh
	db	096h, 07eh, 047h, 0feh, 08ch, 0cah
	db	051h, 08ch, 0cdh, 0a2h, 088h, 088h
	db	02bh, 04bh, 00dh, 078h, 0cah, 018h
	db	08ah, 0cdh, 007h, 08bh, 0feh, 02ch
	db	0c0h, 0c3h, 052h, 08ch, 0cdh, 0b9h
	db	08eh, 07eh, 0feh, 088h, 0cah, 06eh
	db	08ch, 0cdh, 0a2h, 088h, 0a9h, 02bh
	db	0cdh, 0aah, 08eh, 0cdh, 08ch, 098h
	db	0cah, 0d3h, 08bh, 0cdh, 030h, 08ah
	db	0dah, 08eh, 08bh, 0c3h, 017h, 08ah
	db	02bh, 0cdh, 030h, 08ah, 0cah, 0e2h
	db	08ch, 0c8h, 0feh, 0a5h, 0cah, 015h
	db	08dh, 0feh, 0a8h, 0cah, 015h, 08dh
	db	0e5h, 0feh, 02ch, 0cah, 0feh, 08ch
	db	0feh, 03bh, 0cah, 038h, 08dh, 0c1h
	db	0cdh, 0b9h, 08eh, 0e5h, 03ah, 0adh
	db	005h, 0b7h, 0c2h, 0ceh, 08ch, 0cdh
	db	031h, 09ah, 0cdh, 03fh, 093h, 036h
	db	020h, 02ah, 0e4h, 005h, 034h, 02ah
	db	0e4h, 005h, 03ah, 042h, 005h, 047h
	db	004h, 0cah, 0cah, 08ch, 004h, 03ah
	db	0abh, 005h, 086h, 03dh, 0b8h, 0d4h
	db	0e2h, 08ch, 0cdh, 084h, 093h, 0afh
	db	0c4h, 084h, 093h, 0e1h, 0c3h, 080h
	db	08ch, 03ah, 0abh, 005h, 0b7h, 0c8h
	db	0c3h, 0e2h, 08ch, 036h, 000h, 021h
	db	060h, 005h, 03eh, 00dh, 0cdh, 0adh
	db	088h, 03eh, 00ah, 0cdh, 0adh, 088h
	db	0afh, 032h, 0abh, 005h, 03ah, 041h
	db	005h, 03dh, 0c8h, 0f5h, 0afh, 0cdh
	db	0adh, 088h, 0f1h, 0c3h, 0f3h, 08ch
	db	03ah, 043h, 005h, 047h, 03ah, 0abh
	db	005h, 0b8h, 0d4h, 0e2h, 08ch, 0d2h
	db	038h, 08dh, 0d6h, 00eh, 0d2h, 00ch
	db	08dh, 02fh, 0c3h, 02dh, 08dh, 0f5h
	db	0cdh, 008h, 096h, 0cdh, 0a2h, 088h
	db	029h, 02bh, 0f1h, 0d6h, 0a8h, 0e5h
	db	0cah, 028h, 08dh, 03ah, 0abh, 005h
	db	02fh, 083h, 0d2h, 038h, 08dh, 03ch
	db	047h, 03eh, 020h, 0cdh, 0adh, 088h
	db	005h, 0c2h, 031h, 08dh, 0e1h, 0cdh
	db	030h, 08ah, 0c3h, 087h, 08ch, 03fh
	db	052h, 065h, 064h, 06fh, 020h, 066h
	db	072h, 06fh, 06dh, 020h, 073h, 074h
	db	061h, 072h, 074h, 00dh, 00ah, 000h
	db	03ah, 0cdh, 005h, 0b7h, 0c2h, 0ceh
	db	085h, 0c1h, 021h, 03fh, 08dh, 0cdh
	db	081h, 093h, 0c3h, 01fh, 087h, 0cdh
	db	0ech, 092h, 07eh, 0feh, 022h, 03eh
	db	000h, 032h, 045h, 005h, 0c2h, 07dh
	db	08dh, 0cdh, 040h, 093h, 0cdh, 0a2h
	db	088h, 03bh, 0e5h, 0cdh, 084h, 093h
	db	03eh, 0e5h, 0cdh, 023h, 087h, 0c1h
	db	0dah, 089h, 08ah, 023h, 07eh, 0b7h
	db	02bh, 0c5h, 0cah, 0d0h, 08bh, 036h
	db	02ch, 0c3h, 097h, 08dh, 0e5h, 02ah
	db	0dch, 005h, 0f6h, 0afh, 032h, 0cdh
	db	005h, 0e3h, 0c3h, 0a3h, 08dh, 0cdh
	db	0a2h, 088h, 02ch, 0cdh, 09eh, 090h
	db	0e3h, 0d5h, 07eh, 0feh, 02ch, 0cah
	db	0cbh, 08dh, 03ah, 0cdh, 005h, 0b7h
	db	0c2h, 038h, 08eh, 03eh, 03fh, 0cdh
	db	0adh, 088h, 0cdh, 023h, 087h, 0d1h
	db	0c1h, 0dah, 089h, 08ah, 023h, 07eh
	db	0b7h, 02bh, 0c5h, 0cah, 0d0h, 08bh
	db	0d5h, 03ah, 0adh, 005h, 0b7h, 0cah
	db	0f5h, 08dh, 0cdh, 030h, 08ah, 057h
	db	047h, 0feh, 022h, 0cah, 0e9h, 08dh
	db	03ah, 0cdh, 005h, 0b7h, 057h, 0cah
	db	0e6h, 08dh, 016h, 03ah, 006h, 02ch
	db	02bh, 0cdh, 043h, 093h, 0ebh, 021h
	db	000h, 08eh, 0e3h, 0d5h, 0c3h, 003h
	db	08ch, 0cdh, 030h, 08ah, 0cdh, 093h
	db	099h, 0e3h, 0cdh, 0e4h, 098h, 0e1h
	db	02bh, 0cdh, 030h, 08ah, 0cah, 00ch
	db	08eh, 0feh, 02ch, 0c2h, 052h, 08dh
	db	0e3h, 02bh, 0cdh, 030h, 08ah, 0c2h
	db	09fh, 08dh, 0d1h, 03ah, 0cdh, 005h
	db	0b7h, 0ebh, 0c2h, 056h, 08ah, 0d5h
	db	0b6h, 021h, 027h, 08eh, 0c4h, 081h
	db	093h, 0e1h, 0c9h, 03fh, 045h, 078h
	db	074h, 072h, 061h, 020h, 069h, 067h
	db	06eh, 06fh, 072h, 065h, 064h, 00dh
	db	00ah, 000h, 0cdh, 0d1h, 08bh, 0b7h
	db	0c2h, 051h, 08eh, 023h, 07eh, 023h
	db	0b6h, 01eh, 006h, 0cah, 0e8h, 085h
	db	023h, 05eh, 023h, 056h, 0ebh, 022h
	db	0c9h, 005h, 0ebh, 0cdh, 030h, 08ah
	db	0feh, 083h, 0c2h, 038h, 08eh, 0c3h
	db	0cbh, 08dh, 011h, 000h, 000h, 0c4h
	db	09eh, 090h, 022h, 0ceh, 005h, 0cdh
	db	07dh, 085h, 0c2h, 0dah, 085h, 0f9h
	db	0d5h, 07eh, 023h, 0f5h, 0d5h, 0cdh
	db	0cah, 098h, 0e3h, 0e5h, 0cdh, 037h
	db	096h, 0e1h, 0cdh, 0e4h, 098h, 0e1h
	db	0cdh, 0dbh, 098h, 0e5h, 0cdh, 007h
	db	099h, 0e1h, 0c1h, 090h, 0cdh, 0dbh
	db	098h, 0cah, 097h, 08eh, 0ebh, 022h
	db	05ch, 005h, 069h, 060h, 0c3h, 0ech
	db	089h, 0f9h, 02ah, 0ceh, 005h, 07eh
	db	0feh, 02ch, 0c2h, 0f0h, 089h, 0cdh
	db	030h, 08ah, 0cdh, 05fh, 08eh, 0cdh
	db	0b9h, 08eh, 0f6h, 037h, 03ah, 0adh
	db	005h, 08fh, 0b7h, 0e8h, 0c3h, 0e6h
	db	085h, 0cdh, 0a2h, 088h, 028h, 02bh
	db	016h, 000h, 0d5h, 00eh, 001h, 0cdh
	db	0b1h, 085h, 0cdh, 030h, 08fh, 022h
	db	0d0h, 005h, 02ah, 0d0h, 005h, 0c1h
	db	078h, 0feh, 078h, 0d4h, 0aah, 08eh
	db	07eh, 016h, 000h, 0d6h, 0b3h, 0dah
	db	0f1h, 08eh, 0feh, 003h, 0d2h, 0f1h
	db	08eh, 0feh, 001h, 017h, 0aah, 0bah
	db	057h, 0dah, 0d4h, 085h, 022h, 0c5h
	db	005h, 0cdh, 030h, 08ah, 0c3h, 0d5h
	db	08eh, 07ah, 0b7h, 0c2h, 019h, 090h
	db	07eh, 022h, 0c5h, 005h, 0d6h, 0ach
	db	0d8h, 0feh, 007h, 0d0h, 05fh, 03ah
	db	0adh, 005h, 03dh, 0b3h, 07bh, 0cah
	db	077h, 094h, 007h, 083h, 05fh, 021h
	db	0c6h, 084h, 019h, 078h, 056h, 0bah
	db	0d0h, 023h, 0cdh, 0aah, 08eh, 0c5h
	db	001h, 0c8h, 08eh, 0c5h, 043h, 04ah
	db	0cdh, 0bdh, 098h, 058h, 051h, 04eh
	db	023h, 046h, 023h, 0c5h, 02ah, 0c5h
	db	005h, 0c3h, 0bch, 08eh, 0afh, 032h
	db	0adh, 005h, 0cdh, 030h, 08ah, 01eh
	db	024h, 0cah, 0e8h, 085h, 0dah, 093h
	db	099h, 0cdh, 0d8h, 08ah, 0d2h, 098h
	db	08fh, 0feh, 026h, 0c2h, 05ch, 08fh
	db	0cdh, 030h, 08ah, 0feh, 048h, 0cah
	db	0ddh, 09dh, 0feh, 042h, 0cah, 059h
	db	09eh, 01eh, 002h, 0cah, 0e8h, 085h
	db	0feh, 0ach, 0cah, 030h, 08fh, 0feh
	db	02eh, 0cah, 093h, 099h, 0feh, 0adh
	db	0cah, 087h, 08fh, 0feh, 022h, 0cah
	db	040h, 093h, 0feh, 0aah, 0cah, 079h
	db	090h, 0feh, 0a7h, 0cah, 0a4h, 092h
	db	0d6h, 0b6h, 0d2h, 0a9h, 08fh, 0cdh
	db	0b5h, 08eh, 0cdh, 0a2h, 088h, 029h
	db	0c9h, 016h, 07dh, 0cdh, 0bch, 08eh
	db	02ah, 0d0h, 005h, 0e5h, 0cdh, 0b5h
	db	098h, 0cdh, 0aah, 08eh, 0e1h, 0c9h
	db	0cdh, 09eh, 090h, 0e5h, 0ebh, 022h
	db	0e4h, 005h, 03ah, 0adh, 005h, 0b7h
	db	0cch, 0cah, 098h, 0e1h, 0c9h, 006h
	db	000h, 007h, 04fh, 0c5h, 0cdh, 030h
	db	08ah, 079h, 0feh, 031h, 0dah, 0d0h
	db	08fh, 0cdh, 0b5h, 08eh, 0cdh, 0a2h
	db	088h, 02ch, 0cdh, 0abh, 08eh, 0ebh
	db	02ah, 0e4h, 005h, 0e3h, 0e5h, 0ebh
	db	0cdh, 00bh, 096h, 0ebh, 0e3h, 0c3h
	db	0d8h, 08fh, 0cdh, 07fh, 08fh, 0e3h
	db	011h, 093h, 08fh, 0d5h, 001h, 025h
	db	083h, 009h, 04eh, 023h, 066h, 069h
	db	0e9h, 015h, 0feh, 0adh, 0c8h, 0feh
	db	02dh, 0c8h, 014h, 0feh, 02bh, 0c8h
	db	0feh, 0ach, 0c8h, 02bh, 0c9h, 0f6h
	db	0afh, 0f5h, 0cdh, 0aah, 08eh, 0cdh
	db	0ech, 08ah, 0f1h, 0ebh, 0c1h, 0e3h
	db	0ebh, 0cdh, 0cdh, 098h, 0f5h, 0cdh
	db	0ech, 08ah, 0f1h, 0c1h, 079h, 021h
	db	062h, 092h, 0c2h, 014h, 090h, 0a3h
	db	04fh, 078h, 0a2h, 0e9h, 0b3h, 04fh
	db	078h, 0b2h, 0e9h, 021h, 02bh, 090h
	db	03ah, 0adh, 005h, 01fh, 07ah, 017h
	db	05fh, 016h, 064h, 078h, 0bah, 0d0h
	db	0c3h, 019h, 08fh, 02dh, 090h, 079h
	db	0b7h, 01fh, 0c1h, 0d1h, 0f5h, 0cdh
	db	0ach, 08eh, 021h, 06fh, 090h, 0e5h
	db	0cah, 007h, 099h, 0afh, 032h, 0adh
	db	005h, 0d5h, 0cdh, 0c4h, 094h, 07eh
	db	023h, 023h, 04eh, 023h, 046h, 0d1h
	db	0c5h, 0f5h, 0cdh, 0c8h, 094h, 0cdh
	db	0dbh, 098h, 0f1h, 057h, 0e1h, 07bh
	db	0b2h, 0c8h, 07ah, 0d6h, 001h, 0d8h
	db	0afh, 0bbh, 03ch, 0d0h, 015h, 01dh
	db	00ah, 0beh, 023h, 003h, 0cah, 057h
	db	090h, 03fh, 0c3h, 097h, 098h, 03ch
	db	08fh, 0c1h, 0a0h, 0c6h, 0ffh, 09fh
	db	0c3h, 09eh, 098h, 016h, 05ah, 0cdh
	db	0bch, 08eh, 0cdh, 0aah, 08eh, 0cdh
	db	0ech, 08ah, 07bh, 02fh, 04fh, 07ah
	db	02fh, 0cdh, 062h, 092h, 0c1h, 0c3h
	db	0c8h, 08eh, 02bh, 0cdh, 030h, 08ah
	db	0c8h, 0cdh, 0a2h, 088h, 02ch, 001h
	db	090h, 090h, 0c5h, 0f6h, 0afh, 032h
	db	0ach, 005h, 046h, 0cdh, 0d8h, 08ah
	db	0dah, 0d4h, 085h, 0afh, 04fh, 032h
	db	0adh, 005h, 0cdh, 030h, 08ah, 0dah
	db	0bah, 090h, 0cdh, 0d8h, 08ah, 0dah
	db	0c7h, 090h, 04fh, 0cdh, 030h, 08ah
	db	0dah, 0bbh, 090h, 0cdh, 0d8h, 08ah
	db	0d2h, 0bbh, 090h, 0d6h, 024h, 0c2h
	db	0d6h, 090h, 03ch, 032h, 0adh, 005h
	db	00fh, 081h, 04fh, 0cdh, 030h, 08ah
	db	03ah, 0cbh, 005h, 03dh, 0cah, 083h
	db	091h, 0f2h, 0e6h, 090h, 07eh, 0d6h
	db	028h, 0cah, 05bh, 091h, 0afh, 032h
	db	0cbh, 005h, 0e5h, 050h, 059h, 02ah
	db	0deh, 005h, 0cdh, 09ch, 088h, 011h
	db	0e0h, 005h, 0cah, 0cdh, 097h, 02ah
	db	0d8h, 005h, 0ebh, 02ah, 0d6h, 005h
	db	0cdh, 09ch, 088h, 0cah, 019h, 091h
	db	079h, 096h, 023h, 0c2h, 00eh, 091h
	db	078h, 096h, 023h, 0cah, 04dh, 091h
	db	023h, 023h, 023h, 023h, 0c3h, 000h
	db	091h, 0e1h, 0e3h, 0d5h, 011h, 09bh
	db	08fh, 0cdh, 09ch, 088h, 0d1h, 0cah
	db	050h, 091h, 0e3h, 0e5h, 0c5h, 001h
	db	006h, 000h, 02ah, 0dah, 005h, 0e5h
	db	009h, 0c1h, 0e5h, 0cdh, 0a0h, 085h
	db	0e1h, 022h, 0dah, 005h, 060h, 069h
	db	022h, 0d8h, 005h, 02bh, 036h, 000h
	db	0cdh, 09ch, 088h, 0c2h, 03fh, 091h
	db	0d1h, 073h, 023h, 072h, 023h, 0ebh
	db	0e1h, 0c9h, 032h, 0e7h, 005h, 021h
	db	070h, 085h, 022h, 0e4h, 005h, 0e1h
	db	0c9h, 0e5h, 02ah, 0ach, 005h, 0e3h
	db	057h, 0d5h, 0c5h, 0cdh, 0e0h, 08ah
	db	0c1h, 0f1h, 0ebh, 0e3h, 0e5h, 0ebh
	db	03ch, 057h, 07eh, 0feh, 02ch, 0cah
	db	061h, 091h, 0cdh, 0a2h, 088h, 029h
	db	022h, 0d0h, 005h, 0e1h, 022h, 0ach
	db	005h, 01eh, 000h, 0d5h, 011h, 0e5h
	db	0f5h, 02ah, 0d8h, 005h, 03eh, 019h
	db	0ebh, 02ah, 0dah, 005h, 0ebh, 0cdh
	db	09ch, 088h, 0cah, 0bbh, 091h, 07eh
	db	0b9h, 023h, 0c2h, 09dh, 091h, 07eh
	db	0b8h, 023h, 05eh, 023h, 056h, 023h
	db	0c2h, 089h, 091h, 03ah, 0ach, 005h
	db	0b7h, 0c2h, 0ddh, 085h, 0f1h, 044h
	db	04dh, 0cah, 0cdh, 097h, 096h, 0cah
	db	019h, 092h, 01eh, 010h, 0c3h, 0e8h
	db	085h, 011h, 004h, 000h, 0f1h, 0cah
	db	001h, 08bh, 071h, 023h, 070h, 023h
	db	04fh, 0cdh, 0b1h, 085h, 023h, 023h
	db	022h, 0c5h, 005h, 071h, 023h, 03ah
	db	0ach, 005h, 017h, 079h, 001h, 00bh
	db	000h, 0d2h, 0deh, 091h, 0c1h, 003h
	db	071h, 023h, 070h, 023h, 0f5h, 0e5h
	db	0cdh, 078h, 099h, 0ebh, 0e1h, 0f1h
	db	03dh, 0c2h, 0d6h, 091h, 0f5h, 042h
	db	04bh, 0ebh, 019h, 0dah, 0c9h, 085h
	db	0cdh, 0bah, 085h, 022h, 0dah, 005h
	db	02bh, 036h, 000h, 0cdh, 09ch, 088h
	db	0c2h, 0fch, 091h, 003h, 057h, 02ah
	db	0c5h, 005h, 05eh, 0ebh, 029h, 009h
	db	0ebh, 02bh, 02bh, 073h, 023h, 072h
	db	023h, 0f1h, 0dah, 03dh, 092h, 047h
	db	04fh, 07eh, 023h, 016h, 0e1h, 05eh
	db	023h, 056h, 023h, 0e3h, 0f5h, 0cdh
	db	09ch, 088h, 0d2h, 0b6h, 091h, 0e5h
	db	0cdh, 078h, 099h, 0d1h, 019h, 0f1h
	db	03dh, 044h, 04dh, 0c2h, 01eh, 092h
	db	029h, 029h, 0c1h, 009h, 0ebh, 02ah
	db	0d0h, 005h, 0c9h, 02ah, 0dah, 005h
	db	0ebh, 021h, 000h, 000h, 039h, 03ah
	db	0adh, 005h, 0b7h, 0cah, 05dh, 092h
	db	0cdh, 0c4h, 094h, 0cdh, 0c4h, 093h
	db	02ah, 05ah, 005h, 0ebh, 02ah, 0c3h
	db	005h, 07dh, 093h, 04fh, 07ch, 09ah
	db	041h, 050h, 01eh, 000h, 021h, 0adh
	db	005h, 073h, 006h, 090h, 0c3h, 0a3h
	db	098h, 03ah, 0abh, 005h, 047h, 0afh
	db	0c3h, 063h, 092h, 0cdh, 0fah, 092h
	db	0cdh, 0ech, 092h, 001h, 0d1h, 08bh
	db	0c5h, 0d5h, 0cdh, 0a2h, 088h, 028h
	db	0cdh, 09eh, 090h, 0e5h, 0ebh, 02bh
	db	056h, 02bh, 05eh, 0e1h, 0cdh, 0aah
	db	08eh, 0cdh, 0a2h, 088h, 029h, 0cdh
	db	0a2h, 088h, 0b4h, 044h, 04dh, 0e3h
	db	071h, 023h, 070h, 0c3h, 039h, 093h
	db	0cdh, 0fah, 092h, 0d5h, 0cdh, 07fh
	db	08fh, 0cdh, 0aah, 08eh, 0e3h, 05eh
	db	023h, 056h, 023h, 07ah, 0b3h, 0cah
	db	0e0h, 085h, 07eh, 023h, 066h, 06fh
	db	0e5h, 02ah, 0deh, 005h, 0e3h, 022h
	db	0deh, 005h, 02ah, 0e2h, 005h, 0e5h
	db	02ah, 0e0h, 005h, 0e5h, 021h, 0e0h
	db	005h, 0d5h, 0cdh, 0e4h, 098h, 0e1h
	db	0cdh, 0a7h, 08eh, 02bh, 0cdh, 030h
	db	08ah, 0c2h, 0d4h, 085h, 0e1h, 022h
	db	0e0h, 005h, 0e1h, 022h, 0e2h, 005h
	db	0e1h, 022h, 0deh, 005h, 0e1h, 0c9h
	db	0e5h, 02ah, 05ch, 005h, 023h, 07ch
	db	0b5h, 0e1h, 0c0h, 01eh, 016h, 0c3h
	db	0e8h, 085h, 0cdh, 0a2h, 088h, 0a7h
	db	03eh, 080h, 032h, 0cbh, 005h, 0b6h
	db	047h, 0cdh, 0a3h, 090h, 0c3h, 0aah
	db	08eh, 0cdh, 0aah, 08eh, 0cdh, 031h
	db	09ah, 0cdh, 03fh, 093h, 0cdh, 0c4h
	db	094h, 001h, 01fh, 095h, 0c5h, 07eh
	db	023h, 023h, 0e5h, 0cdh, 09ah, 093h
	db	0e1h, 04eh, 023h, 046h, 0cdh, 033h
	db	093h, 0e5h, 06fh, 0cdh, 0b7h, 094h
	db	0d1h, 0c9h, 0cdh, 09ah, 093h, 021h
	db	0bfh, 005h, 0e5h, 077h, 023h, 023h
	db	073h, 023h, 072h, 0e1h, 0c9h, 02bh
	db	006h, 022h, 050h, 0e5h, 00eh, 0ffh
	db	023h, 07eh, 00ch, 0b7h, 0cah, 055h
	db	093h, 0bah, 0cah, 055h, 093h, 0b8h
	db	0c2h, 046h, 093h, 0feh, 022h, 0cch
	db	030h, 08ah, 0e3h, 023h, 0ebh, 079h
	db	0cdh, 033h, 093h, 011h, 0bfh, 005h
	db	02ah, 0b1h, 005h, 022h, 0e4h, 005h
	db	03eh, 001h, 032h, 0adh, 005h, 0cdh
	db	0e7h, 098h, 0cdh, 09ch, 088h, 022h
	db	0b1h, 005h, 0e1h, 07eh, 0c0h, 01eh
	db	01eh, 0c3h, 0e8h, 085h, 023h, 0cdh
	db	03fh, 093h, 0cdh, 0c4h, 094h, 0cdh
	db	0dbh, 098h, 01ch, 01dh, 0c8h, 00ah
	db	0cdh, 0adh, 088h, 0feh, 00dh, 0cch
	db	0ech, 08ch, 003h, 0c3h, 08bh, 093h
	db	0b7h, 00eh, 0f1h, 0f5h, 02ah, 05ah
	db	005h, 0ebh, 02ah, 0c3h, 005h, 02fh
	db	04fh, 006h, 0ffh, 009h, 023h, 0cdh
	db	09ch, 088h, 0dah, 0b8h, 093h, 022h
	db	0c3h, 005h, 023h, 0ebh, 0f1h, 0c9h
	db	0f1h, 01eh, 01ah, 0cah, 0e8h, 085h
	db	0bfh, 0f5h, 001h, 09ch, 093h, 0c5h
	db	02ah, 0afh, 005h, 022h, 0c3h, 005h
	db	021h, 000h, 000h, 0e5h, 02ah, 05ah
	db	005h, 0e5h, 021h, 0b3h, 005h, 0ebh
	db	02ah, 0b1h, 005h, 0ebh, 0cdh, 09ch
	db	088h, 001h, 0d5h, 093h, 0c2h, 029h
	db	094h, 02ah, 0d6h, 005h, 0ebh, 02ah
	db	0d8h, 005h, 0ebh, 0cdh, 09ch, 088h
	db	0cah, 0fch, 093h, 07eh, 023h, 023h
	db	0b7h, 0cdh, 02ch, 094h, 0c3h, 0e6h
	db	093h, 0c1h, 0ebh, 02ah, 0dah, 005h
	db	0ebh, 0cdh, 09ch, 088h, 0cah, 052h
	db	094h, 0cdh, 0dbh, 098h, 07bh, 0e5h
	db	009h, 0b7h, 0f2h, 0fbh, 093h, 022h
	db	0c5h, 005h, 0e1h, 04eh, 006h, 000h
	db	009h, 009h, 023h, 0ebh, 02ah, 0c5h
	db	005h, 0ebh, 0cdh, 09ch, 088h, 0cah
	db	0fch, 093h, 001h, 01bh, 094h, 0c5h
	db	0f6h, 080h, 07eh, 023h, 023h, 05eh
	db	023h, 056h, 023h, 0f0h, 0b7h, 0c8h
	db	044h, 04dh, 02ah, 0c3h, 005h, 0cdh
	db	09ch, 088h, 060h, 069h, 0d8h, 0e1h
	db	0e3h, 0cdh, 09ch, 088h, 0e3h, 0e5h
	db	060h, 069h, 0d0h, 0c1h, 0f1h, 0f1h
	db	0e5h, 0d5h, 0c5h, 0c9h, 0d1h, 0e1h
	db	07dh, 0b4h, 0c8h, 02bh, 046h, 02bh
	db	04eh, 0e5h, 02bh, 02bh, 06eh, 026h
	db	000h, 009h, 050h, 059h, 02bh, 044h
	db	04dh, 02ah, 0c3h, 005h, 0cdh, 0a3h
	db	085h, 0e1h, 071h, 023h, 070h, 069h
	db	060h, 02bh, 0c3h, 0c7h, 093h, 0c5h
	db	0e5h, 02ah, 0e4h, 005h, 0e3h, 0cdh
	db	030h, 08fh, 0e3h, 0cdh, 0abh, 08eh
	db	07eh, 0e5h, 02ah, 0e4h, 005h, 0e5h
	db	086h, 01eh, 01ch, 0dah, 0e8h, 085h
	db	0cdh, 030h, 093h, 0d1h, 0cdh, 0c8h
	db	094h, 0e3h, 0cdh, 0c7h, 094h, 0e5h
	db	02ah, 0c1h, 005h, 0ebh, 0cdh, 0aeh
	db	094h, 0cdh, 0aeh, 094h, 021h, 0c5h
	db	08eh, 0e3h, 0e5h, 0c3h, 061h, 093h
	db	0e1h, 0e3h, 07eh, 023h, 023h, 04eh
	db	023h, 046h, 06fh, 02ch, 02dh, 0c8h
	db	00ah, 012h, 003h, 013h, 0c3h, 0b8h
	db	094h, 0cdh, 0abh, 08eh, 02ah, 0e4h
	db	005h, 0ebh, 0cdh, 0e2h, 094h, 0ebh
	db	0c0h, 0d5h, 050h, 059h, 01bh, 04eh
	db	02ah, 0c3h, 005h, 0cdh, 09ch, 088h
	db	0c2h, 0e0h, 094h, 047h, 009h, 022h
	db	0c3h, 005h, 0e1h, 0c9h, 02ah, 0b1h
	db	005h, 02bh, 046h, 02bh, 04eh, 02bh
	db	02bh, 0cdh, 09ch, 088h, 0c0h, 022h
	db	0b1h, 005h, 0c9h, 001h, 072h, 092h
	db	0c5h, 0cdh, 0c1h, 094h, 0afh, 057h
	db	032h, 0adh, 005h, 07eh, 0b7h, 0c9h
	db	001h, 072h, 092h, 0c5h, 0cdh, 0f7h
	db	094h, 0cah, 001h, 08bh, 023h, 023h
	db	05eh, 023h, 056h, 01ah, 0c9h, 03eh
	db	001h, 0cdh, 030h, 093h, 0cdh, 00eh
	db	096h, 02ah, 0c1h, 005h, 073h, 0c1h
	db	0c3h, 061h, 093h, 0cdh, 0beh, 095h
	db	0afh, 0e3h, 04fh, 0e5h, 07eh, 0b8h
	db	0dah, 031h, 095h, 078h, 011h, 00eh
	db	000h, 0c5h, 0cdh, 09ah, 093h, 0c1h
	db	0e1h, 0e5h, 023h, 023h, 046h, 023h
	db	066h, 068h, 006h, 000h, 009h, 044h
	db	04dh, 0cdh, 033h, 093h, 06fh, 0cdh
	db	0b7h, 094h, 0d1h, 0cdh, 0c8h, 094h
	db	0c3h, 061h, 093h, 0cdh, 0beh, 095h
	db	0d1h, 0d5h, 01ah, 090h, 0c3h, 027h
	db	095h, 0ebh, 07eh, 0cdh, 0c3h, 095h
	db	004h, 005h, 0cah, 001h, 08bh, 0c5h
	db	01eh, 0ffh, 0feh, 029h, 0cah, 076h
	db	095h, 0cdh, 0a2h, 088h, 02ch, 0cdh
	db	00bh, 096h, 0cdh, 0a2h, 088h, 029h
	db	0f1h, 0e3h, 001h, 029h, 095h, 0c5h
	db	03dh, 0beh, 006h, 000h, 0d0h, 04fh
	db	07eh, 091h, 0bbh, 047h, 0d8h, 043h
	db	0c9h, 0cdh, 0f7h, 094h, 0cah, 0ach
	db	096h, 05fh, 023h, 023h, 07eh, 023h
	db	066h, 06fh, 0e5h, 019h, 046h, 072h
	db	0e3h, 0c5h, 07eh, 0feh, 024h, 0c2h
	db	0ach, 095h, 0cdh, 0ddh, 09dh, 0c3h
	db	0bah, 095h, 0feh, 025h, 0c2h, 0b7h
	db	095h, 0cdh, 059h, 09eh, 0c3h, 0bah
	db	095h, 0cdh, 093h, 099h, 0c1h, 0e1h
	db	070h, 0c9h, 0ebh, 0cdh, 0a2h, 088h
	db	029h, 0c1h, 0d1h, 0c5h, 043h, 0c9h
	db	0cdh, 00eh, 096h, 032h, 03fh, 005h
	db	0cdh, 03eh, 005h, 0c3h, 072h, 092h
	db	0cdh, 0f8h, 095h, 0c3h, 006h, 005h
	db	0cdh, 0f8h, 095h, 0f5h, 01eh, 000h
	db	02bh, 0cdh, 030h, 08ah, 0cah, 0eeh
	db	095h, 0cdh, 0a2h, 088h, 02ch, 0cdh
	db	00bh, 096h, 0c1h, 0cdh, 03eh, 005h
	db	0abh, 0a0h, 0cah, 0efh, 095h, 0c9h
	db	0cdh, 00bh, 096h, 032h, 03fh, 005h
	db	032h, 007h, 005h, 0cdh, 0a2h, 088h
	db	02ch, 0c3h, 00bh, 096h, 0cdh, 030h
	db	08ah, 0cdh, 0a7h, 08eh, 0cdh, 0e6h
	db	08ah, 07ah, 0b7h, 0c2h, 001h, 08bh
	db	02bh, 0cdh, 030h, 08ah, 07bh, 0c9h
	db	0cdh, 0ech, 08ah, 01ah, 0c3h, 072h
	db	092h, 0cdh, 0a7h, 08eh, 0cdh, 0ech
	db	08ah, 0d5h, 0cdh, 0a2h, 088h, 02ch
	db	0cdh, 00bh, 096h, 0d1h, 012h, 0c9h
	db	021h, 00ah, 09bh, 0cdh, 0dbh, 098h
	db	0c3h, 046h, 096h, 0cdh, 0dbh, 098h
	db	021h, 0c1h, 0d1h, 0cdh, 0b5h, 098h
	db	078h, 0b7h, 0c8h, 03ah, 0e7h, 005h
	db	0b7h, 0cah, 0cdh, 098h, 090h, 0d2h
	db	060h, 096h, 02fh, 03ch, 0ebh, 0cdh
	db	0bdh, 098h, 0ebh, 0cdh, 0cdh, 098h
	db	0c1h, 0d1h, 0feh, 019h, 0d0h, 0f5h
	db	0cdh, 0f2h, 098h, 067h, 0f1h, 0cdh
	db	00bh, 097h, 0b4h, 021h, 0e4h, 005h
	db	0f2h, 086h, 096h, 0cdh, 0ebh, 096h
	db	0d2h, 0cch, 096h, 023h, 034h, 0cah
	db	0e3h, 085h, 02eh, 001h, 0cdh, 021h
	db	097h, 0c3h, 0cch, 096h, 0afh, 090h
	db	047h, 07eh, 09bh, 05fh, 023h, 07eh
	db	09ah, 057h, 023h, 07eh, 099h, 04fh
	db	0dch, 0f7h, 096h, 068h, 063h, 0afh
	db	047h, 079h, 0b7h, 0c2h, 0b9h, 096h
	db	04ah, 054h, 065h, 06fh, 078h, 0d6h
	db	008h, 0feh, 0e0h, 0c2h, 09ah, 096h
	db	0afh, 032h, 0e7h, 005h, 0c9h, 005h
	db	029h, 07ah, 017h, 057h, 079h, 08fh
	db	04fh, 0f2h, 0b1h, 096h, 078h, 05ch
	db	045h, 0b7h, 0cah, 0cch, 096h, 021h
	db	0e7h, 005h, 086h, 077h, 0d2h, 0ach
	db	096h, 0c8h, 078h, 021h, 0e7h, 005h
	db	0b7h, 0fch, 0deh, 096h, 046h, 023h
	db	07eh, 0e6h, 080h, 0a9h, 04fh, 0c3h
	db	0cdh, 098h, 01ch, 0c0h, 014h, 0c0h
	db	00ch, 0c0h, 00eh, 080h, 034h, 0c0h
	db	0c3h, 0e3h, 085h, 07eh, 083h, 05fh
	db	023h, 07eh, 08ah, 057h, 023h, 07eh
	db	089h, 04fh, 0c9h, 021h, 0e8h, 005h
	db	07eh, 02fh, 077h, 0afh, 06fh, 090h
	db	047h, 07dh, 09bh, 05fh, 07dh, 09ah
	db	057h, 07dh, 099h, 04fh, 0c9h, 006h
	db	000h, 0d6h, 008h, 0dah, 01ah, 097h
	db	043h, 05ah, 051h, 00eh, 000h, 0c3h
	db	00dh, 097h, 0c6h, 009h, 06fh, 0afh
	db	02dh, 0c8h, 079h, 01fh, 04fh, 07ah
	db	01fh, 057h, 07bh, 01fh, 05fh, 078h
	db	01fh, 047h, 0c3h, 01dh, 097h, 000h
	db	000h, 000h, 081h, 003h, 0aah, 056h
	db	019h, 080h, 0f1h, 022h, 076h, 080h
	db	045h, 0aah, 038h, 082h, 0cdh, 08ch
	db	098h, 0b7h, 0eah, 001h, 08bh, 021h
	db	0e7h, 005h, 07eh, 001h, 035h, 080h
	db	011h, 0f3h, 004h, 090h, 0f5h, 070h
	db	0d5h, 0c5h, 0cdh, 046h, 096h, 0c1h
	db	0d1h, 004h, 0cdh, 0e2h, 097h, 021h
	db	02fh, 097h, 0cdh, 03dh, 096h, 021h
	db	033h, 097h, 0cdh, 0d4h, 09bh, 001h
	db	080h, 080h, 011h, 000h, 000h, 0cdh
	db	046h, 096h, 0f1h, 0cdh, 007h, 09ah
	db	001h, 031h, 080h, 011h, 018h, 072h
	db	021h, 0c1h, 0d1h, 0cdh, 08ch, 098h
	db	0c8h, 02eh, 000h, 0cdh, 04ah, 098h
	db	079h, 032h, 0f6h, 005h, 0ebh, 022h
	db	0f7h, 005h, 001h, 000h, 000h, 050h
	db	058h, 021h, 097h, 096h, 0e5h, 021h
	db	0a3h, 097h, 0e5h, 0e5h, 021h, 0e4h
	db	005h, 07eh, 023h, 0b7h, 0cah, 0cfh
	db	097h, 0e5h, 02eh, 008h, 01fh, 067h
	db	079h, 0d2h, 0bdh, 097h, 0e5h, 02ah
	db	0f7h, 005h, 019h, 0ebh, 0e1h, 03ah
	db	0f6h, 005h, 089h, 01fh, 04fh, 07ah
	db	01fh, 057h, 07bh, 01fh, 05fh, 078h
	db	01fh, 047h, 02dh, 07ch, 0c2h, 0ach
	db	097h, 0e1h, 0c9h, 043h, 05ah, 051h
	db	04fh, 0c9h, 0cdh, 0bdh, 098h, 001h
	db	020h, 084h, 011h, 000h, 000h, 0cdh
	db	0cdh, 098h, 0c1h, 0d1h, 0cdh, 08ch
	db	098h, 0cah, 0d7h, 085h, 02eh, 0ffh
	db	0cdh, 04ah, 098h, 034h, 034h, 02bh
	db	07eh, 032h, 012h, 005h, 02bh, 07eh
	db	032h, 00eh, 005h, 02bh, 07eh, 032h
	db	00ah, 005h, 041h, 0ebh, 0afh, 04fh
	db	057h, 05fh, 032h, 015h, 005h, 0e5h
	db	0c5h, 07dh, 0cdh, 009h, 005h, 0deh
	db	000h, 03fh, 0d2h, 01ah, 098h, 032h
	db	015h, 005h, 0f1h, 0f1h, 037h, 0d2h
	db	0c1h, 0e1h, 079h, 03ch, 03dh, 01fh
	db	0fah, 0cdh, 096h, 017h, 07bh, 017h
	db	05fh, 07ah, 017h, 057h, 079h, 017h
	db	04fh, 029h, 078h, 017h, 047h, 03ah
	db	015h, 005h, 017h, 032h, 015h, 005h
	db	079h, 0b2h, 0b3h, 0c2h, 007h, 098h
	db	0e5h, 021h, 0e7h, 005h, 035h, 0e1h
	db	0c2h, 007h, 098h, 0c3h, 0e3h, 085h
	db	078h, 0b7h, 0cah, 06eh, 098h, 07dh
	db	021h, 0e7h, 005h, 0aeh, 080h, 047h
	db	01fh, 0a8h, 078h, 0f2h, 06dh, 098h
	db	0c6h, 080h, 077h, 0cah, 0cdh, 097h
	db	0cdh, 0f2h, 098h, 077h, 02bh, 0c9h
	db	0cdh, 08ch, 098h, 02fh, 0e1h, 0b7h
	db	0e1h, 0f2h, 0ach, 096h, 0c3h, 0e3h
	db	085h, 0cdh, 0d8h, 098h, 078h, 0b7h
	db	0c8h, 0c6h, 002h, 0dah, 0e3h, 085h
	db	047h, 0cdh, 046h, 096h, 021h, 0e7h
	db	005h, 034h, 0c0h, 0c3h, 0e3h, 085h
	db	03ah, 0e7h, 005h, 0b7h, 0c8h, 03ah
	db	0e6h, 005h, 0feh, 02fh, 017h, 09fh
	db	0c0h, 03ch, 0c9h, 0cdh, 08ch, 098h
	db	006h, 088h, 011h, 000h, 000h, 021h
	db	0e7h, 005h, 04fh, 070h, 006h, 000h
	db	023h, 036h, 080h, 017h, 0c3h, 094h
	db	096h, 0cdh, 08ch, 098h, 0f0h, 021h
	db	0e6h, 005h, 07eh, 0eeh, 080h, 077h
	db	0c9h, 0ebh, 02ah, 0e4h, 005h, 0e3h
	db	0e5h, 02ah, 0e6h, 005h, 0e3h, 0e5h
	db	0ebh, 0c9h, 0cdh, 0dbh, 098h, 0ebh
	db	022h, 0e4h, 005h, 060h, 069h, 022h
	db	0e6h, 005h, 0ebh, 0c9h, 021h, 0e4h
	db	005h, 05eh, 023h, 056h, 023h, 04eh
	db	023h, 046h, 023h, 0c9h, 011h, 0e4h
	db	005h, 006h, 004h, 01ah, 077h, 013h
	db	023h, 005h, 0c2h, 0e9h, 098h, 0c9h
	db	021h, 0e6h, 005h, 07eh, 007h, 037h
	db	01fh, 077h, 03fh, 01fh, 023h, 023h
	db	077h, 079h, 007h, 037h, 01fh, 04fh
	db	01fh, 0aeh, 0c9h, 078h, 0b7h, 0cah
	db	08ch, 098h, 021h, 095h, 098h, 0e5h
	db	0cdh, 08ch, 098h, 079h, 0c8h, 021h
	db	0e6h, 005h, 0aeh, 079h, 0f8h, 0cdh
	db	021h, 099h, 01fh, 0a9h, 0c9h, 023h
	db	078h, 0beh, 0c0h, 02bh, 079h, 0beh
	db	0c0h, 02bh, 07ah, 0beh, 0c0h, 02bh
	db	07bh, 096h, 0c0h, 0e1h, 0e1h, 0c9h
	db	047h, 04fh, 057h, 05fh, 0b7h, 0c8h
	db	0e5h, 0cdh, 0d8h, 098h, 0cdh, 0f2h
	db	098h, 0aeh, 067h, 0fch, 058h, 099h
	db	03eh, 098h, 090h, 0cdh, 00bh, 097h
	db	07ch, 017h, 0dch, 0deh, 096h, 006h
	db	000h, 0dch, 0f7h, 096h, 0e1h, 0c9h
	db	01bh, 07ah, 0a3h, 03ch, 0c0h, 00bh
	db	0c9h, 021h, 0e7h, 005h, 07eh, 0feh
	db	098h, 03ah, 0e4h, 005h, 0d0h, 07eh
	db	0cdh, 034h, 099h, 036h, 098h, 07bh
	db	0f5h, 079h, 017h, 0cdh, 094h, 096h
	db	0f1h, 0c9h, 021h, 000h, 000h, 078h
	db	0b1h, 0c8h, 03eh, 010h, 029h, 0dah
	db	0b6h, 091h, 0ebh, 029h, 0ebh, 0d2h
	db	08eh, 099h, 009h, 0dah, 0b6h, 091h
	db	03dh, 0c2h, 080h, 099h, 0c9h, 0feh
	db	02dh, 0f5h, 0cah, 09fh, 099h, 0feh
	db	02bh, 0cah, 09fh, 099h, 02bh, 0cdh
	db	0ach, 096h, 047h, 057h, 05fh, 02fh
	db	04fh, 0cdh, 030h, 08ah, 0dah, 0f0h
	db	099h, 0feh, 02eh, 0cah, 0cbh, 099h
	db	0feh, 045h, 0c2h, 0cfh, 099h, 0cdh
	db	030h, 08ah, 0cdh, 0e1h, 08fh, 0cdh
	db	030h, 08ah, 0dah, 012h, 09ah, 014h
	db	0c2h, 0cfh, 099h, 0afh, 093h, 05fh
	db	00ch, 00ch, 0cah, 0a7h, 099h, 0e5h
	db	07bh, 090h, 0f4h, 0e8h, 099h, 0f2h
	db	0deh, 099h, 0f5h, 0cdh, 0d4h, 097h
	db	0f1h, 03ch, 0c2h, 0d2h, 099h, 0d1h
	db	0f1h, 0cch, 0b5h, 098h, 0ebh, 0c9h
	db	0c8h, 0f5h, 0cdh, 075h, 098h, 0f1h
	db	03dh, 0c9h, 0d5h, 057h, 078h, 089h
	db	047h, 0c5h, 0e5h, 0d5h, 0cdh, 075h
	db	098h, 0f1h, 0d6h, 030h, 0cdh, 007h
	db	09ah, 0e1h, 0c1h, 0d1h, 0c3h, 0a7h
	db	099h, 0cdh, 0bdh, 098h, 0cdh, 09eh
	db	098h, 0c1h, 0d1h, 0c3h, 046h, 096h
	db	07bh, 007h, 007h, 083h, 007h, 086h
	db	0d6h, 030h, 05fh, 0c3h, 0bdh, 099h
	db	0e5h, 021h, 06ch, 085h, 0cdh, 081h
	db	093h, 0e1h, 0ebh, 0afh, 006h, 098h
	db	0cdh, 0a3h, 098h, 021h, 080h, 093h
	db	0e5h, 021h, 0e9h, 005h, 0e5h, 0cdh
	db	08ch, 098h, 036h, 020h, 0f2h, 03fh
	db	09ah, 036h, 02dh, 023h, 036h, 030h
	db	0cah, 0f5h, 09ah, 0e5h, 0fch, 0b5h
	db	098h, 0afh, 0f5h, 0cdh, 0fbh, 09ah
	db	001h, 043h, 091h, 011h, 0f8h, 04fh
	db	0cdh, 007h, 099h, 0b7h, 0e2h, 06ch
	db	09ah, 0f1h, 0cdh, 0e9h, 099h, 0f5h
	db	0c3h, 04eh, 09ah, 0cdh, 0d4h, 097h
	db	0f1h, 03ch, 0f5h, 0cdh, 0fbh, 09ah
	db	0cdh, 034h, 096h, 03ch, 0cdh, 034h
	db	099h, 0cdh, 0cdh, 098h, 001h, 006h
	db	003h, 0f1h, 081h, 03ch, 0fah, 088h
	db	09ah, 0feh, 008h, 0d2h, 088h, 09ah
	db	03ch, 047h, 03eh, 002h, 03dh, 03dh
	db	0e1h, 0f5h, 011h, 00eh, 09bh, 005h
	db	0c2h, 099h, 09ah, 036h, 02eh, 023h
	db	036h, 030h, 023h, 005h, 036h, 02eh
	db	0cch, 0e2h, 098h, 0c5h, 0e5h, 0d5h
	db	0cdh, 0d8h, 098h, 0e1h, 006h, 02fh
	db	004h, 07bh, 096h, 05fh, 023h, 07ah
	db	09eh, 057h, 023h, 079h, 09eh, 04fh
	db	02bh, 02bh, 0d2h, 0a8h, 09ah, 0cdh
	db	0ebh, 096h, 023h, 0cdh, 0cdh, 098h
	db	0ebh, 0e1h, 070h, 023h, 0c1h, 00dh
	db	0c2h, 099h, 09ah, 005h, 0cah, 0d9h
	db	09ah, 02bh, 07eh, 0feh, 030h, 0cah
	db	0cdh, 09ah, 0feh, 02eh, 0c4h, 0e2h
	db	098h, 0f1h, 0cah, 0f8h, 09ah, 036h
	db	045h, 023h, 036h, 02bh, 0f2h, 0e9h
	db	09ah, 036h, 02dh, 02fh, 03ch, 006h
	db	02fh, 004h, 0d6h, 00ah, 0d2h, 0ebh
	db	09ah, 0c6h, 03ah, 023h, 070h, 023h
	db	077h, 023h, 071h, 0e1h, 0c9h, 001h
	db	074h, 094h, 011h, 0f7h, 023h, 0cdh
	db	007h, 099h, 0b7h, 0e1h, 0e2h, 063h
	db	09ah, 0e9h, 000h, 000h, 000h, 080h
	db	0a0h, 086h, 001h, 010h, 027h, 000h
	db	0e8h, 003h, 000h, 064h, 000h, 000h
	db	00ah, 000h, 000h, 001h, 000h, 000h
	db	021h, 0b5h, 098h, 0e3h, 0e9h, 0cdh
	db	0bdh, 098h, 021h, 00ah, 09bh, 0cdh
	db	0cah, 098h, 0c1h, 0d1h, 0cdh, 08ch
	db	098h, 078h, 0cah, 073h, 09bh, 0f2h
	db	03eh, 09bh, 0b7h, 0cah, 0d7h, 085h
	db	0b7h, 0cah, 0adh, 096h, 0d5h, 0c5h
	db	079h, 0f6h, 07fh, 0cdh, 0d8h, 098h
	db	0f2h, 05bh, 09bh, 0d5h, 0c5h, 0cdh
	db	05fh, 099h, 0c1h, 0d1h, 0f5h, 0cdh
	db	007h, 099h, 0e1h, 07ch, 01fh, 0e1h
	db	022h, 0e6h, 005h, 0e1h, 022h, 0e4h
	db	005h, 0dch, 020h, 09bh, 0cch, 0b5h
	db	098h, 0d5h, 0c5h, 0cdh, 040h, 097h
	db	0c1h, 0d1h, 0cdh, 081h, 097h, 0cdh
	db	0bdh, 098h, 001h, 038h, 081h, 011h
	db	03bh, 0aah, 0cdh, 081h, 097h, 03ah
	db	0e7h, 005h, 0feh, 088h, 0d2h, 068h
	db	098h, 0cdh, 05fh, 099h, 0c6h, 080h
	db	0c6h, 002h, 0dah, 068h, 098h, 0f5h
	db	021h, 02fh, 097h, 0cdh, 037h, 096h
	db	0cdh, 078h, 097h, 0f1h, 0c1h, 0d1h
	db	0f5h, 0cdh, 043h, 096h, 0cdh, 0b5h
	db	098h, 021h, 0b3h, 09bh, 0cdh, 0e3h
	db	09bh, 011h, 000h, 000h, 0c1h, 04ah
	db	0c3h, 081h, 097h, 008h, 040h, 02eh
	db	094h, 074h, 070h, 04fh, 02eh, 077h
	db	06eh, 002h, 088h, 07ah, 0e6h, 0a0h
	db	02ah, 07ch, 050h, 0aah, 0aah, 07eh
	db	0ffh, 0ffh, 07fh, 07fh, 000h, 000h
	db	080h, 081h, 000h, 000h, 000h, 081h
	db	0cdh, 0bdh, 098h, 011h, 07fh, 097h
	db	0d5h, 0e5h, 0cdh, 0d8h, 098h, 0cdh
	db	081h, 097h, 0e1h, 0cdh, 0bdh, 098h
	db	07eh, 023h, 0cdh, 0cah, 098h, 006h
	db	0f1h, 0c1h, 0d1h, 03dh, 0c8h, 0d5h
	db	0c5h, 0f5h, 0e5h, 0cdh, 081h, 097h
	db	0e1h, 0cdh, 0dbh, 098h, 0e5h, 0cdh
	db	046h, 096h, 0e1h, 0c3h, 0ech, 09bh
	db	0cdh, 08ch, 098h, 021h, 019h, 005h
	db	0fah, 065h, 09ch, 021h, 03ah, 005h
	db	0cdh, 0cah, 098h, 021h, 019h, 005h
	db	0c8h, 086h, 0e6h, 007h, 006h, 000h
	db	077h, 023h, 087h, 087h, 04fh, 009h
	db	0cdh, 0dbh, 098h, 0cdh, 081h, 097h
	db	03ah, 018h, 005h, 03ch, 0e6h, 003h
	db	006h, 000h, 0feh, 001h, 088h, 032h
	db	018h, 005h, 021h, 069h, 09ch, 087h
	db	087h, 04fh, 009h, 0cdh, 037h, 096h
	db	0cdh, 0d8h, 098h, 07bh, 059h, 0eeh
	db	04fh, 04fh, 036h, 080h, 02bh, 046h
	db	036h, 080h, 021h, 017h, 005h, 034h
	db	07eh, 0d6h, 0abh, 0c2h, 05ch, 09ch
	db	077h, 00ch, 015h, 01ch, 0cdh, 097h
	db	096h, 021h, 03ah, 005h, 0c3h, 0e4h
	db	098h, 077h, 02bh, 077h, 02bh, 077h
	db	0c3h, 040h, 09ch, 068h, 0b1h, 046h
	db	068h, 099h, 0e9h, 092h, 069h, 010h
	db	0d1h, 075h, 068h, 021h, 0c3h, 09ch
	db	0cdh, 037h, 096h, 0cdh, 0bdh, 098h
	db	001h, 049h, 083h, 011h, 0dbh, 00fh
	db	0cdh, 0cdh, 098h, 0c1h, 0d1h, 0cdh
	db	0e2h, 097h, 0cdh, 0bdh, 098h, 0cdh
	db	05fh, 099h, 0c1h, 0d1h, 0cdh, 043h
	db	096h, 021h, 0c7h, 09ch, 0cdh, 03dh
	db	096h, 0cdh, 08ch, 098h, 037h, 0f2h
	db	0afh, 09ch, 0cdh, 034h, 096h, 0cdh
	db	08ch, 098h, 0b7h, 0f5h, 0f4h, 0b5h
	db	098h, 021h, 0c7h, 09ch, 0cdh, 037h
	db	096h, 0f1h, 0d4h, 0b5h, 098h, 021h
	db	0cbh, 09ch, 0c3h, 0d4h, 09bh, 0dbh
	db	00fh, 049h, 081h, 000h, 000h, 000h
	db	07fh, 005h, 0bah, 0d7h, 01eh, 086h
	db	064h, 026h, 099h, 087h, 058h, 034h
	db	023h, 087h, 0e0h, 05dh, 0a5h, 086h
	db	0dah, 00fh, 049h, 083h, 0cdh, 0bdh
	db	098h, 0cdh, 07fh, 09ch, 0c1h, 0e1h
	db	0cdh, 0bdh, 098h, 0ebh, 0cdh, 0cdh
	db	098h, 0cdh, 079h, 09ch, 0c3h, 0e0h
	db	097h, 0cdh, 08ch, 098h, 0fch, 020h
	db	09bh, 0fch, 0b5h, 098h, 03ah, 0e7h
	db	005h, 0feh, 081h, 0dah, 012h, 09dh
	db	001h, 000h, 081h, 051h, 059h, 0cdh
	db	0e2h, 097h, 021h, 03dh, 096h, 0e5h
	db	021h, 01ch, 09dh, 0cdh, 0d4h, 09bh
	db	021h, 0c3h, 09ch, 0c9h, 009h, 04ah
	db	0d7h, 03bh, 078h, 002h, 06eh, 084h
	db	07bh, 0feh, 0c1h, 02fh, 07ch, 074h
	db	031h, 09ah, 07dh, 084h, 03dh, 05ah
	db	07dh, 0c8h, 07fh, 091h, 07eh, 0e4h
	db	0bbh, 04ch, 07eh, 06ch, 0aah, 0aah
	db	07fh, 000h, 000h, 000h, 081h, 0c9h
	db	03eh, 00ch, 0c3h, 007h, 082h, 0cdh
	db	00bh, 096h, 07bh, 032h, 042h, 005h
	db	0c9h, 0cdh, 0a7h, 08eh, 0cdh, 0ech
	db	08ah, 0e5h, 0d5h, 0e1h, 022h, 046h
	db	005h, 022h, 048h, 005h, 0e1h, 0c9h
	db	0cdh, 0ech, 08ah, 0d5h, 0e1h, 046h
	db	023h, 07eh, 0c3h, 063h, 092h, 0cdh
	db	0a7h, 08eh, 0cdh, 0ech, 08ah, 0d5h
	db	0cdh, 0a2h, 088h, 02ch, 0cdh, 0a7h
	db	08eh, 0cdh, 0ech, 08ah, 0e3h, 073h
	db	023h, 072h, 0e1h, 0c9h, 0cdh, 0aah
	db	08eh, 0cdh, 0ech, 08ah, 0c5h, 021h
	db	0e9h, 005h, 07ah, 0feh, 000h, 0cah
	db	09fh, 09dh, 0cdh, 0beh, 09dh, 078h
	db	0feh, 030h, 0cah, 09dh, 09dh, 070h
	db	023h, 071h, 023h, 07bh, 0cdh, 0beh
	db	09dh, 07ah, 0feh, 000h, 0c2h, 0afh
	db	09dh, 078h, 0feh, 030h, 0cah, 0b1h
	db	09dh, 070h, 023h, 071h, 023h, 0afh
	db	077h, 023h, 077h, 0c1h, 021h, 0e9h
	db	005h, 0c3h, 011h, 093h, 047h, 0e6h
	db	00fh, 0feh, 00ah, 0dah, 0c8h, 09dh
	db	0c6h, 007h, 0c6h, 030h, 04fh, 078h
	db	00fh, 00fh, 00fh, 00fh, 0e6h, 00fh
	db	0feh, 00ah, 0dah, 0d9h, 09dh, 0c6h
	db	007h, 0c6h, 030h, 047h, 0c9h, 0ebh
	db	021h, 000h, 000h, 0cdh, 0f9h, 09dh
	db	0dah, 01ah, 09eh, 0c3h, 0f0h, 09dh
	db	0cdh, 0f9h, 09dh, 0dah, 011h, 09eh
	db	029h, 029h, 029h, 029h, 0b5h, 06fh
	db	0c3h, 0eah, 09dh, 013h, 01ah, 0feh
	db	020h, 0cah, 0f9h, 09dh, 0d6h, 030h
	db	0d8h, 0feh, 00ah, 0dah, 00dh, 09eh
	db	0d6h, 007h, 0feh, 00ah, 0d8h, 0feh
	db	010h, 03fh, 0c9h, 0ebh, 07ah, 04bh
	db	0e5h, 0cdh, 062h, 092h, 0e1h, 0c9h
	db	01eh, 026h, 0c3h, 0e8h, 085h, 0cdh
	db	0aah, 08eh, 0cdh, 0ech, 08ah, 0c5h
	db	021h, 0e9h, 005h, 006h, 011h, 005h
	db	078h, 0feh, 001h, 0cah, 03eh, 09eh
	db	07bh, 017h, 05fh, 07ah, 017h, 057h
	db	0d2h, 02bh, 09eh, 0c3h, 044h, 09eh
	db	07bh, 017h, 05fh, 07ah, 017h, 057h
	db	03eh, 030h, 0ceh, 000h, 077h, 023h
	db	005h, 0c2h, 03eh, 09eh, 0afh, 077h
	db	023h, 077h, 0c1h, 021h, 0e9h, 005h
	db	0c3h, 011h, 093h, 0ebh, 021h, 000h
	db	000h, 0cdh, 077h, 09eh, 0dah, 085h
	db	09eh, 0d6h, 030h, 029h, 0b5h, 06fh
	db	0cdh, 077h, 09eh, 0d2h, 063h, 09eh
	db	0ebh, 07ah, 04bh, 0e5h, 0cdh, 062h
	db	092h, 0e1h, 0c9h, 013h, 01ah, 0feh
	db	020h, 0cah, 077h, 09eh, 0feh, 030h
	db	0d8h, 0feh, 032h, 03fh, 0c9h, 01eh
	db	028h, 0c3h, 0e8h, 085h, 0c3h, 027h
	db	082h, 03eh, 000h, 032h, 04dh, 005h
	db	0c3h, 02eh, 082h, 0f5h, 0a0h, 0c1h
	db	0b8h, 03eh, 000h, 0c9h, 0cdh, 0adh
	db	088h, 0c3h, 0e2h, 08ch
 ;
;	Reset
	org	0fff0h
	db	0eah	;jmp
	dw	start	;offset
	dw	0000h	;segment
;
	end
