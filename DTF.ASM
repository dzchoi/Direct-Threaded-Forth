TITLE	Direct-Threaded Forth v0.8	07-30-95
.XALL

;; 8086/8088 register usage

;	BX		top of stack
;	SI		interpretive pointer
;       SP              data stack pointer
;	BP		return stack pointer
;	CS = DS = SS	segment pointers
;	DF (= up)	direction flag

;; CONTEXT vocabularies

;	+---------------+
;	|      va1	| ---> transient vocabulary
;	+---------------+
;	+---------------+
;	|      va2	| -+
;	+---------------+  |
;	|      va3	|  |
;	+---------------+  |-> resident vocabularies
;	|      va4	|  |
;	+---------------+  |
;	|      va5	| -+
;	+---------------+

;; constants

_IMME		EQU	40H		;lexicon immediate bit
_MASK		EQU	1FH		;lexicon bit mask

_PAD		EQU	80		;offset of PAD from HERE
_VOCS		EQU	5		;depth of vocabulary stack
_WIDTH		EQU	80		;screen width assumed by EXPECT

_BS		EQU	8		;back space
_LF		EQU	10		;line feed
_CR		EQU	13		;carriage return

_CALL		EQU	0E8H		;"CALL" opcode

;; memory allocation

_CELL		EQU	2		;size of a cell
_US		EQU	64*_CELL	;user area size
_RTS		EQU	128*_CELL	;return stack/TIB size

_EM		EQU	0		;64K top of memory + 1
_UP		EQU	_EM-_US 	;start of user area
_RP0		EQU	_UP-8*_CELL	;start of return stack
_TIB		EQU	_RP0-_RTS	;terminal input buffer
_SP0		EQU	_TIB-8*_CELL	;start of data stack

;; meta compiler

		IF1

;	meta VOCABULARY

$VOCAB		MACRO	VOCAB

_&VOCAB 	=	NULL		;;begin with the null word

VOCAB		MACRO

;	meta CODE

$CODE		MACRO	ALIAS, NAME
		DW	_&VOCAB
_LAST		=	$		;;nfa of the last word
		DB	?, NAME
_SIZE		=	$-_LAST-1	;;name length of the last word
		ORG	_LAST
		DB	_SIZE
		ORG	$+_SIZE
_&VOCAB 	=	_LAST		;;link this word to current vocab
ALIAS           LABEL   NEAR            ;;alias to ca of this word
		ENDM
                ENDM
                ENDM

;	meta :

$COLON          MACRO   ALIAS, NAME
		$CODE	ALIAS, NAME
		CALL	NEST		;;7+1 clocks, 3 bytes
                ENDM

;       meta USER

$USER           MACRO   ALIAS, NAME
                ; defines a user variable with initial values
		$CODE	ALIAS, NAME
		CALL	DOUSE		;;7+1 clocks, 3 bytes
                DW      _RESU
_HERE           =       $
                ORG     _UZERO+_RESU
                ENDM

$RESU           MACRO
_RESU           =       $-_UZERO
                ORG     _HERE
                ENDM

USER$           MACRO   ALIAS, NAME
                ; defines an uninitialized user variable
		$CODE	ALIAS, NAME
                CALL    DOUSE           ;;7+1 clocks, 3 bytes
                DW      _USER
_USER           =       _USER+_CELL
                ENDM

;       meta CONSTANT

$CONST          MACRO   ALIAS, NAME
		$CODE	ALIAS, NAME
		CALL	DOCON		;;7+1 clocks, 3 bytes
                ENDM

;       meta CREATE

$CREATE 	MACRO	ALIAS, NAME
		$CODE	ALIAS, NAME
		CALL	DOVAR		;;7+2 clocks, 3 bytes
		ENDM

;	meta USES

$USES		MACRO	CODE
_HERE		=	$
		ORG	_LAST+_SIZE+1	;;to ca of the last word
		CALL	CODE		;;7+m clocks, 3 bytes
		ORG	_HERE
		ENDM

;	meta (;CODE)

$PSCODE 	MACRO
		LOCAL	_HERE
_HERE		LABEL	NEAR
		$USES	_HERE
		ENDM

;	introduce a label

$LABEL          MACRO   ALIAS
ALIAS           LABEL   NEAR
                ENDM

;       meta IMMEDIATE

$IMMEDIATE	MACRO
_HERE		=	$
		ORG	_LAST
		DB	_IMME+_SIZE
		ORG	_HERE
		ENDM

;	meta "

$$              MACRO   STRING
		DW	LITQ
_HEAD           =       $
                DB      ?, STRING
_HERE           =       $
                ORG     _HEAD
                DB      _HERE-_HEAD-1
                ORG     _HERE
                ENDM

;       NEXT interpreter

NEXT		MACRO
		LODSW			;;5 clocks, 1 byte
		JMP	AX		;;7+m clocks, 2 bytes
		ENDM

;	output a message during assembly

$ECHO		MACRO	S1, S2, S3, S4, S5, S6, S7, S8, S9
		IF2
		%OUT	S1&S2&S3&S4&S5&S6&S7&S8&S9
		ENDIF
		ENDM

                ENDIF

;; vocabularies

$VOCAB		$ONLY
$VOCAB		$FORTH

;; starting FORTH

MAIN		SEGMENT
		ASSUME	CS:MAIN, DS:MAIN, SS:MAIN

		ORG	100H

_START: 	JMP	BOOT

;; internal system variables

		ORG	_START

		EVEN
OLD_INT0	DD	1 DUP (?)	;interrupt vector for int0

;; room for the initial values (if any) of user variables
;; COLD start moves these to the user area

                EVEN
_UZERO		EQU	$
_RESU		=	0
_USER		=	_USIZE

		IFDEF	USERSIZE
		IF2
.ERRNZ		_USIZE GT USERSIZE
		ENDIF
		ORG	_UZERO+USERSIZE
		ELSE
		ORG	_UZERO+_US
		ENDIF

		$FORTH			;FORTH DEFINITIONS

;; nuclei

; null word	( -- )
;		FIND finds this word in case of null string
;		facilitates the exit from an infinite loop containing
;		BL WORD FIND EXECUTE
		DW	0
NULL:		DB	_IMME
		JMP	SHORT EXIT

; EXIT		( -- )
;               or unnest
;               may not be used within DO/?DO-LOOP/+LOOP
		$CODE	EXIT, 'EXIT'
                MOV     SI, [BP]
                INC     BP
                INC     BP              ;increment by a cell
                NEXT

; UP            ( -- a )
;		pointer to the user area
;		assumes on RAM
		$CREATE UP, 'UP'
UP_		DW	_UP

; douse         ( -- a ) for compilation only
;		: douse SWAP @ UP @ + ;
		$LABEL	DOUSE
		POP	DI
		PUSH	BX
		MOV	BX, [DI]	;read user area offset
		ADD	BX, UP_ 	;add user area pointer
		NEXT

; lit		( -- w ) for compilation only
;		pushes the following inline number onto stack
;		: lit R> DUP CELL+ >R @ ;
		$CODE	LIT, 'lit'
		PUSH	BX
		LODSW
		MOV	BX, AX
		NEXT

; dlit		( -- wd ) for compilation only
;		: dlit R> DUP CELL+ CELL+ >R 2@ ;
		$CODE	DLIT, 'dlit'
		PUSH	BX
		LODSW
		MOV	BX, AX
		LODSW
		PUSH	AX
		NEXT

; litq		( -- $ ) for compilation only
;               or (")
;               returns the address of the following inline packed string
                $COLON  LITQ, 'litq'
		DW	RFROM, DUPE, COUNT, PLUS, TOR, EXIT

;; words dependent on system calls

; BYE		( -- )
;		: BYE ( from ZEN ) 0 EXECUTE ;
		$CODE	BYE, 'BYE'
		LDS	DX, OLD_INT0
		MOV	AX, 2500H
		INT	21H
		INT	20H

; (?KEY)	( -- f )
;		checks keyboard input status
		$CODE	PQKEY, '(?KEY)'
		PUSH	BX
		MOV	AH, 11
		INT	21H
		CBW			;or MOV  AH, AL
		MOV	BX, AX
		NEXT

; (KEY) 	( -- c )
;		keyboard input without echo
;		special keys are returned in high byte with low byte zeroed
;		w/o calling multitasking hook
		$CODE	PKEY, '(KEY)'
		PUSH	BX
		MOV	AH, 8
		INT	21H
		SUB	BX, BX		;or SUB  BH, BH
		MOV	BL, AL
                OR      AL, AL
		JNZ	@F
		INT	21H
		MOV	BH, AL
@@:		NEXT

; SEMIT 	( c -- )
;		writes c as teletype (TTY) mode
		$CODE	SEMIT, 'SEMIT'
		MOV	AH, 15
		INT	10H		;BH = current display page number
		MOV	AX, BX		;or MOV  AL, BL
		MOV	AH, 14
		INT	10H
		POP	BX
		NEXT

;; flow-control

; branch	( -- ) for compilation only
;		unconditional branch
;		: branch R> @ >R ;
		$CODE	BRANCH, 'branch'
		MOV	SI, [SI]
		NEXT

; ?branch	( f -- ) for compilation only
;		branches if zero
		$CODE	QBRANCH, '?branch'
		OR	BX, BX
		POP	BX
		JZ	BRANCH
		INC	SI
		INC	SI		;jump over the address
		NEXT

; loop		( -- ) for compilation only
		$CODE	LOOPP, 'loop'
		INC	WORD PTR [BP]
		JNO	BRANCH
LOOP1:		INC	SI
		INC	SI		;jump over the address
		ADD	BP, 2*_CELL
		NEXT

; +loop 	( n -- ) for compilation only
		$CODE	PLOOP, '+loop'
		ADD	[BP], BX
		POP	BX
		JNO	BRANCH
		JMP	SHORT LOOP1

; do		( n1 n2 -- ) for compilation only
;		not followed by inline jump address
		$CODE	DO, 'do'
		POP	AX
DO1:		XCHG	BP, SP
		ADD	AX, 8000H	;or SUB  AX, 8000H
		SUB	BX, AX
		PUSH	AX		;= n1-8000h
		PUSH	BX		;= n2-(n1-8000h)
		XCHG	BP, SP
		POP	BX
		NEXT

; ?do		( n1 n2 -- ) for compilation only
		$CODE	QDO, '?do'
		POP	AX
		INC	SI
		INC	SI		;jump over the address
		CMP	AX, BX
		JNE	DO1
		POP	BX
		MOV	SI, [SI-_CELL]
		NEXT

; GOTO		( -- ) for compilation only
;		forces the nesting word to terminate and executes the following
;		word directly so that it may seem to be the nesting word
;		$CODE	GOTO, 'GOTO'
;		LODSW
;		MOV	SI, [BP]
;		INC	BP
;		INC	BP		;increment by a cell
;		JMP	AX

; EXECUTE	( ca -- )
		$CODE	EXECUTE, 'EXECUTE'
		POP	AX
		XCHG	BX, AX
		JMP	AX

; PERFORM	( a -- )
;		or @EXECUTE
;		: PERFORM @ EXECUTE ;
		$CODE	PERFORM, 'PERFORM'
		MOV	AX, [BX]
		POP	BX
		JMP	AX

;; 16 bit return stack operations

; RP0		( -- a )
;		or R0
		$USER	RP0, 'RP0'
		DW	_RP0
		$RESU

; RP@		( -- a )
		$CODE	RPAT, 'RP@'
		PUSH	BX
		MOV	BX, BP
		NEXT

; RP!		( a -- ) for compilation only
		$CODE	RPSTORE, 'RP!'
		MOV	BP, BX
		POP	BX
		NEXT

; >R		( w -- ) for compilation only
		$CODE	TOR, '>R'
		DEC	BP
		DEC	BP		;decrement by a cell
		MOV	[BP], BX
		POP	BX
		NEXT

; R@		( -- w )
		$CODE	RAT, 'R@'
		PUSH	BX
		MOV	BX, [BP]
		NEXT

; R>		( -- w ) for compilation only
		$CODE	RFROM, 'R>'
		PUSH	BX
		MOV	BX, [BP]
		INC	BP
		INC	BP		;increment by a cell
		NEXT

;; 32 bit return stack operations

; 2>R		( w1 w2 -- ) for compilation only
;		pushes w1 and w2 to return stack, w2 on top
		$CODE	DTOR, '2>R'
		SUB	BP, 2*_CELL
		MOV	[BP], BX
		POP	[BP+_CELL]
		POP	BX
		NEXT

; 2R>		( -- w1 w2 ) for compilation only
		$CODE	DRFROM, '2R>'
		PUSH	BX
		PUSH	[BP+_CELL]
		MOV	BX, [BP]
		ADD	BP, 2*_CELL
		NEXT

;; 16 bit data stack operations

; SP0		( -- a )
;		or S0
		$USER	SP0, 'SP0'
		DW	_SP0
		$RESU

; SP@		( -- a )
		$CODE	SPAT, 'SP@'
		PUSH	BX
		MOV	BX, SP
		NEXT

; SP!		( a -- )
		$CODE	SPSTORE, 'SP!'
		MOV	SP, BX
		POP	BX
		NEXT

; DUP		( w -- w w )
;		: DUP >R R@ R> ;
		$CODE	DUPE, 'DUP'
		PUSH	BX
		NEXT

; DROP		( w -- )
		$CODE	DROP, 'DROP'
		POP	BX
		NEXT

; SWAP		( w1 w2 -- w2 w1 )
;		: SWAP 2>R R> R> ;
		$CODE	SWAP, 'SWAP'
		MOV	DI, SP
		XCHG	[DI], BX
		NEXT

; OVER		( w1 w2 -- w1 w2 w1 )
;		: OVER >R DUP R> SWAP ;
		$CODE	OVER, 'OVER'
		MOV	DI, SP
		PUSH	BX
		MOV	BX, [DI]
		NEXT

; ROT		( w1 w2 w3 -- w2 w3 w1 )
;		: ROT >R SWAP R> SWAP ;
		$CODE	ROT, 'ROT'
		POP	DX
		POP	AX
		PUSH	DX
		PUSH	BX
		MOV	BX, AX
		NEXT

; ?DUP		( w -- w w, 0 )
;		: ?DUP DUP IF DUP THEN ;
		$CODE	QDUP, '?DUP'
		OR	BX, BX
		JNZ	DUPE
		NEXT

; NIP		( w1 w2 -- w2 )
;		: NIP SWAP DROP ;
		$CODE	NIP, 'NIP'
		INC	SP
		INC	SP		;increment by a cell
		NEXT

; TUCK		( w1 w2 -- w2 w1 w2 )
;		: TUCK SWAP OVER ;
		$CODE	TUCK, 'TUCK'
		POP	AX
		PUSH	BX
		PUSH	AX
		NEXT

;; 32 bit data stack operations

; 2DUP		( wd -- wd wd )
;		: 2DUP OVER OVER ;
		$CODE	DDUP, '2DUP'
		MOV	DI, SP
		PUSH	BX
		PUSH	[DI]
		NEXT

; 2DROP 	( wd -- )
;		: 2DROP DROP DROP ;
		$CODE	DDROP, '2DROP'
		INC	SP
		INC	SP		;increment by a cell
		POP	BX
		NEXT

;; 16 bit bitwise/logical operations

; TRUE		( -- -1 )
;		or -1
		$CONST	TRUE, 'TRUE'
		DW	-1

; AND		( w1 w2 -- w3 )
		$CODE	ANDD, 'AND'
		POP	AX
		AND	BX, AX
		NEXT

; OR		( w1 w2 -- w3 )
		$CODE	ORR, 'OR'
		POP	AX
		OR	BX, AX
		NEXT

; XOR		( w1 w2 -- w3 )
		$CODE	XORR, 'XOR'
		POP	AX
		XOR	BX, AX
		NEXT

; NOT		( w1 -- w2 )
;		one's complement of tos
;		: NOT -1 XOR ;
		$CODE	NOTT, 'NOT'
		NOT	BX
		NEXT

;; 16 bit comparison operations

; 0=		( n -- f )
;		logical not
;		: 0= IF 0 ELSE TRUE THEN ;
		$CODE	ZEQUAL, '0='
		SUB	BX, 1
		SBB	BX, BX
		NEXT

; =		( n1 n2 -- f )
;		: = XOR 0= ;
		$CODE	EQUAL, '='
		POP	AX
		SUB	AX, BX
		SUB	AX, 1
		SBB	BX, BX
		NEXT

; 0<		( n -- f )
		$CODE	ZLESS, '0<'
                SHL     BX, 1
                SBB     BX, BX
                NEXT

; <             ( n1 n2 -- f )
;		: < 2DUP XOR 0< IF DROP ELSE - THEN 0< ;
		$CODE	LESS, '<'
		POP	AX
		CMP	AX, BX
		MOV	BX, -1
		JL	@F
		INC	BX
@@:		NEXT

; U<		( u1 u2 -- f )
;		: U< 2DUP XOR 0< IF NIP ELSE - THEN 0< ;
		$CODE	ULESS, 'U<'
		POP	AX
		SUB	AX, BX
		SBB	BX, BX
		NEXT

; MAX		( n1 n2 -- n3 )
;		: MAX ( from ZEN ) 2DUP < IF SWAP THEN DROP ;
		$CODE	MAX, 'MAX'
		POP	AX
		CMP	AX, BX
		JLE	@F
		MOV	BX, AX
@@:		NEXT

; MIN		( n1 n2 -- n3 )
		$CODE	MIN, 'MIN'
		POP	AX
		CMP	AX, BX
		JGE	@F
		MOV	BX, AX
@@:             NEXT

; WITHIN	( n l h -- f )
;		true if l <= n < h given circular comparison
;		false whenever l = h
;		: WITHIN ( from ZEN ) OVER - >R - R> U< ;
;		: BETWEEN ( from Pygmy ) OVER - >R - R> SWAP U< NOT ;
;		: WITHIN ( from Pygmy ) 1- BETWEEN ;
;		all other comparison operators can be based on WITHIN
;		: U< ( u1 u2 -- f ) 0 SWAP WITHIN ;
;		: < ( n1 n2 -- f ) -32768 SWAP WITHIN ;
;		: 0< ( n -- f ) -32768 0 WITHIN ;
;		: = ( n1 n2 -- f ) DUP 1+ WITHIN ;
;		: 0= ( n -- f ) 0 1 WITHIN ;
		$CODE	WITHIN, 'WITHIN'
		POP	DX		;DX = l
		POP	AX
		SUB	AX, DX		;AX = n-l
		SUB	BX, DX		;BX = h-l
		SUB	AX, BX		;CY if n-l U< h-l
		SBB	BX, BX
		NEXT

;; 16 bit arithmetic operations

; 0		( -- 0 )
		$CODE	ZERO, '0'
		PUSH	BX
		SUB	BX, BX
		NEXT

; 1		( -- 1 )
		$CODE	ONE, '1'
		PUSH	BX
		MOV	BX, 1
		NEXT

; NEGATE	( n1 -- n2 )
;		two's complement of tos
;		: NEGATE NOT 1+ ;
		$CODE	NEGATE, 'NEGATE'
		NEG	BX
		NEXT

; ABS		( n1 -- +n2 )
;		: ABS DUP 0< IF NEGATE THEN ;
		$CODE	ABS, 'ABS'
		OR	BX, BX
		JS	NEGATE
		NEXT

; +		( n1 n2 -- n3 )
;		: + UM+ DROP ;
		$CODE	PLUS, '+'
		POP	AX
		ADD	BX, AX
		NEXT

; -		( n1 n2 -- n3 )
;		: - NEGATE + ;
		$CODE	MINUS, '-'
		POP	AX
		SUB	AX, BX
		MOV	BX, AX
		NEXT

; 1+		( n1 -- n2 )
;		: 1+ 1 + ;
		$CODE	ONEP, '1+'
		INC	BX
		NEXT

; 1-		( n1 -- n2 )
;		: 1- 1 - ;
		$CODE	ONEM, '1-'
		DEC	BX
		NEXT

;; 32 bit arithmetic operations

; DNEGATE	( d1 -- d2 )
;		: DNEGATE NOT >R NOT 1 UM+ R> + ;
		$CODE	DNEGATE, 'DNEGATE'
		POP	AX
		NEG	AX
		PUSH	AX
		ADC	BX, 0
		NEG	BX
		NEXT

; DABS		( d1 -- +d2 )
		$CODE	DABS, 'DABS'
		OR	BX, BX
		JS	DNEGATE
		NEXT

; S>D           ( n -- d )
;		: S>D DUP 0< ;
		$CODE	STOD, 'S>D'
		PUSH	BX
		SHL	BX, 1
                SBB     BX, BX
                NEXT

; D>S		( d -- n )
;		: D>S DROP ;

; D+		( d1 d2 -- d3 )
;		: D+ >R SWAP >R UM+ 2R> + + ;
		$CODE	DPLUS, 'D+'
		POP	AX
		POP	DX
		POP	CX
		ADD	AX, CX
		PUSH	AX
		ADC	BX, DX
		NEXT

;; mixed mode arithmetic

; UM*		( u1 u2 -- ud )
;		: UM* ( from eForth )
;		  0 SWAP ( u1 0 u2 ) 16 0
;		  DO DUP UM+ >R >R DUP UM+ R> + R>
;		    IF >R OVER UM+ R> + THEN
;		  LOOP ROT DROP ;
		$CODE	UMSTAR, 'UM*'
		POP	AX
		MUL	BX
		PUSH	AX
		MOV	BX, DX
		NEXT

; M*		( n1 n2 -- d )
;		: M* ( from eForth )
;		  2DUP XOR 0< >R
;		  ABS SWAP ABS UM*
;		  R> IF DNEGATE THEN ;
;		$CODE	MSTAR, 'M*'
;		POP	AX
;		IMUL	BX
;		PUSH	AX
;		MOV	BX, DX
;		NEXT

; UM/MOD	( ud u -- ur uq )
;		on zero-divide or overflow, int0 occurs
;		: UM/MOD ( from eForth )
;		  2DUP U<
;		  IF NEGATE 16 0
;		    DO >R DUP UM+ >R >R DUP UM+ R> + DUP
;		      R> R@ SWAP >R UM+ R> OR
;		      IF >R DROP 1+ R> ELSE DROP THEN R>
;		    LOOP DROP SWAP EXIT
;		  THEN DROP 2DROP -1 DUP ;
		$CODE	UMSMOD, 'UM/MOD'
		POP	DX
		POP	AX
		DIV	BX
UMSMOD1:	PUSH	DX
		MOV	BX, AX
		NEXT

; M/MOD 	( d n -- r q )
;		signed floored mixed-precision divide
;		on zero-divide or overflow, int0 occurs
;		: M/MOD ( floored ) ( from eForth )
;		  DUP 0< DUP >R
;		  IF NEGATE >R DNEGATE R> THEN
;		  >R DUP 0< IF R@ + THEN R> UM/MOD R>
;		  IF SWAP NEGATE SWAP THEN ;
;		: M/MOD ( rounded-down ) ( from ZEN )
;		  2DUP XOR >R OVER >R ABS >R DABS R> UM/MOD
;		  SWAP R> 0< IF NEGATE THEN
;		  SWAP R> 0< IF NEGATE THEN ;
		$CODE	MSMOD, 'M/MOD'
		POP	DX
		POP	AX
		MOV	CX, DX
		IDIV	BX
		XOR	CX, BX
		JNS	UMSMOD1
		OR	DX, DX
		JZ	UMSMOD1
		ADD	DX, BX
		DEC	AX
		JNO	UMSMOD1
		INT	0

;; pointer arithmetic

; CELL+ 	( a1 -- a2 )
;		or 2+
;		: CELL+ 1+ 1+ ;
		$CODE	CELLP, 'CELL+'
		INC	BX
		INC	BX		;increment by a cell
		NEXT

; CELL- 	( a1 -- a2 )
;		or 2-
;		: CELL- 1- 1- ;
		$CODE	CELLM, 'CELL-'
		DEC	BX
		DEC	BX		;decrement by a cell
		NEXT

; CELLS 	( a1 -- a2 )
;		or 2*
;		: CELLS 2 * ;
		$CODE	CELLS, 'CELLS'
		SAL	BX, 1		;multiplication by _CELL
		NEXT

; EVEN          ( a1 -- a2 )
;		: EVEN DUP 1 AND + ;

;; 16 and 8 bit memory operations

; @		( a -- w )
		$CODE	AT, '@'
		MOV	BX, [BX]
		NEXT

; C@		( a -- c )
		$CODE	CAT, 'C@'
		MOV	BL, [BX]
		SUB	BH, BH
		NEXT

; !		( w a -- )
		$CODE	STORE, '!'
		POP	[BX]
		POP	BX
		NEXT

; C!		( c a -- )
		$CODE	CSTORE, 'C!'
		POP	AX
		MOV	[BX], AL
		POP	BX
		NEXT

; +!		( n a -- )
;		: +! TUCK @ + SWAP ! ;
		$CODE	PSTORE, '+!'
		POP	AX
		ADD	[BX], AX
		POP	BX
		NEXT

; OFF		( a -- )
;		: OFF 0 SWAP ! ;
		$CODE	OFF, 'OFF'
		SUB	AX, AX
		MOV	[BX], AX	;or MOV  WORD PTR [BX], 0
		POP	BX
		NEXT

;; 32 bit memory operations

; 2@		( a -- wd )
;		: 2@ DUP CELL+ @ SWAP @ ;
		$CODE	DAT, '2@'
		PUSH	[BX+_CELL]	;low word of wd
		MOV	BX, [BX]
		NEXT

; 2!		( wd a -- )
;		: 2! TUCK ! CELL+ ! ;
		$CODE	DSTORE, '2!'
		POP	[BX]
		POP	[BX+_CELL]	;low word of wd
		POP	BX
		NEXT

;; block memory operations

; CMOVE 	( a1 a2 u -- )
;		moves u bytes from a1 to a2, leftmost byte first
;		does nothing if zero length
;		: CMOVE 0 ?DO >R DUP C@ R@ C! 1+ R> 1+ LOOP 2DROP ;
		$CODE	CMOVE, 'CMOVE'
		POP	DI
		MOV	AX, DS
		MOV	ES, AX		;ES is free
		MOV	CX, BX
		MOV	AX, SI		;save SI
		POP	SI
		REP	MOVSB
		POP	BX
		MOV	SI, AX		;restore SI
		NEXT

; CMOVE>	( a1 a2 u -- )
;		moves u bytes from a1 to a2, rightmost byte first
;		does nothing if zero length
;		: CMOVE> ( from ZEN ) DUP DUP >R D+ R>
;		  0 ?DO 1- SWAP 1- TUCK C@ OVER C! LOOP 2DROP ;
		$CODE	CMOVETO, 'CMOVE>'
		POP	DI
                MOV     AX, DS
		MOV	ES, AX		;ES is free
		MOV	CX, BX
                MOV     AX, SI          ;save SI
                POP     SI
		DEC	BX
                ADD     SI, BX
		ADD	DI, BX
		STD
                REP     MOVSB
		CLD
		POP	BX
		MOV	SI, AX		;restore SI
		NEXT

; MOVE		( a1 a2 u -- )
;		moves u bytes from a1 to a2 without overlap
;               does nothing if zero length
;		: MOVE ( from ZEN )
;		  >R 2DUP U< IF R> CMOVE> ELSE R> CMOVE THEN ;

; FILL		( a u c -- )
;		stores u c's, starting at addr a
;		does nothing if zero length
;		: FILL ( from ZEN ) SWAP ?DUP
;		  IF >R OVER C! DUP 1+ R> 1- CMOVE ELSE 2DROP THEN ;
		$CODE	FILL, 'FILL'
		POP	CX
		POP	DI
		MOV	AX, DS
		MOV	ES, AX		;ES is free
		MOV	AX, BX
		REP	STOSB
		POP	BX
		NEXT

; ERASE 	( a u -- )
;		: ERASE 0 FILL ;

; BLANK 	( a u -- )
;               : BLANK BL FILL ;

;; string operations

; COUNT 	( $ -- a u )
;		transforms packed string into text string
;		: COUNT DUP 1+ SWAP C@ ;
		$CODE	COUNT, 'COUNT'
		INC	BX
		PUSH	BX
		MOV	BL, [BX-1]
		SUB	BH, BH
		NEXT

; /STRING	( a1 u1 n -- a2 u2 )
;		truncates leftmost n chars of string
;		: /STRING OVER MIN TUCK - >R + R> ;
		$CODE	SSTRING, '/STRING'
		POP	AX
		CMP	AX, BX
		JGE	@F
		MOV	BX, AX
@@:		POP	DX
		ADD	DX, BX
		PUSH	DX
		SUB	AX, BX
		MOV	BX, AX
		NEXT

; SKIP		( a1 u1 c -- a2 u2 )
;		returns shorter string from first position unequal to c
;		returns null string if not found
;		: SKIP >R
;		  BEGIN DUP
;		  WHILE OVER C@ R@ = WHILE 1 /STRING
;		  REPEAT THEN R> DROP ;
		$CODE	SKIP, 'SKIP'
		POP	CX
		JCXZ	SKIP2
		POP	DI
		MOV	AX, DS
		MOV	ES, AX		;ES is free
		MOV	AX, BX
		REPE	SCASB
		JZ	SKIP1
		INC	CX
		DEC	DI
SKIP1:		PUSH	DI
SKIP2:		MOV	BX, CX
		NEXT

; SCAN		( a1 u1 c -- a2 u2 )
;		returns shorter string from first position equal to c
;		returns null string if not found
;		: SCAN >R
;		  BEGIN DUP
;		  WHILE OVER C@ R@ XOR WHILE 1 /STRING
;		  REPEAT THEN R> DROP ;
		$CODE	SCAN, 'SCAN'
		POP	CX
		JCXZ	SCAN2
		POP	DI
		MOV	AX, DS
		MOV	ES, AX		;ES is free
		MOV	AX, BX
		REPNE	SCASB
		JNZ	SCAN1
		INC	CX
		DEC	DI
SCAN1:		PUSH	DI
SCAN2:		MOV	BX, CX
		NEXT

;; basic I/O

; '?KEY         ( -- a )
;               execution vector of ?KEY
                $USER   TQKEY, "'?KEY"
                DW      PQKEY
                $RESU

; ?KEY          ( -- f )
                $COLON  QKEY, '?KEY'
                DW      TQKEY, PERFORM, EXIT

; 'KEY          ( -- a )
;               execution vector of KEY
                $USER   TKEY, "'KEY"
                DW      PKEY
                $RESU

; KEY           ( -- c )
                $COLON  KEY, 'KEY'
                DW      TKEY, PERFORM, EXIT

; 'EMIT         ( -- a )
;               execution vector of EMIT
;		does not need initializing unless COLD prints any message
                $USER   TEMIT, "'EMIT"
                DW      SEMIT
                $RESU

; EMIT          ( c -- )
                $COLON  EMIT, 'EMIT'
                DW      TEMIT, PERFORM, EXIT

; CONSOLE       ( -- )
;               initializes the output device to the terminal
                $COLON  CONSOLE, 'CONSOLE'
                DW      LIT, SEMIT, TEMIT, STORE, EXIT

; BL            ( -- 32 )
                $CONST  BLL, 'BL'
                DW      ' '

; SPACE         ( -- )
                $COLON  SPACE, 'SPACE'
                DW      BLL, EMIT, EXIT

; SPACES        ( n -- )
;		does nothing unless n is positive
;		: SPACES 0 MAX 0 ?DO SPACE LOOP ;
                $COLON  SPACES, 'SPACES'
		DW	ZERO, MAX, ZERO, QDO, SPACES2
SPACES1:	DW	SPACE, LOOPP, SPACES1
SPACES2:	DW	EXIT

; CR            ( -- )
                $COLON  CR, 'CR'
                DW      LIT, _CR, EMIT
                DW      LIT, _LF, EMIT, EXIT

; TYPE          ( a u -- )
;               outputs u characters from a
;               does nothing if zero length
;		: TYPE 0 ?DO COUNT EMIT LOOP DROP ;
                $COLON  TYPES, 'TYPE'
                DW      ZERO, QDO, TYPES2
TYPES1:         DW      COUNT, EMIT, LOOPP, TYPES1
TYPES2:         DW      DROP, EXIT

; TYPE$         ( $ -- )
;               or dotq
;               need not be a compilation-only word
                $COLON  TYPE$, 'TYPE$'
                DW      COUNT, TYPES, EXIT

;; numeric output string (pictured numeric output)

; BASE		( -- a )
		USER$	BASE, 'BASE'

; HEX		( -- )
		$COLON	HEX, 'HEX'
		DW	LIT, 16, BASE, STORE, EXIT

; DECIMAL	( -- )
		$COLON	DECIMAL, 'DECIMAL'
		DW	LIT, 10, BASE, STORE, EXIT

; PAD		( -- a )
		$COLON	PAD, 'PAD'
		DW	HERE, LIT, _PAD, PLUS, EXIT

; HLD		( -- a )
		USER$	HLD, 'HLD'

; HOLD		( c -- )
;		adds character c to numeric output string
;		may only be used between <# and #>
;		: HOLD ( from eForth ) HLD @ 1- DUP HLD ! C! ;
		$COLON	HOLD, 'HOLD'
		DW	TRUE, HLD, PSTORE
		DW	HLD, AT, CSTORE, EXIT

; SIGN		( n -- )
;		adds '-' to numeric output string if n is negative
		$COLON	SIGN, 'SIGN'
		DW	ZLESS, QBRANCH, @F, LIT, '-', HOLD
@@:		DW	EXIT

; <#		( -- )
;		initializes numeric output string
		$COLON	BDIG, '<#'
		DW	PAD, HLD, STORE, EXIT

; #		( ud1 -- ud2 )
;		transfers the next digit of ud1 to numeric output string
;		: MU/MOD ( d n -- r dq ) ( from Laxen's F83 )
;		  >R 0 R@ UM/MOD R> SWAP >R UM/MOD R> ;
;		: # ( ud1 -- ud2 ) ( from Laxen's F83 )
;		  BASE @ MU/MOD ROT 9 OVER < IF 7 + THEN [ASCII] 0 + HOLD ;
		$COLON	DIG, '#'
		DW	BASE, AT, TOR, ZERO, RAT, UMSMOD
		DW	RFROM, SWAP, TOR, UMSMOD, RFROM
		DW	ROT, LIT, 9, OVER, LESS
		DW	LIT, 'A'-('9'+1), ANDD, PLUS
		DW	LIT, '0', PLUS, HOLD, EXIT

; #S		( ud1 -- ud2 )
;		transfers all remaining digits of ud1, then ud2 is 0 0
		$COLON	DIGS, '#S'
@@:		DW	DIG, DDUP, ORR, ZEQUAL
		DW	QBRANCH, @B, EXIT

; #>		( wd -- a u )
;		ends numeric output conversion, returns the string
		$COLON	EDIG, '#>'
		DW	DDROP, HLD, AT, PAD, OVER, MINUS, EXIT

;; number output

; D.R           ( d n -- )
                $COLON  DDOTR, 'D.R'
                DW      TOR, TUCK, DABS, BDIG, DIGS, ROT, SIGN, EDIG
                DW      RFROM, OVER, MINUS, SPACES, TYPES, EXIT

; D.            ( d -- )
                $COLON  DDOT, 'D.'
                DW      ZERO, DDOTR, SPACE, EXIT

; .             ( n -- )
                $COLON  DOT, '.'
                DW      STOD, DDOT, EXIT

; U.            ( u -- )
                $COLON  UDOT, 'U.'
                DW      ZERO, DDOT, EXIT

;; input number conversion

; DIGIT 	( c base -- u T, F )
;		converts a character to its numeric value
;		: DIGIT ( c base -- u f ) ( from eForth )
;		  >R [ASCII] 0 - 9 OVER <
;		  IF 7 - DUP 10 < OR THEN DUP R> U< ;
		$CODE	DIGIT, 'DIGIT'
		POP	AX		;AL = c
		SUB	AL, '0'
		JB	DIGIT2		;if c < '0'
		CMP	AL, 9
		JBE	DIGIT1		;if '0' <= c <= '9'
		SUB	AL, 'A'-('9'+1)
		CMP	AL, 10
		JB	DIGIT2		;if '9' < c < 'A'
DIGIT1: 	CMP	AL, BL
		CMC
		JB	DIGIT2		;if AL >= base
		SUB	AH, AH
		PUSH	AX
DIGIT2: 	CMC
		SBB	BX, BX
		NEXT

; CONVERT	( +d1 a1 -- +d2 a2 )
;		converts the char sequence at a1+1 and accumulates it in +d1
;		continues until an unconvertible char is encountered
;		a2 is the address of the first unconvertible digit
;		: CONVERT
;		  BEGIN 1+ DUP >R C@ BASE @ DIGIT
;		  WHILE SWAP BASE @ UM* DROP ROT BASE @ UM* D+ R>
;		  REPEAT R> ;
		$COLON	CONVERT, 'CONVERT'
@@:		DW	ONEP, DUPE, TOR, CAT, BASE, AT, DIGIT, QBRANCH, @F
		DW	SWAP, BASE, AT, UMSTAR, DROP
		DW	ROT, BASE, AT, UMSTAR, DPLUS, RFROM, BRANCH, @B
@@:		DW	RFROM, EXIT

; DPL		( -- a )
		USER$	DPL, 'DPL'

; (NUMBER?)	( a -- d f )
;		converts the string at a+1 to a double number using BASE
;		string must be followed by a SPACE or HEX 00
;		string may have a leading minus sign, but not any plus sign
;		recognizes as a hex number if the string begins with $
;		sets DPL = -1 if no decimal in the string
;		otherwise DPL is set to #digits to the right of the decimal
;		: (NUMBER?)
;		  TRUE DPL ! ( DPL ON ) BASE @ >R ( a ; base )
;		  DUP 1+ C@ [ASCII] - = DUP >R -
;		  DUP 1+ C@ [ASCII] $ = IF HEX 1+ THEN
;		  ( a ; base f ) 0 0 ROT CONVERT ( +d a ; base f )
;		  DUP C@ [ASCII] . =
;		  IF ( +d a ; base f ) DUP >R ( +d a ; base f a )
;		    CONVERT ( +d a' ; base f a )
;		    DUP R> - 1- ( +d a' a'-a-1 ; base f )
;		    DPL ! ( +d a ; base f )
;		  THEN R> ( +d a f ; base )
;		  IF >R DNEGATE R> THEN ( d a ; base )
;		  R> BASE ! ( d a )
;		  C@ DUP ( d c c ) BL = SWAP ( d f1 c ) 0= ( d f1 f2 )
;		  OR ( d f ) ;
		$COLON	PNUMBERQ, '(NUMBER?)'
		DW	TRUE, DPL, STORE, BASE, AT, TOR
		DW	DUPE, ONEP, CAT, LIT, '-', EQUAL
		DW	DUPE, TOR, MINUS
		DW	DUPE, ONEP, CAT, LIT, '$', EQUAL
		DW	QBRANCH, @F, HEX, ONEP
@@:		DW	ZERO, ZERO, ROT, CONVERT
		DW	DUPE, CAT, LIT, '.', EQUAL
		DW	QBRANCH, @F, DUPE, TOR, CONVERT
		DW	DUPE, RFROM, MINUS, ONEM, DPL, STORE
@@:		DW	RFROM, QBRANCH, @F, TOR, DNEGATE, RFROM
@@:		DW	RFROM, BASE, STORE
		DW	CAT, DUPE, BLL, EQUAL, SWAP, ZEQUAL
		DW	ORR, EXIT

; 'NUMBER?      ( -- a )
;		execution vector of NUMBER?
		$USER	TNUMBERQ, "'NUMBER?"
		DW	PNUMBERQ
		$RESU

; NUMBER?	( a -- d f )
		$COLON	NUMBERQ, 'NUMBER?'
		DW	TNUMBERQ, PERFORM, EXIT

;; parsing

; source	( -- a )
;		the number of characters and the address of the input stream
		USER$	XSOURCE, 'source'
_USER		=	_USER+_CELL

; SOURCE	( -- a u )
;		input stream source
		$COLON	SOURCE, 'SOURCE'
		DW	XSOURCE, DAT, EXIT

; >IN		( -- a )
;		the present character offset within the input stream
		USER$	TOIN, '>IN'

; PARSE         ( c -- a u )
;		parses a character-delimited string
;		delimiter(if found) is not counted into u
;		: PARSE >R SOURCE >IN @ /STRING ( a u ; c )
;		  OVER SWAP R> ( a a u c ) SCAN ( a a' u' )
;		  DROP OVER - ( a a'-a ) DUP 1+ >IN +! ( a a'-a ) ;
		$COLON	PARSE, 'PARSE'
		DW	TOR, SOURCE, TOIN, AT, SSTRING
		DW	OVER, SWAP, RFROM, SCAN, DROP
		DW	OVER, MINUS, DUPE, ONEP, TOIN, PSTORE, EXIT

; WORD		( c -- $ )
;		parses the next word in the input stream
;		accepts 31 chars at maximum; the rest are accepted but ignored
;		leading delimiters are skipped
;		the chars are stored at HERE as a packed string
;		the packed string is followed by a blank(not counted)
;		returns null string if the input stream is already exhausted
;		: WORD >R SOURCE >IN @ /STRING ( a u ; c )
;		  OVER SWAP R@ ( a a u c ; c ) SKIP ( a a' u' ; c )
;		  OVER SWAP R> ( a a' a' u' c ) SCAN ( a a' a" u" )
;		  DROP TUCK ( a a" a' a" ) OVER - ( a a" a' a"-a' )
;		  31 MIN HERE ( a a" a' # h ) 2DUP C! ( a a" a' # h )
;		  1+ SWAP ( a a" a' h+1 # ) CMOVE ( a a" )
;		  BL HERE COUNT + ( a a" 32 h+1+# ) C! ( a a" )
;		  SWAP - 1+ ( a"-a+1 ) >IN +! ( ) HERE ( h ) ;
		$COLON	WORDD, 'WORD'
		DW	TOR, SOURCE, TOIN, AT, SSTRING
		DW	OVER, SWAP, RAT, SKIP
		DW	OVER, SWAP, RFROM, SCAN
		DW	DROP, TUCK, OVER, MINUS
		DW	LIT, _MASK, MIN, HERE
		DW	DDUP, CSTORE, ONEP, SWAP, CMOVE
		DW	BLL, HERE, COUNT, PLUS, CSTORE
		DW	SWAP, MINUS, ONEP, TOIN, PSTORE
		DW	HERE, EXIT

;; the line editor

; SPAN          ( -- a )
;               the number of characters received by EXPECT
                USER$   SPAN, 'SPAN'

; EXPECT        ( a u -- )
;               accepts upto u chars into address and stores count in SPAN
;               : EXPECT
;                 >R 0 ( a 0 )
;                 BEGIN DUP R@ <
;                 WHILE KEY DUP 13 ( _CR ) XOR
;                 WHILE DUP 8 ( _BS ) =
;                   IF DROP DUP IF 1- 8 EMIT SPACE 8 EMIT THEN
;                   ELSE >R 2DUP + R> TUCK EMIT C! 1+
;                   THEN
;                 REPEAT DROP
;                 THEN SPAN ! R> 2DROP ;
                $COLON  EXPECT, 'EXPECT'
                ;       has been branch-optimized
                DW      TOR, ZERO
EXPECT1:        DW      DUPE, RAT, LESS, QBRANCH, EXPECT4
                DW      KEY, DUPE, LIT, _CR, XORR, QBRANCH, EXPECT3
                DW      DUPE, LIT, _BS, EQUAL, QBRANCH, EXPECT2
                DW      DROP, DUPE, QBRANCH, EXPECT1
                DW      ONEM, LIT, _BS, EMIT, SPACE, LIT, _BS, EMIT
                DW      BRANCH, EXPECT1
EXPECT2:        DW      TOR, DDUP, PLUS, RFROM, TUCK, EMIT, CSTORE, ONEP
                DW      BRANCH, EXPECT1
EXPECT3:        DW      DROP
EXPECT4:        DW      SPAN, STORE, RFROM, DDROP, EXIT

; BLK           ( -- a )
;               the block number currently serving as the input stream
                USER$   BLK, 'BLK'

; #TIB          ( -- a )
                $USER   NTIB, '#TIB'
                DW      ?               ;#chars in the terminal input buffer
                DW      _TIB            ;address of the terminal input buffer
                $RESU

; TIB           ( -- a )
;               returns base address of TIB
                $COLON  TIB, 'TIB'
                DW      NTIB, CELLP, AT, EXIT

; QUERY         ( -- )
;               fills TIB from keyboard input
;               assuming 80 column display
                $COLON  QUERY, 'QUERY'
                DW      TIB, DUPE, LIT, _WIDTH, EXPECT
                DW      SPAN, AT, DUPE, NTIB, STORE
                DW      XSOURCE, DSTORE
                DW      BLK, OFF, TOIN, OFF, EXIT

;; vocabulary

		$ONLY			;ONLY DEFINITIONS

; CONTEXT	( -- a )
		USER$	CONTEXT, 'CONTEXT'
_USER		=	_USER + (_VOCS-1)*_CELL

; CURRENT	( -- a )
		USER$	CURRENT, 'CURRENT'

; DEFINITIONS	( -- )
		$COLON	DEFINITIONS, 'DEFINITIONS'
		DW	CONTEXT, AT, CURRENT, STORE, EXIT

; ALSO		( -- )
;		makes the transient vocabulary also one of the resident ones
		$COLON	ALSO, 'ALSO'
		DW	CONTEXT, DUPE, CELLP, LIT, (_VOCS-2)*_CELL
		DW	CMOVETO, EXIT

; ONLY		( -- )
;		a small vocabulary for controlling search order
;		erases CONTEXT vocabulary stack and installs itself as both
;		the transient and the last resident vocabulary
;		assumes on RAM
;		VOCABULARY ROOT ( from Laxen's F83 )
;		: ONLY ( -- ) ( from Laxen's F83 )
;		  ['] ROOT >BODY CONTEXT #VOCS 1- 2* 2DUP ERASE + ! ROOT ;
                $CREATE ONLY, 'ONLY'
ONLY_           DW      _ONLY           ;vocabulary head pointer
		DW	0		;vocabulary link pointer
		$PSCODE
		CALL	DODOES
		DW	CONTEXT, DDUP, LIT, (_VOCS-1)*_CELL, DDUP
		DW	ZERO, FILL	;or ERASE
		DW	PLUS, STORE, STORE, EXIT

; FORTH 	( -- )
;               is not an immediate word
;		its vocabulary link pointer serves as VOC-LINK
;               assumes on RAM
;		| VARIABLE f ( from ZEN ) CELL ALLOT
;               : FORTH ( from ZEN ) f CONTEXT ! ;
                $CREATE FORTH, 'FORTH'
FORTH_          DW      _FORTH          ;vocabulary head pointer
VLINK_		DW	ONLY		;head of the VOC-LINK chain
                $USES   DOVOC

		$FORTH			;FORTH DEFINITIONS

;; dictionary

; DP		( -- a )
;		or H
		$USER	DP, 'DP'
		DW	_DP0
		$RESU

; HERE		( -- a )
		$COLON	HERE, 'HERE'
		DW	DP, AT, EXIT

; ALLOT 	( n -- )
		$COLON	ALLOT, 'ALLOT'
		DW	DP, PSTORE, EXIT

; ,		( w -- )
		$COLON	COMMA, ','
		DW	HERE, STORE, LIT, _CELL, ALLOT, EXIT

; C,		( c -- )
		$COLON	CCOMMA, 'C,'
		DW	HERE, CSTORE, ONE, ALLOT, EXIT

; ALIGN 	( -- )
;		forces DP to the next even address
;		: ALIGN HERE 1 AND ALLOT ;

; find		( a #vocs $ -- $ 0, ca -1, ca 1 )
;		searches a vocabulary array for a packed string
;		skips over null va
;		returns code address and -1 or 1(immediate) if found
;		w/o supporting HASH
		$CODE	XFIND, 'find'
		MOV	DX, BX		;DX = packed string
		MOV	AX, DS
		MOV	ES, AX		;ES is free
		MOV	SAVE, SI	;save SI
		SUB	BX, BX		;in order to return $ 0
FIND1:		POP	CX		;CX = #vocs
		POP	SI		;SI = vocabulary array
FIND2:		JCXZ	FIND5		;not found on all vocab's
		DEC	CX
		LODSW			;AX = va
		OR	AX, AX
		JZ	FIND2		;null va
		CMP	AX, [SI]
		JE	FIND2		;equal to the next va
		PUSH	SI
                PUSH    CX
                MOV     BX, AX          ;BX = va
FIND3:		MOV	DI, DX		;DI = packed string
FIND4:		MOV	BX, [BX]
		OR	BX, BX
		JZ	FIND1		;not found on this vocab
		MOV	SI, BX		;SI = nfa
		DEC	BX
		DEC	BX		;N>LINK
		LODSB			;AL = count byte & lexicon bits
		MOV	CL, AL
		AND	CL, _MASK	;CL = count
		CMP	CL, [DI]
		JNE	FIND4		;lengths differ
		INC	DI
		SUB	CH, CH		;CX = count, set zero flag
		REPE	CMPSB
		JNZ	FIND3		;strings differ
		MOV	DX, SI		;DX = ca
		TEST	AL, _IMME
		POP	AX
		POP	AX		;pop off garbages
		MOV	BX, -1
		JZ	FIND5
		NEG	BX
FIND5:		PUSH	DX		;DX = $ or ca
		DB	0beh		;MOV  SI, ????
SAVE		DW	?		;restore SI
		NEXT			;BX = 0, -1, or 1

; FIND		( $ -- $ 0, ca -1, ca 1 )
;		searches all CONTEXT vocabularies for a packed string
;		returns code address and -1 or 1(immediate) if found
		$COLON	FIND, 'FIND'
		DW	CONTEXT, LIT, _VOCS, ROT, XFIND, EXIT

; '             ( -- ca )
;		error occurs if not found on the context vocabularies
		$COLON	TICK, "'"
		DW	BLL, WORDD, FIND, QMISSING, EXIT

;; error handling

; abortq	( f $ -- )
;		need not be a compilation-only word
		$COLON	ABORTQ, 'abortq'
		DW	SWAP, QBRANCH, @F	;need to append CONSOLE ?
		DW	CR, CR, LIT, '"', EMIT
                DW      HERE, TYPE$, LIT, '"', EMIT
		DW	SPACE, TYPE$, CR, ABORT
@@:             DW      DROP, EXIT

; ABORT"        ( -- ) for compilation only
		$COLON	ABORT$, 'ABORT"'
		DW	QUOTE, COMPILE, ABORTQ, EXIT
		$IMMEDIATE

; 0DIVIDE	( -- )
;		triggers divide-by-0 error
		$CODE	ZDIVIDE, '0DIVIDE'
		STI
		CALL	NEST
		DW	TRUE
		$$	"divide by zero or overflow"
		DW	ABORTQ

; ?MISSING	( f -- )
		$COLON	QMISSING, '?MISSING'
		DW	ZEQUAL
		$$	"is undefined"
		DW	ABORTQ, EXIT

; ?STACK	( -- )
		$COLON	QSTACK, '?STACK'
		DW	SPAT, SP0, AT, SWAP, ULESS
		$$	"stack underflow"
		DW	ABORTQ, EXIT

;; compiler layer

; (		( -- )
;		ignores following string up to next )
		$COLON	PAREN, '('
		DW	LIT, ')', PARSE, DDROP, EXIT
		$IMMEDIATE

; .(		( -- )
;		outputs following string up to next )
		$COLON	DOTP, '.('
		DW	LIT, ')', PARSE, TYPES, EXIT
		$IMMEDIATE

; COMPILE	( -- ) for compilation only
		$COLON	COMPILE, 'COMPILE'
		DW	RFROM, DUPE, CELLP, TOR, AT, COMMA, EXIT

; [COMPILE]	( -- ) for compilation only
;		compiles otherwise an immediate word
		$COLON	BCOMPILE, '[COMPILE]'
		DW	TICK, COMMA, EXIT
		$IMMEDIATE

; LITERAL	( w -- ) for compilation only
		$COLON	LITERAL, 'LITERAL'
		DW	COMPILE, LIT, COMMA, EXIT
		$IMMEDIATE

; DLITERAL	( wd -- ) for compilation only
		$COLON	DLITERAL, 'DLITERAL'
		DW	COMPILE, DLIT, COMMA, COMMA, EXIT
		$IMMEDIATE

; [']           ( -- ) for compilation only
;		: ['] ( from Pygmy ) COMPILE lit ; IMMEDIATE
		$COLON	BTICK, "[']"
		DW	TICK, LITERAL, EXIT
		$IMMEDIATE

; ASCII 	( -- c )
;		or CHAR
;		returns the value of next character
;		w/o compiling action
		$COLON	ASCII, 'ASCII'
		DW	BLL, WORDD, ONEP, CAT, EXIT

; [ASCII]	( -- ) for compilation only
;		compiles the value of next character
		$COLON	BASCII, '[ASCII]'
		DW	ASCII, LITERAL, EXIT
		$IMMEDIATE

; "             ( -- ) for compilation only
;               string compiler
		$COLON	QUOTE, '"'
                DW      COMPILE, LITQ, LIT, '"', PARSE
                DW      DUPE, CCOMMA, HERE, SWAP, DUPE, ALLOT
		DW	CMOVE, EXIT
		$IMMEDIATE

; ."            ( -- ) for compilation only
		$COLON	DOT$, '."'
                DW      QUOTE, COMPILE, TYPE$, EXIT
		$IMMEDIATE

;; defining words

; LAST		( -- a )
;		pointer to the nfa of the last CREATEd word
		USER$	LAST, 'LAST'

; (;CODE)	( -- ) for compilation only
;		terminates the current word and sets the code field of the
;		LAST word to the address of the following
		$COLON	PSCODE, '(;CODE)'
		DW	RFROM
PSCODE1:	DW	LAST, AT
		DW	COUNT, LIT, _MASK, ANDD, PLUS	;or NAME>
		DW	ONEP, TUCK, CELLP, MINUS
		DW	SWAP, STORE, EXIT

; USES		( -- ) for compilation only
;		sets the code field of the LAST word to the contents of the
;		following cell
		$CODE	USES, 'USES'
		PUSH	BX
		LODSW
		MOV	BX, AX
		MOV	AX, OFFSET PSCODE1
		PUSH	AX		;or PUSH  OFFSET PSCODE1 on 80286+

; nest		( -- ) for compilation only
;               or docol
                $LABEL  NEST
                DEC     BP
                DEC     BP              ;decrement by a cell
                MOV     [BP], SI        ;push current SI to return stack
                POP     SI              ;set SI to new position
                NEXT

; CREATE        ( -- )
;		makes a header and some leading codes for the next word in the
;		input stream
;		consults the current, not context, vocabulary for checking
;		redefinition, removing the need for setting CONTEXT to the
;		current vocabulary in ':'
		$COLON	CREATE, 'CREATE'
		DW	CURRENT, AT, AT, COMMA
		DW	CURRENT, ONE, BLL, WORDD, XFIND
		DW	QBRANCH, @F
		DW	CR, LIT, '"', EMIT, HERE, TYPE$
		DW	LIT, '"', EMIT
		$$	" is redefined "
		DW	TYPE$
@@:		DW	DROP, HERE, LAST, STORE
		DW	HERE, CURRENT, AT, STORE
		DW	HERE, CAT, ONEP, ALLOT
		DW	LIT, _CALL, CCOMMA, ZERO, COMMA
		DW	USES, DOVAR, EXIT

; dodoes	( -- pfa ) for compilation only
;               : dodoes SWAP >R SWAP ;
                $LABEL  DODOES
                DEC     BP
                DEC     BP              ;decrement by a cell
                MOV     [BP], SI        ;push current SI to return stack
                POP     SI              ;set SI to new position

; dovar         ( -- a ) for compilation only
;               runtime VARIABLE and CREATE
;               same as SWAP
                $LABEL  DOVAR
                MOV     DI, SP
                XCHG    [DI], BX
                NEXT

; DOES>         ( -- ) for compilation only
;		specifies the runtime of a defining word in high level Forth
		$COLON	DOESTO, 'DOES>'
		DW	COMPILE, PSCODE, LIT, _CALL, CCOMMA
		DW	LIT, DODOES, HERE, CELLP, MINUS, COMMA, EXIT
		$IMMEDIATE

; VARIABLE	( -- )
		$COLON	VARIABLE, 'VARIABLE'
		DW	CREATE, ZERO, COMMA, EXIT

; CONSTANT	( w -- )
;		: CONSTANT CREATE , DOES> @ ;
		$COLON	CONSTANT, 'CONSTANT'
		DW	CREATE, COMMA, PSCODE

; docon 	( -- w ) for compilation only
;               : docon SWAP @ ;
                $LABEL  DOCON
                POP     DI
                PUSH    BX
                MOV     BX, [DI]
                NEXT

		$ONLY			;ONLY DEFINITIONS

; VOCABULARY	( -- )
;               does not declare the new vocabulary IMMEDIATE
;               initializes vhead pointer to NULL
;               initializes vlink pointer to nfa of the previous vocab
                $COLON  VOCABULARY, 'VOCABULARY'
                DW      CREATE, LIT, NULL, COMMA
                DW      LAST, AT, LIT, VLINK_, DUPE, AT, COMMA, STORE
                DW      PSCODE

; dovoc         ( -- ) for compilation only
;               runtime VOCABULARY
                $LABEL  DOVOC
                CALL    DODOES
                DW      CONTEXT, STORE, EXIT

		$FORTH			;FORTH DEFINITIONS

; PREVIOUS      ( -- a )
;		the CURRENT vocabulary during the last CREATE
		USER$	PREVIOUS, 'PREVIOUS'

; HIDE		( -- )
;		removes the last definition from the current vocabulary
		$COLON	HIDE, 'HIDE'
		DW	CURRENT, AT, DUPE, PREVIOUS, STORE
		DW	DUPE, AT, CELLM, AT, SWAP, STORE, EXIT

; REVEAL	( -- )
;		restores the last definition in the PREVIOUS vocabulary
		$COLON	REVEAL, 'REVEAL'
		DW	LAST, AT, PREVIOUS, AT, STORE, EXIT

; :		( -- )
;		does not set CONTEXT to the current vocabulary (see CREATE)
;		acts as a compiling loop like ']'
		$COLON	COLON, ':'
		DW	RFROM, DROP, CREATE, HIDE, USES, NEST, RBRAK

; ;		( -- ) for compilation only
;		acts as an interpreting loop like '['
		$COLON	SEMI, ';'
		DW	RFROM, DROP, COMPILE, EXIT, REVEAL, LBRAK
		$IMMEDIATE

;; structures

; IF		( -- a ) for compilation only
		$COLON	IFF, 'IF'
		DW	COMPILE, QBRANCH, HERE, ZERO, COMMA, EXIT
		$IMMEDIATE

; THEN		( a -- ) for compilation only
		$COLON	THENN, 'THEN'
		DW	HERE, SWAP, STORE, EXIT
		$IMMEDIATE

; ELSE		( a1 -- a2 ) for compilation only
		$COLON	ELSEE, 'ELSE'
		DW	COMPILE, BRANCH, HERE, ZERO, COMMA
		DW	SWAP, THENN, EXIT
		$IMMEDIATE

; BEGIN 	( -- a ) for compilation only
		$COLON	BEGIN, 'BEGIN'
		DW	HERE, EXIT
		$IMMEDIATE

; UNTIL 	( a -- ) for compilation only
		$COLON	UNTIL, 'UNTIL'
		DW	COMPILE, QBRANCH, COMMA, EXIT
		$IMMEDIATE

; AGAIN 	( a -- ) for compilation only
		$COLON	AGAIN, 'AGAIN'
		DW	COMPILE, BRANCH, COMMA, EXIT
		$IMMEDIATE

; WHILE 	( a1 -- a2 a1 ) for compilation only
		$COLON	WHILE, 'WHILE'
		DW	IFF, SWAP, EXIT
		$IMMEDIATE

; REPEAT	( a1 a2 -- ) for compilation only
		$COLON	REPEAT, 'REPEAT'
		DW	AGAIN, THENN, EXIT
		$IMMEDIATE

;; interpreter

; STATE 	( -- a )
;		or 'INTERPRET
;		needed to support multi-line compiler
;		needs initializing for EVALUATE to work in COLD or ABORT
		USER$	STATE, 'STATE'

; [		( -- )
;		interpreting loop
;		forces the nesting word (e.g. ]) to terminate
;		: [
;                 R> DROP lit RECURSE STATE !
;                 BEGIN BL WORD FIND
;                   IF ( ca ) EXECUTE
;                   ELSE ( $ ) NUMBER?
;                     ?MISSING DPL @ 0< IF DROP THEN ( i.e, /NUMBER )
;                   THEN ?STACK
;		  AGAIN ; RECOVER IMMEDIATE
		$COLON	LBRAK, '['
                DW      RFROM, DROP, LIT, LBRAK, STATE, STORE
LBRAK1: 	DW	BLL, WORDD, FIND, QBRANCH, LBRAK2
		DW	EXECUTE, BRANCH, LBRAK3
LBRAK2: 	DW	NUMBERQ, QMISSING
		DW	DPL, AT, ZLESS, QBRANCH, LBRAK3, DROP
LBRAK3: 	DW	QSTACK, BRANCH, LBRAK1
		$IMMEDIATE

; ]		( -- )
;		compiling loop
;		forces the nesting word (e.g. [) to terminate
;		: ]
;		  R> DROP lit RECURSE STATE !
;		  BEGIN BL WORD FIND ?DUP
;		    IF ( ca -1, ca 1 ) 0<
;		      IF , ELSE EXECUTE ?STACK THEN
;		    ELSE ( $ ) NUMBER?
;		      ?MISSING DPL @ 1+ IF DLITERAL ELSE DROP LITERAL THEN
;		      ( i.e, NUMBER, )
;		    THEN ( ?LIMIT may follow )
;		  AGAIN ; RECOVER
		$COLON	RBRAK, ']'
		;	has been branch-optimized
                DW      RFROM, DROP, LIT, RBRAK, STATE, STORE
RBRAK1: 	DW	BLL, WORDD, FIND, QDUP, QBRANCH, RBRAK3
		DW	ZLESS, QBRANCH, RBRAK2
		DW	COMMA, BRANCH, RBRAK1
RBRAK2: 	DW	EXECUTE, QSTACK
		DW	BRANCH, RBRAK1
RBRAK3: 	DW	NUMBERQ, QMISSING
		DW	DPL, AT, ONEP, QBRANCH, RBRAK4
		DW	DLITERAL, BRANCH, RBRAK1
RBRAK4: 	DW	DROP, LITERAL
		DW	BRANCH, RBRAK1

; INTERPRET	( -- )
;		interprets one line of keyed commands or one screen of text
		$COLON	INTERPRET, 'INTERPRET'
		DW	STATE, PERFORM		;need to append EXIT ?

; EVALUATE	( a u -- )
;		evaluates a string
;		does not alter BLK while evaluating
		$COLON	EVALUATE, 'EVALUATE'
		DW	XSOURCE, DUPE, DAT, DTOR, DSTORE
		DW	ZERO, TOIN, DUPE, AT, TOR, STORE
		DW	INTERPRET
		DW	RFROM, TOIN, STORE
		DW	DRFROM, XSOURCE, DSTORE, EXIT

; QUIT		( -- )
;		endless evaluation loop
;		clears the return stack, sets execution mode and begins text
;		interpretation from keyboard input
;		: QUIT
;		  ['] [ STATE !
;		  BEGIN
;		    BEGIN
;		      RP0 @ RP! CR QUERY SPACE INTERPRET
;		      STATE @ ['] [ =
;		    UNTIL ." ok"
;		  AGAIN ; RECOVER
		$COLON	QUIT, 'QUIT'
		DW	LIT, LBRAK, STATE, STORE
@@:		DW	RP0, AT, RPSTORE, CR, QUERY, SPACE, INTERPRET
		DW	STATE, AT, LIT, LBRAK, EQUAL, QBRANCH, @B
		$$	"ok"
		DW	TYPE$, BRANCH, @B

; ABORT 	( -- )
;		default main program and error handler
;		clears both stacks and returns control to the terminal in
;		execution mode
;		alters neither the CONTEXT nor the CURRENT vocabularies
		$COLON	ABORT, 'ABORT'
		DW	SP0, AT, SPSTORE
		DW	CONSOLE, DECIMAL, QUIT

;; initialization

; COLD		( -- )
;		the hi level cold start procedure
;		does not initialize segment pointers
		$COLON	COLD, 'COLD'
		DW	LIT, _UP, LIT, UP_, STORE	;initialize RAM words
		DW	LIT, _ONLY, LIT, ONLY_, STORE
                DW      LIT, ONLY, LIT, _FORTH, LIT, FORTH_, DSTORE
COLD1:          DW      LIT, _UZERO, UP, AT
		DW	LIT, _USIZE, CMOVE		;initialize user area
		DW	ONLY, FORTH, ALSO, DEFINITIONS	;initialize vocabs
		DW	CR
		$$	"Direct-Threaded FORTH v0.8"
		DW	TYPE$, CR, ABORT

_DP0		EQU	$
_ONLY		EQU	_$ONLY+0
_FORTH		EQU	_$FORTH+0
_USIZE		EQU	_RESU+0 	;the size of the initialized user area

		IF2
.ERRNZ		_USER GT _US
		ENDIF

		$ECHO	<USERSIZE(initialized) = >, %_USIZE

; BOOT          ( -- )
;		assumes CS = DS = SS
		$LABEL	BOOT
		MOV	SP, OFFSET _START	;temporary stack
		MOV	AX, 3500H
		INT	21H
		MOV	WORD PTR OLD_INT0, BX
		MOV	WORD PTR OLD_INT0[2], ES
		MOV	DX, OFFSET ZDIVIDE
		MOV	AH, 25H
		INT	21H
		MOV	SP, _SP0
		MOV	BP, _RP0		;initialize stack pointers
		CLD				;SI gets incremented
		MOV	SI, OFFSET COLD1
		NEXT

MAIN		ENDS
		END	_START
