; ============================================================================
;  APEX Computer Shop - Inventory & Point-of-Sale System
;  32-bit x86 assembly, NASM syntax, Linux (int 0x80 system calls, no libc)
;
;  Build :  nasm -f elf32 apex_pos.asm -o apex_pos.o
;           ld -m elf_i386 apex_pos.o -o apex_pos
;  Run   :  ./apex_pos          (staff PIN: 1234)
;
;  Money is stored as integer cents (RM 29.99 = 2999) so that only integer
;  arithmetic (ADD, SUB, MUL, IMUL, DIV) is needed.
; ============================================================================

bits 32

NITEMS   equ 5          ; number of products in the catalogue
NAMELEN  equ 12         ; fixed width of a product name field
MAXCART  equ 10         ; maximum lines in one sale
MAXSTOCK equ 999        ; upper limit for stock after a restock
LOWSTOCK equ 5          ; stock below this is flagged [LOW]
TAXRATE  equ 6          ; sales tax, percent

; Linux i386 system call numbers
SYS_EXIT  equ 1
SYS_READ  equ 3
SYS_WRITE equ 4

%macro NAME 1                       ; product name padded to NAMELEN bytes
    %strlen _l %1
    db %1
    times NAMELEN-_l db ' '
%endmacro

%macro PUTS 1                       ; print a zero-terminated string
    push esi
    mov  esi, %1
    call print_str
    pop  esi
%endmacro

; ----------------------------------------------------------------------------
section .data
; ----------------------------------------------------------------------------
pin         db "1234"

; product table (parallel arrays, index 0..NITEMS-1)
item_names:
    NAME "Laptop"
    NAME "Monitor"
    NAME "Keyboard"
    NAME "Mouse"
    NAME "USB Flash"
item_price  dd 299900, 59900, 8900, 4500, 2500      ; in cents
item_stock  dd 5, 8, 20, 30, 50                     ; modified at run time

s_banner    db 27,"[1;36m",10
            db "  ==========================================",10
            db "    APEX COMPUTER SHOP  -  POS & INVENTORY SYSTEM",10
            db "  ==========================================",27,"[0m",10,0
s_pin       db "  Enter staff PIN: ",0
s_wrong     db 27,"[31m  Wrong PIN.",27,"[0m",10,0
s_locked    db 27,"[31m  Too many failed attempts. System locked.",27,"[0m",10,0
s_welcome   db 27,"[32m  Login successful.",27,"[0m",10,0

s_menu      db 10,27,"[1m  ---------- MAIN MENU ----------",27,"[0m",10
            db "   1. New sale",10
            db "   2. View inventory",10
            db "   3. Restock item",10
            db "   4. Sales report",10
            db "   5. Exit",10
            db "  Choice: ",0
s_invalid   db 27,"[31m  Invalid input, try again.",27,"[0m",10,0
s_bye       db 10,"  Session closed. Goodbye!",10,0

s_invhdr    db 10,"  No. Product      Price         Stock",10
            db "  --------------------------------------",10,0
s_low       db 27,"[33m  [LOW]",27,"[0m",0
s_sp2       db "  ",0
s_dotsp     db ".  ",0
s_tab       db "   ",0
s_nl        db 10,0

s_selitem   db "  Item no. (0 = checkout, 6 = back to menu): ",0
s_qty       db "  Quantity: ",0
s_added     db 27,"[32m  Added to cart.",27,"[0m",10,0
s_nostock   db 27,"[31m  Not enough stock for that quantity.",27,"[0m",10,0
s_back      db "  Back to main menu (cart cleared, stock restored).",10,0
s_cartfull  db "  Cart is full - proceeding to checkout.",10,0

s_rcpt      db 10,"  ============== RECEIPT ==============",10,0
s_x         db " x ",0
s_at        db " @ ",0
s_eq        db " = ",0
s_subtot    db "  --------------------------------------",10
            db "  Subtotal          : ",0
s_disc      db "  Discount (",0
s_disc2     db "%)      : -",0
s_tax       db "  Tax (6%)          : ",0
s_total     db "  TOTAL             : ",0
s_pay       db 10,"  Cash received in RM, e.g. 2861.04 (0 = cancel): ",0
s_short     db 27,"[31m  Insufficient payment.",27,"[0m",10,0
s_change    db "  Change            : ",0
s_thanks    db 27,"[32m  Payment complete. Thank you!",27,"[0m",10,0
s_cancel    db "  Sale cancelled - stock restored.",10,0

s_rsitem    db "  Restock which item (0 = back): ",0
s_rsqty     db "  Units to add: ",0
s_rsfull    db 27,"[31m  Stock would exceed the limit of 999.",27,"[0m",10,0
s_rsok      db 27,"[32m  Stock updated.",27,"[0m",10,0

s_rephdr    db 10,"  ============ SALES REPORT ============",10
            db "  Product      Units sold   Revenue",10
            db "  --------------------------------------",10,0
s_rule      db "  --------------------------------------",10,0
s_rtxn      db "  Transactions      : ",0
s_runits    db "  Units sold        : ",0
s_rrev      db "  Gross revenue     : ",0
s_ravg      db "  Average sale      : ",0
s_rbest     db "  Best seller       : ",0
s_nosales   db "  (no sales recorded yet)",10,0
s_rm        db "RM ",0
s_dot       db ".",0
s_zero      db "0",0

; ----------------------------------------------------------------------------
section .bss
; ----------------------------------------------------------------------------
inbuf       resb 64
numbuf      resb 12
cart_item   resd MAXCART            ; product index per cart line
cart_qty    resd MAXCART            ; quantity per cart line
cart_count  resd 1
sold        resd NITEMS             ; units sold per product
total_sales resd 1                  ; cents
txn_count   resd 1
rc_sub      resd 1
rc_pct      resd 1
rc_disc     resd 1
rc_tax      resd 1
rc_total    resd 1

; ----------------------------------------------------------------------------
section .text
global _start
; ----------------------------------------------------------------------------

_start:
    PUTS s_banner

; ---- login: 3 attempts (loop + conditional jumps) --------------------------
    mov  ebp, 3
.try:
    PUTS s_pin
    call read_line
    mov  esi, inbuf
    mov  edi, pin
    mov  ecx, 4
.cmp:                               ; compare 4 PIN digits one by one
    mov  al, [esi]
    cmp  al, [edi]
    jne  .fail
    inc  esi
    inc  edi
    loop .cmp
    cmp  byte [esi], 10             ; PIN must end exactly here
    jne  .fail
    PUTS s_welcome
    jmp  menu
.fail:
    dec  ebp
    jz   .locked
    PUTS s_wrong
    jmp  .try
.locked:
    PUTS s_locked
    mov  ebx, 1
    jmp  exit_code

; ---- main menu -------------------------------------------------------------
menu:
    PUTS s_menu
    call read_int
    cmp  eax, 1
    je   do_sale
    cmp  eax, 2
    je   do_inventory
    cmp  eax, 3
    je   do_restock
    cmp  eax, 4
    je   do_report
    cmp  eax, 5
    je   do_exit
    PUTS s_invalid
    jmp  menu

do_inventory:
    call show_inventory
    jmp  menu

do_exit:
    PUTS s_bye
    xor  ebx, ebx
exit_code:                          ; ebx = exit status
    mov  eax, SYS_EXIT
    int  0x80

; ---- option 1: new sale ----------------------------------------------------
do_sale:
    mov  dword [cart_count], 0
    call show_inventory
.item:
    PUTS s_selitem
    call read_int
    test eax, eax
    jz   .checkout                  ; 0 -> finish cart
    cmp  eax, 6
    je   .back                      ; 6 -> abandon cart, return to menu
    cmp  eax, NITEMS
    ja   .bad                       ; also catches -1 (invalid number)
    dec  eax
    mov  esi, eax                   ; esi = product index
    PUTS s_qty
    call read_int
    test eax, eax
    jle  .bad
    mov  edi, eax                   ; edi = quantity
    cmp  edi, [item_stock+esi*4]
    ja   .nostock
    mov  ecx, [cart_count]          ; append line to the cart
    mov  [cart_item+ecx*4], esi
    mov  [cart_qty+ecx*4], edi
    inc  ecx
    mov  [cart_count], ecx
    sub  [item_stock+esi*4], edi    ; reserve stock
    PUTS s_added
    cmp  ecx, MAXCART
    jb   .item
    PUTS s_cartfull
    jmp  .checkout
.nostock:
    PUTS s_nostock
    jmp  .item
.bad:
    PUTS s_invalid
    jmp  .item
.back:                              ; give reserved stock back
    xor  ebx, ebx
.unreserve:
    cmp  ebx, [cart_count]
    jae  .backdone
    mov  esi, [cart_item+ebx*4]
    mov  eax, [cart_qty+ebx*4]
    add  [item_stock+esi*4], eax
    inc  ebx
    jmp  .unreserve
.backdone:
    mov  dword [cart_count], 0
    PUTS s_back
    jmp  menu
.checkout:
    cmp  dword [cart_count], 0
    je   menu
    call checkout
    jmp  menu

; ---- option 3: restock -----------------------------------------------------
do_restock:
    call show_inventory
.again:
    PUTS s_rsitem
    call read_int
    test eax, eax
    jz   menu
    cmp  eax, NITEMS
    ja   .bad
    dec  eax
    mov  esi, eax
    PUTS s_rsqty
    call read_int
    test eax, eax
    jle  .bad
    add  eax, [item_stock+esi*4]
    cmp  eax, MAXSTOCK
    ja   .full
    mov  [item_stock+esi*4], eax
    PUTS s_rsok
    jmp  .again
.full:
    PUTS s_rsfull
    jmp  .again
.bad:
    PUTS s_invalid
    jmp  .again

; ---- option 4: sales report ------------------------------------------------
do_report:
    PUTS s_rephdr
    xor  ebx, ebx                   ; product index
    xor  ebp, ebp                   ; total units
    xor  edi, edi                   ; best seller index
    mov  dword [rc_sub], 0          ; highest units seen so far
.row:
    cmp  ebx, NITEMS
    jae  .summary
    PUTS s_sp2
    mov  eax, ebx
    imul eax, eax, NAMELEN
    lea  ecx, [item_names+eax]
    mov  edx, NAMELEN
    call write_buf
    PUTS s_tab
    mov  eax, [sold+ebx*4]
    add  ebp, eax
    cmp  eax, [rc_sub]              ; new best seller?
    jbe  .notbest
    mov  [rc_sub], eax
    mov  edi, ebx
.notbest:
    call print_uint
    PUTS s_tab
    mov  eax, [sold+ebx*4]
    mul  dword [item_price+ebx*4]   ; units * price
    call print_money
    PUTS s_nl
    inc  ebx
    jmp  .row
.summary:
    PUTS s_rule
    PUTS s_rtxn
    mov  eax, [txn_count]
    call print_uint
    PUTS s_nl
    PUTS s_runits
    mov  eax, ebp
    call print_uint
    PUTS s_nl
    PUTS s_rrev
    mov  eax, [total_sales]
    call print_money
    PUTS s_nl
    cmp  dword [txn_count], 0
    je   .nosales                   ; avoid divide-by-zero
    PUTS s_ravg
    xor  edx, edx
    mov  eax, [total_sales]
    div  dword [txn_count]          ; average = revenue / transactions
    call print_money
    PUTS s_nl
    PUTS s_rbest
    mov  eax, edi
    imul eax, eax, NAMELEN
    lea  ecx, [item_names+eax]
    mov  edx, NAMELEN
    call write_buf
    PUTS s_nl
    jmp  menu
.nosales:
    PUTS s_nosales
    jmp  menu

; ============================================================================
;  Subroutines
; ============================================================================

; ---- checkout: receipt, discount, tax, payment ------------------------------
checkout:
    PUTS s_rcpt
    xor  ebx, ebx                   ; cart line index
    xor  ebp, ebp                   ; running subtotal (cents)
.line:                              ; loop over every cart line
    cmp  ebx, [cart_count]
    jae  .totals
    mov  esi, [cart_item+ebx*4]
    mov  edi, [cart_qty+ebx*4]
    PUTS s_sp2
    mov  eax, esi
    imul eax, eax, NAMELEN
    lea  ecx, [item_names+eax]
    mov  edx, NAMELEN
    call write_buf
    PUTS s_x
    mov  eax, edi
    call print_uint
    PUTS s_at
    mov  eax, [item_price+esi*4]
    call print_money
    PUTS s_eq
    mov  eax, [item_price+esi*4]
    mul  edi                        ; line total = price * qty
    add  ebp, eax
    call print_money
    PUTS s_nl
    inc  ebx
    jmp  .line

.totals:
    mov  [rc_sub], ebp
    xor  ecx, ecx                   ; tiered discount
    cmp  ebp, 50000                 ; >= RM500 -> 10%
    jb   .tier2
    mov  ecx, 10
    jmp  .havepct
.tier2:
    cmp  ebp, 10000                 ; >= RM100 -> 5%
    jb   .havepct
    mov  ecx, 5
.havepct:
    mov  [rc_pct], ecx
    mov  ebx, 100
    mov  eax, ebp
    mul  ecx
    div  ebx                        ; discount = subtotal * pct / 100
    mov  [rc_disc], eax
    mov  edi, ebp
    sub  edi, eax                   ; net amount
    mov  eax, edi
    xor  edx, edx
    mov  ecx, TAXRATE
    mul  ecx
    div  ebx                        ; tax = net * 6 / 100
    mov  [rc_tax], eax
    add  eax, edi
    mov  [rc_total], eax

    PUTS s_subtot
    mov  eax, [rc_sub]
    call print_money
    PUTS s_nl
    PUTS s_disc
    mov  eax, [rc_pct]
    call print_uint
    PUTS s_disc2
    mov  eax, [rc_disc]
    call print_money
    PUTS s_nl
    PUTS s_tax
    mov  eax, [rc_tax]
    call print_money
    PUTS s_nl
    PUTS s_total
    mov  eax, [rc_total]
    call print_money
    PUTS s_nl

.pay:
    PUTS s_pay
    call read_money                 ; eax = cents, or -1 if invalid
    cmp  eax, -1
    je   .badpay
    test eax, eax
    jz   .cancel
    cmp  eax, [rc_total]
    jb   .short
    sub  eax, [rc_total]            ; change due
    push eax
    PUTS s_change
    pop  eax
    call print_money
    PUTS s_nl

    mov  eax, [rc_total]            ; record the sale
    add  [total_sales], eax
    inc  dword [txn_count]
    xor  ebx, ebx
.tally:
    cmp  ebx, [cart_count]
    jae  .done
    mov  esi, [cart_item+ebx*4]
    mov  eax, [cart_qty+ebx*4]
    add  [sold+esi*4], eax
    inc  ebx
    jmp  .tally
.done:
    PUTS s_thanks
    ret
.short:
    PUTS s_short
    jmp  .pay
.badpay:
    PUTS s_invalid
    jmp  .pay
.cancel:                            ; give reserved stock back
    xor  ebx, ebx
.restore:
    cmp  ebx, [cart_count]
    jae  .cancelled
    mov  esi, [cart_item+ebx*4]
    mov  eax, [cart_qty+ebx*4]
    add  [item_stock+esi*4], eax
    inc  ebx
    jmp  .restore
.cancelled:
    PUTS s_cancel
    ret

; ---- show_inventory: table of all products ---------------------------------
show_inventory:
    pusha
    PUTS s_invhdr
    xor  ebx, ebx
.row:
    cmp  ebx, NITEMS
    jae  .end
    PUTS s_sp2
    lea  eax, [ebx+1]
    call print_uint
    PUTS s_dotsp
    mov  eax, ebx
    imul eax, eax, NAMELEN
    lea  ecx, [item_names+eax]
    mov  edx, NAMELEN
    call write_buf
    mov  eax, [item_price+ebx*4]
    call print_money
    PUTS s_tab
    mov  eax, [item_stock+ebx*4]
    call print_uint
    cmp  eax, LOWSTOCK
    jae  .ok
    PUTS s_low
.ok:
    PUTS s_nl
    inc  ebx
    jmp  .row
.end:
    popa
    ret

; ---- write_buf: ecx = buffer, edx = length ---------------------------------
write_buf:
    pusha
    mov  eax, SYS_WRITE
    mov  ebx, 1
    int  0x80
    popa
    ret

; ---- print_str: esi = zero-terminated string -------------------------------
print_str:
    pusha
    mov  ecx, esi
    xor  edx, edx
.len:
    cmp  byte [esi+edx], 0
    je   .out
    inc  edx
    jmp  .len
.out:
    mov  eax, SYS_WRITE
    mov  ebx, 1
    int  0x80
    popa
    ret

; ---- print_uint: eax = unsigned number -------------------------------------
print_uint:
    pusha
    mov  edi, numbuf+11
    mov  byte [edi], 0
    mov  ebx, 10
.digit:                             ; repeated division by 10
    xor  edx, edx
    div  ebx
    add  dl, '0'
    dec  edi
    mov  [edi], dl
    test eax, eax
    jnz  .digit
    mov  esi, edi
    call print_str
    popa
    ret

; ---- print_money: eax = cents, prints "RM d.dd" ----------------------------
print_money:
    pusha
    xor  edx, edx
    mov  ebx, 100
    div  ebx                        ; eax = ringgit, edx = cents
    push edx
    PUTS s_rm
    call print_uint
    PUTS s_dot
    pop  eax
    cmp  eax, 10
    jae  .two
    PUTS s_zero                     ; leading zero for 0..9 cents
.two:
    call print_uint
    popa
    ret

; ---- read_line: fills inbuf (ends with 10,0); exits cleanly at end of input --
;      reads one byte at a time so piped input is consumed line by line
read_line:
    push ebx
    push ecx
    push edx
    push esi
    xor  esi, esi                   ; characters stored so far
.getc:
    mov  eax, SYS_READ
    xor  ebx, ebx
    mov  ecx, numbuf                ; 1-byte scratch
    mov  edx, 1
    int  0x80
    test eax, eax
    jle  .eof
    mov  al, [numbuf]
    cmp  al, 10
    je   .endline
    cmp  esi, 62
    jae  .getc                      ; discard overflow characters
    mov  [inbuf+esi], al
    inc  esi
    jmp  .getc
.endline:
    mov  byte [inbuf+esi], 10
    mov  byte [inbuf+esi+1], 0
    pop  esi
    pop  edx
    pop  ecx
    pop  ebx
    ret
.eof:
    PUTS s_bye
    xor  ebx, ebx
    jmp  exit_code

; ---- read_int: eax = parsed number, or -1 when input is not a number --------
read_int:
    push ebx
    push ecx
    push esi
    call read_line
    mov  esi, inbuf
    xor  eax, eax
    xor  ecx, ecx                   ; digit counter
.next:
    movzx ebx, byte [esi]
    sub  bl, '0'
    cmp  bl, 9
    ja   .end                       ; not a digit
    imul eax, eax, 10
    add  eax, ebx
    inc  ecx
    inc  esi
    cmp  ecx, 9
    jbe  .next
    jmp  .bad                       ; more than 9 digits
.end:
    test ecx, ecx
    jz   .bad                       ; no digits at all
    cmp  byte [esi], 10             ; digits must end the line ("5.5", "3x"
    je   .ret                       ; are rejected)
    cmp  byte [esi], 13
    je   .ret
.bad:
    mov  eax, -1
.ret:
    pop  esi
    pop  ecx
    pop  ebx
    ret

; ---- read_money: eax = cents parsed from "RM" or "RM.sen", or -1 if invalid --
read_money:
    push ebx
    push ecx
    push esi
    push edi
    call read_line
    mov  esi, inbuf
    xor  eax, eax
    xor  ecx, ecx                   ; digit counter
.rm:
    movzx ebx, byte [esi]
    sub  bl, '0'
    cmp  bl, 9
    ja   .rmend
    imul eax, eax, 10
    add  eax, ebx
    inc  ecx
    inc  esi
    cmp  ecx, 7
    jbe  .rm
    jmp  .bad                       ; more than 7 integer digits
.rmend:
    test ecx, ecx
    jz   .bad
    imul eax, eax, 100              ; ringgit -> cents
    cmp  byte [esi], '.'
    jne  .chkend                    ; no decimal part
    inc  esi
    xor  ecx, ecx
    xor  edi, edi                   ; sen
.fr:
    movzx ebx, byte [esi]
    sub  bl, '0'
    cmp  bl, 9
    ja   .frend
    cmp  ecx, 2
    jae  .bad                       ; more than 2 decimals
    imul edi, edi, 10
    add  edi, ebx
    inc  ecx
    inc  esi
    jmp  .fr
.frend:
    test ecx, ecx
    jz   .bad                       ; "5." is not valid
    cmp  ecx, 1
    jne  .addsen
    imul edi, edi, 10               ; "5.5" means 50 sen
.addsen:
    add  eax, edi
.chkend:
    cmp  byte [esi], 10             ; nothing may follow the amount
    je   .ret
    cmp  byte [esi], 13
    je   .ret
.bad:
    mov  eax, -1
.ret:
    pop  edi
    pop  esi
    pop  ecx
    pop  ebx
    ret
