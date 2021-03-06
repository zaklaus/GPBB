; Fixed point routines.
; Tested with TASM 4.0.

USE386          equ     1       ;1 for 386-specific opcodes, 0 for
                                ; 8088 opcodes
MUL_ROUNDING_ON equ     1       ;1 for rounding on multiplies,
                                ; 0 for no rounding. Not rounding is faster,
                                ; rounding is more accurate and generally a
                                ; good idea
DIV_ROUNDING_ON equ     0       ;1 for rounding on divides,
                                ; 0 for no rounding. Not rounding is faster,
                                ; rounding is more accurate, but because
                                ; division is only performed to project to
                                ; the screen, rounding quotients generally
                                ; isn't necessary
ALIGNMENT       equ     2

        .model small
        .386
        .code

;=====================================================================
; Multiplies two fixed-point values together.
; C near-callable as:
;       Fixedpoint FixedMul(Fixedpoint M1, Fixedpoint M2);
FMparms struc
        dw      2 dup(?)        ;return address & pushed BP
M1      dd      ?
M2      dd      ?
FMparms ends
        align   ALIGNMENT
        public  _FixedMul
_FixedMul       proc    near
        push    bp
        mov     bp,sp

if USE386

        mov     eax,[bp+M1]
        imul    dword ptr [bp+M2] ;multiply
if MUL_ROUNDING_ON
        add     eax,8000h       ;round by adding 2^(-17)
        adc     edx,0           ;whole part of result is in DX
endif ;MUL_ROUNDING_ON
        shr     eax,16          ;put the fractional part in AX

else    ;!USE386

                                ;do four partial products and
                                ; add them together, accumulating
                                ; the result in CX:BX
        push    si              ;preserve C register variables
        push    di
                                ;figure out signs, so we can use
                                ; unsigned multiplies
        sub     cx,cx           ;assume both operands positive
        mov     ax,word ptr [bp+M1+2]
        mov     si,word ptr [bp+M1]
        and     ax,ax           ;first operand negative?
        jns     short CheckSecondOperand ;no
        neg     ax              ;yes, so negate first operand
        neg     si
        sbb     ax,0
        inc     cx              ;mark that first operand is negative
CheckSecondOperand:
        mov     bx,word ptr [bp+M2+2]
        mov     di,word ptr [bp+M2]
        and     bx,bx           ;second operand negative?
        jns     short SaveSignStatus ;no
        neg     bx              ;yes, so negate second operand
        neg     di
        sbb     bx,0
        xor     cx,1            ;mark that second operand is negative
SaveSignStatus:
        push    cx              ;remember sign of result; 1 if result
                                ; negative, 0 if result nonnegative
        push    ax              ;remember high word of M1
        mul     bx              ;high word M1 times high word M2
        mov     cx,ax           ;accumulate result in CX:BX (BX not used
                                ; until next operation, however)
                                ;assume no overflow into DX
        mov     ax,si           ;low word M1 times high word M2
        mul     bx
        mov     bx,ax
        add     cx,dx           ;accumulate result in CX:BX
        pop     ax              ;retrieve high word of M1
        mul     di              ;high word M1 times low word M2
        add     bx,ax
        adc     cx,dx           ;accumulate result in CX:BX
        mov     ax,si           ;low word M1 times low word M2
        mul     di
if MUL_ROUNDING_ON
        add     ax,8000h        ;round by adding 2^(-17)
        adc     bx,dx
else ;!MUL_ROUNDING_ON
        add     bx,dx           ;don't round
endif ;MUL_ROUNDING_ON
        adc     cx,0            ;accumulate result in CX:BX
        mov     dx,cx
        mov     ax,bx
        pop     cx
        and     cx,cx           ;is the result negative?
        jz      short FixedMulDone ;no, we're all set
        neg     dx              ;yes, so negate DX:AX
        neg     ax
        sbb     dx,0
FixedMulDone:

        pop     di              ;restore C register variables
        pop     si

endif   ;USE386

        pop     bp
        ret
_FixedMul       endp

;=====================================================================
; Divides one fixed-point value by another.
; C near-callable as:
;       Fixedpoint FixedDiv(Fixedpoint Dividend, Fixedpoint Divisor);
FDparms struc
        dw      2 dup(?)        ;return address & pushed BP
Dividend dd     ?
Divisor  dd     ?
FDparms ends
        align   ALIGNMENT
        public  _FixedDiv
_FixedDiv       proc    near
        push    bp
        mov     bp,sp

if USE386

if DIV_ROUNDING_ON
        sub     cx,cx           ;assume positive result
        mov     eax,[bp+Dividend]
        and     eax,eax         ;positive dividend?
        jns     short FDP1      ;yes
        inc     cx              ;mark it's a negative dividend
        neg     eax             ;make the dividend positive
FDP1:   sub     edx,edx         ;make it a 64-bit dividend, then shift
                                ; left 16 bits so that result will be
                                ; in EAX
        rol     eax,16          ;put fractional part of dividend in
                                ; high word of EAX
        mov     dx,ax           ;put whole part of dividend in DX
        sub     ax,ax           ;clear low word of EAX
        mov     ebx,dword ptr [bp+Divisor]
        and     ebx,ebx         ;positive divisor?
        jns     short FDP2      ;yes
        dec     cx              ;mark it's a negative divisor
        neg     ebx             ;make divisor positive
FDP2:   div     ebx             ;divide
        shr     ebx,1           ;divisor/2, minus 1 if the divisor is
        adc     ebx,0           ; even
        dec     ebx
        cmp     ebx,edx         ;set Carry if the remainder is at least
        adc     eax,0           ; half as large as the divisor, then
                                ; use that to round up if necessary
        and     cx,cx           ;should the result be made negative?
        jz      short FDP3      ;no
        neg     eax             ;yes, negate it
FDP3:
else ;!DIV_ROUNDING_ON
        mov     edx,[bp+Dividend]
        sub     eax,eax
        shrd    eax,edx,16      ;position so that result ends up
        sar     edx,16          ; in EAX
        idiv    dword ptr [bp+Divisor]
endif ;DIV_ROUNDING_ON
        shld    edx,eax,16      ;whole part of result in DX;
                                ; fractional part is already in AX

else ;!USE386

;NOTE!!! Non-386 division uses a 32-bit dividend but only the upper 16 bits
; of the divisor; in other words, only the integer part of the divisor is
; used. This is done so that the division can be accomplished with two fast
; hardware divides instead of a slow software implementation, and is (in my
; opinion) acceptable because division is only used to project points to the
; screen (normally, the divisor is a Z coordinate), so there's no cumulative
; error, although there will be some error in pixel placement (the magnitude
; of the error is less the farther away from the Z=0 plane objects are). This
; is *not* a general-purpose divide, though; if the divisor is less than 1,
; for instance, a divide-by-zero error will result! For this reason, non-386
; projection can't be performed for points closer to the viewpoint than Z=1.

                                ;figure out signs, so we can use
                                ; unsigned divisions
        sub     cx,cx           ;assume both operands positive
        mov     ax,word ptr [bp+Dividend+2]
        and     ax,ax           ;first operand negative?
        jns     short CheckSecondOperandD ;no
        neg     ax              ;yes, so negate first operand
        neg     word ptr [bp+Dividend]
        sbb     ax,0
        inc     cx              ;mark that first operand is negative
CheckSecondOperandD:
        mov     bx,word ptr [bp+Divisor+2]
        and     bx,bx           ;second operand negative?
        jns     short SaveSignStatusD ;no
        neg     bx              ;yes, so negate second operand
        neg     word ptr [bp+Divisor]
        sbb     bx,0
        xor     cx,1            ;mark that second operand is negative
SaveSignStatusD:
        push    cx              ;remember sign of result; 1 if result
                                ; negative, 0 if result nonnegative
        sub     dx,dx           ;put Dividend+2 (integer part) in DX:AX
        div     bx              ;first half of 32/16 division, integer part
                                ; divided by integer part
        mov     cx,ax           ;set aside integer part of result
        mov     ax,word ptr [bp+Dividend] ;concatenate the fractional part of
                                ; the dividend to the remainder (fractional
                                ; part) of the result from dividing the
                                ; integer part of the dividend
        div     bx              ;second half of 32/16 division
        
if DIV_ROUNDING_ON EQ 0
        shr     bx,1            ;divisor/2, minus 1 if the divisor is
        adc     bx,0            ; even
        dec     bx
        cmp     bx,dx           ;set Carry if the remainder is at least
        adc     ax,0            ; half as large as the divisor, then
        adc     cx,0            ; use that to round up if necessary
endif ;DIV_ROUNDING_ON

        mov     dx,cx           ;absolute value of result in DX:AX
        pop     cx
        and     cx,cx           ;is the result negative?
        jz      short FixedDivDone ;no, we're all set
        neg     dx              ;yes, so negate DX:AX
        neg     ax
        sbb     dx,0
FixedDivDone:

endif ;USE386

        pop     bp
        ret
_FixedDiv       endp

;=====================================================================
; Returns the sine and cosine of an angle.
; C near-callable as:
;       void CosSin(TAngle Angle, Fixedpoint *Cos, Fixedpoint *);

        align   ALIGNMENT
CosTable label dword
        include costable.inc

SCparms struc
        dw      2 dup(?)        ;return address & pushed BP
Angle   dw      ?               ;angle to calculate sine & cosine for
Cos     dw      ?               ;pointer to cos destination
Sin     dw      ?               ;pointer to sin destination
SCparms ends

        align   ALIGNMENT
        public _CosSin
_CosSin proc    near
        push    bp              ;preserve stack frame
        mov     bp,sp           ;set up local stack frame

if USE386

        mov     bx,[bp].Angle
        and     bx,bx           ;make sure angle's between 0 and 2*pi
        jns     short CheckInRange
MakePos:                        ;less than 0, so make it positive
        add     bx,360*10
        js      short MakePos
        jmp     short CheckInRange

        align   ALIGNMENT
MakeInRange:                    ;make sure angle is no more than 2*pi
        sub     bx,360*10
CheckInRange:
        cmp     bx,360*10
        jg      short MakeInRange

        cmp     bx,180*10       ;figure out which quadrant
        ja      short BottomHalf ;quadrant 2 or 3
        cmp     bx,90*10        ;quadrant 0 or 1
        ja      short Quadrant1
                                ;quadrant 0
        shl     bx,2
        mov     eax,CosTable[bx] ;look up sine
        neg     bx              ;sin(Angle) = cos(90-Angle)
        mov     edx,CosTable[bx+90*10*4] ;look up cosine
        jmp     short CSDone

        align   ALIGNMENT
Quadrant1:
        neg     bx
        add     bx,180*10       ;convert to angle between 0 and 90
        shl     bx,2
        mov     eax,CosTable[bx] ;look up cosine
        neg     eax             ;negative in this quadrant
        neg     bx              ;sin(Angle) = cos(90-Angle)
        mov     edx,CosTable[bx+90*10*4] ;look up cosine
        jmp     short CSDone

        align   ALIGNMENT
BottomHalf:                     ;quadrant 2 or 3
        neg     bx
        add     bx,360*10       ;convert to angle between 0 and 180
        cmp     bx,90*10        ;quadrant 2 or 3
        ja      short Quadrant2
                                ;quadrant 3
        shl     bx,2
        mov     eax,CosTable[bx] ;look up cosine
        neg     bx              ;sin(Angle) = cos(90-Angle)
        mov     edx,CosTable[90*10*4+bx] ;look up sine
        neg     edx             ;negative in this quadrant
        jmp     short CSDone

        align   ALIGNMENT
Quadrant2:
        neg     bx
        add     bx,180*10       ;convert to angle between 0 and 90
        shl     bx,2
        mov     eax,CosTable[bx] ;look up cosine
        neg     eax             ;negative in this quadrant
        neg     bx              ;sin(Angle) = cos(90-Angle)
        mov     edx,CosTable[90*10*4+bx] ;look up sine
        neg     edx             ;negative in this quadrant
CSDone:
        mov     bx,[bp].Cos
        mov     [bx],eax
        mov     bx,[bp].Sin
        mov     [bx],edx

else ;!USE386

        mov     bx,[bp].Angle
        and     bx,bx           ;make sure angle's between 0 and 2*pi
        jns     short CheckInRange
MakePos:                        ;less than 0, so make it positive
        add     bx,360*10
        js      short MakePos
        jmp     short CheckInRange

        align   ALIGNMENT
MakeInRange:                    ;make sure angle is no more than 2*pi
        sub     bx,360*10
CheckInRange:
        cmp     bx,360*10
        jg      short MakeInRange

        cmp     bx,180*10       ;figure out which quadrant
        ja      short BottomHalf ;quadrant 2 or 3
        cmp     bx,90*10        ;quadrant 0 or 1
        ja      short Quadrant1
                                ;quadrant 0
        shl     bx,2
        mov     ax,word ptr CosTable[bx] ;look up sine
        mov     dx,word ptr CosTable[bx+2]
        neg     bx              ;sin(Angle) = cos(90-Angle)
        mov     cx,word ptr CosTable[bx+90*10*4+2] ;look up cosine
        mov     bx,word ptr CosTable[bx+90*10*4]
        jmp     CSDone

        align   ALIGNMENT
Quadrant1:
        neg     bx
        add     bx,180*10       ;convert to angle between 0 and 90
        shl     bx,2
        mov     ax,word ptr CosTable[bx] ;look up cosine
        mov     dx,word ptr CosTable[bx+2]
        neg     dx              ;negative in this quadrant
        neg     ax
        sbb     dx,0
        neg     bx              ;sin(Angle) = cos(90-Angle)
        mov     cx,word ptr CosTable[bx+90*10*4+2] ;look up cosine
        mov     bx,word ptr CosTable[bx+90*10*4]
        jmp     short CSDone

        align   ALIGNMENT
BottomHalf:                     ;quadrant 2 or 3
        neg     bx
        add     bx,360*10       ;convert to angle between 0 and 180
        cmp     bx,90*10        ;quadrant 2 or 3
        ja      short Quadrant2
                                ;quadrant 3
        shl     bx,2
        mov     ax,word ptr CosTable[bx] ;look up cosine
        mov     dx,word ptr CosTable[bx+2]
        neg     bx              ;sin(Angle) = cos(90-Angle)
        mov     cx,word ptr CosTable[90*10*4+bx+2] ;look up sine
        mov     bx,word ptr CosTable[90*10*4+bx]
        neg     cx              ;negative in this quadrant
        neg     bx
        sbb     cx,0
        jmp     short CSDone

        align   ALIGNMENT
Quadrant2:
        neg     bx
        add     bx,180*10       ;convert to angle between 0 and 90
        shl     bx,2
        mov     ax,word ptr CosTable[bx] ;look up cosine
        mov     dx,word ptr CosTable[bx+2]
        neg     dx              ;negative in this quadrant
        neg     ax
        sbb     dx,0
        neg     bx              ;sin(Angle) = cos(90-Angle)
        mov     cx,word ptr CosTable[90*10*4+bx+2] ;look up sine
        mov     bx,word ptr CosTable[90*10*4+bx]
        neg     cx              ;negative in this quadrant
        neg     bx
        sbb     cx,0
CSDone:
        push    bx
        mov     bx,[bp].Cos
        mov     [bx],ax
        mov     [bx+2],dx
        mov     bx,[bp].Sin
        pop     ax
        mov     [bx],ax
        mov     [bx+2],cx

endif ;USE386

        pop     bp              ;restore stack frame
        ret
_CosSin endp

;=====================================================================
; Matrix multiplies Xform by SourceVec, and stores the result in
; DestVec. Multiplies a 4x4 matrix times a 4x1 matrix; the result
; is a 4x1 matrix. Cheats by assuming the W coord is 1 and the
; bottom row of the matrix is 0 0 0 1, and doesn't bother to set
; the W coordinate of the destination.
; C near-callable as:
;       void XformVec(Xform WorkingXform, Fixedpoint *SourceVec,
;               Fixedpoint *DestVec);
;
; This assembly code is equivalent to this C code:
;   int i;
;
;   for (i=0; i<3; i++)
;      DestVec[i] = FixedMul(WorkingXform[i][0], SourceVec[0]) +
;            FixedMul(WorkingXform[i][1], SourceVec[1]) +
;            FixedMul(WorkingXform[i][2], SourceVec[2]) +
;            WorkingXform[i][3];   /* no need to multiply by W = 1 */

XVparms struc
        dw      2 dup(?)        ;return address & pushed BP
WorkingXform dw ?               ;pointer to transform matrix
SourceVec dw    ?               ;pointer to source vector
DestVec dw      ?               ;pointer to destination vector
XVparms ends

; Macro for non-386 multiply. AX, BX, CX, DX destroyed.
FIXED_MUL       MACRO   M1,M2
        local   CheckSecondOperand,SaveSignStatus,FixedMulDone

                                ;do four partial products and
                                ; add them together, accumulating
                                ; the result in CX:BX
                                ;figure out signs, so we can use
                                ; unsigned multiplies
        sub     cx,cx           ;assume both operands positive
        mov     bx,word ptr [&M1&+2]
        and     bx,bx           ;first operand negative?
        jns     short CheckSecondOperand ;no
        neg     bx              ;yes, so negate first operand
        neg     word ptr [&M1&]
        sbb     bx,0
        mov     word ptr [&M1&+2],bx
        inc     cx              ;mark that first operand is negative
CheckSecondOperand:
        mov     bx,word ptr [&M2&+2]
        and     bx,bx           ;second operand negative?
        jns     short SaveSignStatus  ;no
        neg     bx              ;yes, so negate second operand
        neg     word ptr [&M2&]
        sbb     bx,0
        mov     word ptr [&M2&+2],bx
        xor     cx,1            ;mark that second operand is negative
SaveSignStatus:
        push    cx              ;remember sign of result; 1 if result
                                ; negative, 0 if result nonnegative
        mov     ax,word ptr [&M1&+2] ;high word times high word
        mul     word ptr [&M2&+2]
        mov     cx,ax           ;
                                ;assume no overflow into DX
        mov     ax,word ptr [&M1&+2] ;high word times low word
        mul     word ptr [&M2&]
        mov     bx,ax
        add     cx,dx
        mov     ax,word ptr [&M1&] ;low word times high word
        mul     word ptr [&M2&+2]
        add     bx,ax
        adc     cx,dx
        mov     ax,word ptr [&M1&] ;low word times low word
        mul     word ptr [&M2&]
if MUL_ROUNDING_ON
        add     ax,8000h        ;round by adding 2^(-17)
        adc     bx,dx
else ;!MUL_ROUNDING_ON
        add     bx,dx           ;don't round
endif ;MUL_ROUNDING_ON
        adc     cx,0
        mov     dx,cx
        mov     ax,bx
        pop     cx
        and     cx,cx           ;is the result negative?
        jz      short FixedMulDone ;no, we're all set
        neg     dx              ;yes, so negate DX:AX
        neg     ax
        sbb     dx,0
FixedMulDone:
        ENDM

        align   ALIGNMENT
        public _XformVec
_XformVec       proc    near
        push    bp              ;preserve stack frame
        mov     bp,sp           ;set up local stack frame
        push    si              ;preserve register variables
        push    di

if USE386

        mov     si,[bp].WorkingXform ;SI points to xform matrix
        mov     bx,[bp].SourceVec    ;BX points to source vector
        mov     di,[bp].DestVec      ;DI points to dest vector

soff=0
doff=0
        REPT 3                  ;do once each for dest X, Y, and Z
        mov     eax,[si+soff]   ;column 0 entry on this row
        imul    dword ptr [bx]  ;xform entry times source X entry
if MUL_ROUNDING_ON
        add     eax,8000h       ;round by adding 2^(-17)
        adc     edx,0           ;whole part of result is in DX
endif ;MUL_ROUNDING_ON
        shrd    eax,edx,16      ;shift the result back to 16.16 form
        mov     ecx,eax         ;set running total

        mov     eax,[si+soff+4] ;column 1 entry on this row
        imul    dword ptr [bx+4] ;xform entry times source Y entry
if MUL_ROUNDING_ON
        add     eax,8000h       ;round by adding 2^(-17)
        adc     edx,0           ;whole part of result is in DX
endif ;MUL_ROUNDING_ON
        shrd    eax,edx,16      ;shift the result back to 16.16 form
        add     ecx,eax         ;running total for this row

        mov     eax,[si+soff+8] ;column 2 entry on this row
        imul    dword ptr [bx+8] ;xform entry times source Z entry
if MUL_ROUNDING_ON
        add     eax,8000h       ;round by adding 2^(-17)
        adc     edx,0           ;whole part of result is in DX
endif ;MUL_ROUNDING_ON
        shrd    eax,edx,16      ;shift the result back to 16.16 form
        add     ecx,eax         ;running total for this row

        add     ecx,[si+soff+12] ;add in translation
        mov     [di+doff],ecx   ;save the result in the dest vector
soff=soff+16
doff=doff+4
        ENDM

else ;!USE386

        mov     si,[bp].WorkingXform ;SI points to xform matrix
        mov     di,[bp].SourceVec    ;DI points to source vector
        mov     bx,[bp].DestVec      ;BX points to dest vector
        push    bp                   ;preserve stack frame pointer

soff=0
doff=0
        REPT 3                  ;do once each for dest X, Y, and Z
        push    bx              ;remember dest vector pointer
        push    word ptr [si+soff+2] 
        push    word ptr [si+soff]
        push    word ptr [di+2]
        push    word ptr [di]
        call    _FixedMul       ;xform entry times source X entry
        add     sp,8            ;clear parameters from stack
        mov     cx,ax           ;set running total
        mov     bp,dx

        push    cx              ;preserve low word of running total
        push    word ptr [si+soff+4+2] 
        push    word ptr [si+soff+4]
        push    word ptr [di+4+2]
        push    word ptr [di+4]
        call    _FixedMul       ;xform entry times source Y entry
        add     sp,8            ;clear parameters from stack
        pop     cx              ;restore low word of running total
        add     cx,ax           ;running total for this row
        adc     bp,dx

        push    cx              ;preserve low word of running total
        push    word ptr [si+soff+8+2] 
        push    word ptr [si+soff+8]
        push    word ptr [di+8+2]
        push    word ptr [di+8]
        call    _FixedMul       ;xform entry times source Z entry
        add     sp,8            ;clear parameters from stack
        pop     cx              ;restore low word of running total
        add     cx,ax           ;running total for this row
        adc     bp,dx

        add     cx,[si+soff+12] ;add in translation
        adc     bp,[si+soff+12+2]
        pop     bx              ;restore dest vector pointer
        mov     [bx+doff],cx    ;save the result in the dest vector
        mov     [bx+doff+2],bp
soff=soff+16
doff=doff+4
        ENDM

        pop     bp              ;restore stack frame pointer

endif ;USE386

        pop     di              ;restore register variables
        pop     si
        pop     bp              ;restore stack frame
        ret
_XformVec       endp

;=====================================================================
; Matrix multiplies SourceXform1 by SourceXform2 and stores the
; result in DestXform. Multiplies a 4x4 matrix times a 4x4 matrix;
; the result is a 4x4 matrix. Cheats by assuming the bottom row of
; each matrix is 0 0 0 1, and doesn't bother to set the bottom row
; of the destination.
; C near-callable as:
;       void ConcatXforms(Xform SourceXform1, Xform SourceXform2,
;               Xform DestXform)
;
; This assembly code is equivalent to this C code:
;   int i, j;
;
;   for (i=0; i<3; i++) {
;      for (j=0; j<3; j++)
;         DestXform[i][j] =
;               FixedMul(SourceXform1[i][0], SourceXform2[0][j]) +
;               FixedMul(SourceXform1[i][1], SourceXform2[1][j]) +
;               FixedMul(SourceXform1[i][2], SourceXform2[2][j]);
;      DestXform[i][3] =
;            FixedMul(SourceXform1[i][0], SourceXform2[0][3]) +
;            FixedMul(SourceXform1[i][1], SourceXform2[1][3]) +
;            FixedMul(SourceXform1[i][2], SourceXform2[2][3]) +
;            SourceXform1[i][3];
;   }

CXparms struc
        dw      2 dup(?)        ;return address & pushed BP
SourceXform1 dw ?               ;pointer to first source xform matrix
SourceXform2 dw ?               ;pointer to second source xform matrix
DestXform    dw ?               ;pointer to destination xform matrix
CXparms ends

        align   ALIGNMENT
        public _ConcatXforms
_ConcatXforms   proc    near
        push    bp              ;preserve stack frame
        mov     bp,sp           ;set up local stack frame
        push    si              ;preserve register variables
        push    di

if USE386

        mov     bx,[bp].SourceXform2 ;BX points to xform2 matrix
        mov     si,[bp].SourceXform1 ;SI points to xform1 matrix
        mov     di,[bp].DestXform    ;DI points to dest xform matrix

roff=0                          ;row offset
        REPT 3                  ;once for each row
coff=0                          ;column offset
        REPT 3                  ;once for each of the first 3 columns,
                                ; assuming 0 as the bottom entry (no
                                ; translation)
        mov     eax,[si+roff]   ;column 0 entry on this row
        imul    dword ptr [bx+coff] ;times row 0 entry in column
if MUL_ROUNDING_ON
        add     eax,8000h       ;round by adding 2^(-17)
        adc     edx,0           ;whole part of result is in DX
endif ;MUL_ROUNDING_ON
        shrd    eax,edx,16      ;shift the result back to 16.16 form
        mov     ecx,eax         ;set running total

        mov     eax,[si+roff+4] ;column 1 entry on this row
        imul    dword ptr [bx+coff+16] ;times row 1 entry in col
if MUL_ROUNDING_ON
        add     eax,8000h       ;round by adding 2^(-17)
        adc     edx,0           ;whole part of result is in DX
endif ;MUL_ROUNDING_ON
        shrd    eax,edx,16      ;shift the result back to 16.16 form
        add     ecx,eax         ;running total

        mov     eax,[si+roff+8] ;column 2 entry on this row
        imul    dword ptr [bx+coff+32] ;times row 2 entry in col
if MUL_ROUNDING_ON
        add     eax,8000h       ;round by adding 2^(-17)
        adc     edx,0           ;whole part of result is in DX
endif ;MUL_ROUNDING_ON
        shrd    eax,edx,16      ;shift the result back to 16.16 form
        add     ecx,eax         ;running total

        mov     [di+coff+roff],ecx ;save the result in dest matrix
coff=coff+4                     ;point to next col in xform2 & dest
        ENDM
                                ;now do the fourth column, assuming
                                ; 1 as the bottom entry, causing
                                ; translation to be performed
        mov     eax,[si+roff]   ;column 0 entry on this row
        imul    dword ptr [bx+coff] ;times row 0 entry in column
if MUL_ROUNDING_ON
        add     eax,8000h       ;round by adding 2^(-17)
        adc     edx,0           ;whole part of result is in DX
endif ;MUL_ROUNDING_ON
        shrd    eax,edx,16      ;shift the result back to 16.16 form
        mov     ecx,eax         ;set running total

        mov     eax,[si+roff+4] ;column 1 entry on this row
        imul    dword ptr [bx+coff+16] ;times row 1 entry in col
if MUL_ROUNDING_ON
        add     eax,8000h       ;round by adding 2^(-17)
        adc     edx,0           ;whole part of result is in DX
endif ;MUL_ROUNDING_ON
        shrd    eax,edx,16      ;shift the result back to 16.16 form
        add     ecx,eax         ;running total

        mov     eax,[si+roff+8] ;column 2 entry on this row
        imul    dword ptr [bx+coff+32] ;times row 2 entry in col
if MUL_ROUNDING_ON
        add     eax,8000h       ;round by adding 2^(-17)
        adc     edx,0           ;whole part of result is in DX
endif ;MUL_ROUNDING_ON
        shrd    eax,edx,16      ;shift the result back to 16.16 form
        add     ecx,eax         ;running total

        add     ecx,[si+roff+12] ;add in translation

        mov     [di+coff+roff],ecx ;save the result in dest matrix
coff=coff+4                     ;point to next col in xform2 & dest

roff=roff+16                    ;point to next col in xform2 & dest
        ENDM

else ;!USE386

        mov     di,[bp].SourceXform2 ;DI points to xform2 matrix
        mov     si,[bp].SourceXform1 ;SI points to xform1 matrix
        mov     bx,[bp].DestXform    ;BX points to dest xform matrix
        push    bp                   ;preserve stack frame pointer

roff=0                          ;row offset
        REPT 3                  ;once for each row
coff=0                          ;column offset
        REPT 3                  ;once for each of the first 3 columns,
                                ; assuming 0 as the bottom entry (no
                                ; translation)
        push    bx              ;remember dest vector pointer
        push    word ptr [si+roff+2] 
        push    word ptr [si+roff]
        push    word ptr [di+coff+2]
        push    word ptr [di+coff]
        call    _FixedMul       ;column 0 entry on this row times row 0
                                ; entry in column
        add     sp,8            ;clear parameters from stack
        mov     cx,ax           ;set running total
        mov     bp,dx

        push    cx              ;preserve low word of running total
        push    word ptr [si+roff+4+2] 
        push    word ptr [si+roff+4]
        push    word ptr [di+coff+16+2]
        push    word ptr [di+coff+16]
        call    _FixedMul       ;column 1 entry on this row times row 1
                                ; entry in column
        add     sp,8            ;clear parameters from stack
        pop     cx              ;restore low word of running total
        add     cx,ax           ;running total for this row
        adc     bp,dx

        push    cx              ;preserve low word of running total
        push    word ptr [si+roff+8+2] 
        push    word ptr [si+roff+8]
        push    word ptr [di+coff+32+2]
        push    word ptr [di+coff+32]
        call    _FixedMul       ;column 1 entry on this row times row 1
                                ; entry in column
        add     sp,8            ;clear parameters from stack
        pop     cx              ;restore low word of running total
        add     cx,ax           ;running total for this row
        adc     bp,dx

        pop     bx              ;restore DestXForm pointer
        mov     [bx+coff+roff],cx ;save the result in dest matrix
        mov     [bx+coff+roff+2],bp
coff=coff+4                     ;point to next col in xform2 & dest
        ENDM
                                ;now do the fourth column, assuming
                                ; 1 as the bottom entry, causing
                                ; translation to be performed
        push    bx              ;remember dest vector pointer
        push    word ptr [si+roff+2] 
        push    word ptr [si+roff]
        push    word ptr [di+coff+2]
        push    word ptr [di+coff]
        call    _FixedMul       ;column 0 entry on this row times row 0
                                ; entry in column
        add     sp,8            ;clear parameters from stack
        mov     cx,ax           ;set running total
        mov     bp,dx

        push    cx              ;preserve low word of running total
        push    word ptr [si+roff+4+2] 
        push    word ptr [si+roff+4]
        push    word ptr [di+coff+16+2]
        push    word ptr [di+coff+16]
        call    _FixedMul       ;column 1 entry on this row times row 1
                                ; entry in column
        add     sp,8            ;clear parameters from stack
        pop     cx              ;restore low word of running total
        add     cx,ax           ;running total for this row
        adc     bp,dx

        push    cx              ;preserve low word of running total
        push    word ptr [si+roff+8+2] 
        push    word ptr [si+roff+8]
        push    word ptr [di+coff+32+2]
        push    word ptr [di+coff+32]
        call    _FixedMul       ;column 1 entry on this row times row 1
                                ; entry in column
        add     sp,8            ;clear parameters from stack
        pop     cx              ;restore low word of running total
        add     cx,ax           ;running total for this row
        adc     bp,dx

        add     cx,[si+roff+12] ;add in translation
        add     bp,[si+roff+12+2]

        pop     bx              ;restore DestXForm pointer
        mov     [bx+coff+roff],cx ;save the result in dest matrix
        mov     [bx+coff+roff+2],bp
coff=coff+4                     ;point to next col in xform2 & dest

roff=roff+16                    ;point to next col in xform2 & dest
        ENDM

        pop     bp              ;restore stack frame pointer

endif ;USE386

        pop     di              ;restore register variables
        pop     si
        pop     bp              ;restore stack frame
        ret
_ConcatXforms   endp
        end
