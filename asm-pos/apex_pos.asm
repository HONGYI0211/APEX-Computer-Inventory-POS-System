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

DEFAULTITEMS equ 5      ; products that ship with the system
MAXITEMS equ 12         ; capacity of the product table
NAMELEN  equ 12         ; fixed width of a product name field
MAXCART  equ 10         ; maximum lines in one sale
MAXSTOCK equ 999        ; upper limit for stock
LOWSTOCK equ 5          ; stock below this shows as "Low Stock"
MAXPRICE equ 9999999    ; highest price for a new product (RM 99999.99)
CARTLIMIT equ 40000000  ; highest value of one sale in cents (RM 400000.00)
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

; product table (parallel arrays); the first DEFAULTITEMS entries are the
; built-in products, the remaining slots are filled by "Add new product"
item_count  dd DEFAULTITEMS
item_names:
    NAME "Laptop"
    NAME "Monitor"
    NAME "Keyboard"
    NAME "Mouse"
    NAME "USB Flash"
    times (MAXITEMS-DEFAULTITEMS)*NAMELEN db ' '
item_price  dd 299900, 59900, 8900, 4500, 2500      ; in cents
    times MAXITEMS-DEFAULTITEMS dd 0
item_stock  dd 5, 8, 20, 30, 50                     ; modified at run time
    times MAXITEMS-DEFAULTITEMS dd 0

s_banner    db 27,"[1;36m",10
            db "  ======================================================",10
            db "      APEX COMPUTER SHOP  -  POS & INVENTORY SYSTEM",10
            db "  ======================================================",27,"[0m",10,0
s_pin       db "  Enter staff PIN: ",0
s_wrong     db 27,"[31m  Wrong PIN.",27,"[0m",10,0
s_locked    db 27,"[31m  Too many failed attempts. System locked.",27,"[0m",10,0
s_welcome   db 27,"[32m  Login successful.",27,"[0m",10,0

s_menu      db 10,27,"[1m  ---------------------- MAIN MENU ---------------------",27,"[0m",10
            db "   1. New sale",10
            db "   2. View inventory",10
            db "   3. Restock item",10
            db "   4. Add new product",10
            db "   5. Sales report",10
            db "   6. Exit",10
            db "  Choice: ",0
s_invalid   db 27,"[31m  Invalid input, try again.",27,"[0m",10,0
s_bye       db 10,"  Session closed. Goodbye!",10,0

s_reset     db 27,"[0m",0
s_invhdr    db 10,27,"[33m"
            db "  +-----+--------------+--------------+-------+--------------+",10
            db "  | No. | Product      |        Price | Stock | Status       |",10
s_tsep      db "  +-----+--------------+--------------+-------+--------------+",10,0
s_instock   db "In Stock    ",0
s_lowstock  db "Low Stock   ",0
s_outstock  db "Out of Stock",0
s_sp2       db "  ",0
s_space     db " ",0
s_rowb      db "  | ",0
s_rowc      db " | ",0
s_rowend    db " |",0
s_nl        db 10,0

s_selitem   db "  Item no. (0 = checkout, ",0
s_selitem2  db " = back to menu): ",0
s_qty       db "  Quantity: ",0
s_added     db 27,"[32m  Added to cart.",27,"[0m",10,0
s_nostock   db 27,"[31m  Not enough stock for that quantity.",27,"[0m",10,0
s_toobig    db 27,"[31m  Sale value limit reached - checkout first.",27,"[0m",10,0
s_back      db "  Back to main menu (cart cleared, stock restored).",10,0
s_cartfull  db "  Cart is full - proceeding to checkout.",10,0

s_rcpt      db 10,"  ======================== RECEIPT =========================",10,0
s_x         db " x ",0
s_at        db " @ ",0
s_eq        db " = ",0
s_subtot    db "  ----------------------------------------------------------",10
            db "  Subtotal                                : ",0
s_disc      db "  Less: Discount (",0
s_discpad   db "                    : ",0
s_pctb      db "%)",0
s_tax       db "  Tax (6%)                                : ",0
s_total     db "  TOTAL                                   : ",0
s_pay       db 10,"  Cash received in RM, e.g. 2861.04 (0 = cancel): ",0
s_short     db 27,"[31m  Insufficient payment.",27,"[0m",10,0
s_change    db "  Change                                  : ",0
s_thanks    db 27,"[32m  Payment complete. Thank you!",27,"[0m",10,0
s_cancel    db "  Sale cancelled - stock restored.",10,0

s_apname    db "  New product name (max 12 characters, empty = cancel): ",0
s_approce   db "  Price in RM, e.g. 49.90 (0 = cancel): ",0
s_apstock   db "  Initial stock (0-999): ",0
s_apfull    db 27,"[31m  Product list is full (max 12 products).",27,"[0m",10,0
s_badname   db 27,"[31m  Invalid name: use 1-12 printable characters.",27,"[0m",10,0
s_badprice  db 27,"[31m  Price must be between RM 0.01 and RM 99999.99.",27,"[0m",10,0
s_badstock  db 27,"[31m  Stock must be a whole number from 0 to 999.",27,"[0m",10,0
s_apdone    db 27,"[32m  Product added.",27,"[0m",10,0
s_rsitem    db "  Restock which item (0 = back): ",0
s_rsqty     db "  Units to add: ",0
s_rsfull    db 27,"[31m  Stock would exceed the limit of 999.",27,"[0m",10,0
s_rsok      db 27,"[32m  Stock updated.",27,"[0m",10,0

s_rephdr    db 10,"  ================ SALES REPORT ================",10
            db 27,"[33m"
            db "  +--------------+------------+----------------+",10
            db "  | Product      | Units sold |        Revenue |",10
s_rsep      db "  +--------------+------------+----------------+",10,0
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
moneybuf    resb 20
cart_item   resd MAXCART            ; product index per cart line
cart_qty    resd MAXCART            ; quantity per cart line
cart_count  resd 1
cart_total  resd 1                  ; value of the cart in cents
sold        resd MAXITEMS           ; units sold per product
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
    je   do_addproduct
    cmp  eax, 5
    je   do_report
    cmp  eax, 6
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
    mov  dword [cart_total], 0
    call show_inventory
.item:
    PUTS s_selitem
    mov  eax, [item_count]
    inc  eax                        ; "back to menu" is always the number after
    call print_uint                 ; the last product
    PUTS s_selitem2
    call read_int
    test eax, eax
    jz   .checkout                  ; 0 -> finish cart
    mov  ecx, [item_count]
    cmp  eax, ecx
    jbe  .picked                    ; 1..item_count = a product
    inc  ecx
    cmp  eax, ecx
    je   .back                      ; item_count+1 -> abandon cart, back to menu
    jmp  .bad                       ; anything else, including -1
.picked:
    dec  eax
    mov  esi, eax                   ; esi = product index
    PUTS s_qty
    call read_int
    test eax, eax
    jle  .bad
    mov  edi, eax                   ; edi = quantity
    cmp  edi, [item_stock+esi*4]
    ja   .nostock
    mov  eax, [item_price+esi*4]    ; keep the cart value inside 32 bits
    mul  edi
    test edx, edx
    jnz  .toobig
    add  eax, [cart_total]
    jc   .toobig
    cmp  eax, CARTLIMIT
    ja   .toobig
    mov  [cart_total], eax
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
.toobig:
    PUTS s_toobig
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
    cmp  eax, [item_count]
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

; ---- option 4: add new product ---------------------------------------------
do_addproduct:
    cmp  dword [item_count], MAXITEMS
    jb   .name
    PUTS s_apfull
    jmp  menu
.name:
    PUTS s_apname
    call read_line
    mov  esi, inbuf
    xor  ecx, ecx                   ; ecx = name length
.scan:                              ; accept 1..NAMELEN printable characters
    mov  al, [esi+ecx]
    cmp  al, 10
    je   .scanned
    cmp  al, 13
    je   .scanned
    cmp  al, 32
    jb   .badname
    cmp  al, 126
    ja   .badname
    inc  ecx
    cmp  ecx, NAMELEN
    jbe  .scan
.badname:
    PUTS s_badname
    jmp  .name
.scanned:
    test ecx, ecx
    jz   menu                       ; empty name = cancel
    mov  edx, ecx                   ; copy the name into the next free slot and
    mov  eax, [item_count]          ; pad it with spaces up to NAMELEN
    imul eax, eax, NAMELEN
    lea  edi, [item_names+eax]
    rep  movsb
    mov  ecx, NAMELEN
    sub  ecx, edx
    mov  al, ' '
    rep  stosb
.price:
    PUTS s_approce
    call read_money
    cmp  eax, -1
    je   .badprice
    test eax, eax
    jz   menu                       ; 0 = cancel
    cmp  eax, MAXPRICE
    ja   .badprice
    mov  edi, eax                   ; edi = price in cents
.stock:
    PUTS s_apstock
    call read_int
    cmp  eax, MAXSTOCK
    ja   .badstock                  ; also catches -1
    mov  ecx, [item_count]          ; commit the new product
    mov  [item_price+ecx*4], edi
    mov  [item_stock+ecx*4], eax
    mov  dword [sold+ecx*4], 0
    inc  ecx
    mov  [item_count], ecx
    PUTS s_apdone
    call show_inventory
    jmp  menu
.badprice:
    PUTS s_badprice
    jmp  .price
.badstock:
    PUTS s_badstock
    jmp  .stock

; ---- option 5: sales report ------------------------------------------------
do_report:
    PUTS s_rephdr
    xor  ebx, ebx                   ; product index
    xor  ebp, ebp                   ; total units
    xor  edi, edi                   ; best seller index
    mov  dword [rc_sub], 0          ; highest units seen so far
.row:
    cmp  ebx, [item_count]
    jae  .summary
    PUTS s_rowb
    mov  eax, ebx
    imul eax, eax, NAMELEN
    lea  ecx, [item_names+eax]
    mov  edx, NAMELEN
    call write_buf
    PUTS s_rowc
    mov  eax, [sold+ebx*4]
    add  ebp, eax
    cmp  eax, [rc_sub]              ; new best seller?
    jbe  .notbest
    mov  [rc_sub], eax
    mov  edi, ebx
.notbest:
    mov  ecx, 10
    call print_uint_w
    PUTS s_rowc
    mov  eax, [sold+ebx*4]
    mul  dword [item_price+ebx*4]   ; units * price
    mov  ecx, 14
    call print_money_w
    PUTS s_rowend
    PUTS s_nl
    inc  ebx
    jmp  .row
.summary:
    PUTS s_rsep
    PUTS s_reset
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
    mov  ecx, 5
    call print_uint_w
    PUTS s_at
    mov  eax, [item_price+esi*4]
    mov  ecx, 16
    call print_money_w
    PUTS s_eq
    mov  eax, [item_price+esi*4]
    mul  edi                        ; line total = price * qty
    add  ebp, eax
    mov  ecx, 16
    call print_money_w
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
    mov  ecx, 16
    call print_money_w
    PUTS s_nl
    PUTS s_disc
    mov  eax, [rc_pct]
    call print_uint
    PUTS s_pctb
    cmp  dword [rc_pct], 10
    jae  .wide
    PUTS s_space                    ; keep the colon in line for 1-digit rates
.wide:
    PUTS s_discpad
    mov  eax, [rc_disc]
    mov  ecx, 16
    call print_money_w
    PUTS s_nl
    PUTS s_tax
    mov  eax, [rc_tax]
    mov  ecx, 16
    call print_money_w
    PUTS s_nl
    PUTS s_total
    mov  eax, [rc_total]
    mov  ecx, 16
    call print_money_w
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
    mov  ecx, 16
    call print_money_w
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
    cmp  ebx, [item_count]
    jae  .end
    PUTS s_rowb
    lea  eax, [ebx+1]
    mov  ecx, 3                     ; item numbers up to 12 stay in line
    call print_uint_w
    PUTS s_rowc
    mov  eax, ebx
    imul eax, eax, NAMELEN
    lea  ecx, [item_names+eax]
    mov  edx, NAMELEN
    call write_buf
    PUTS s_rowc
    mov  eax, [item_price+ebx*4]
    mov  ecx, 12
    call print_money_w
    PUTS s_rowc
    mov  eax, [item_stock+ebx*4]
    mov  ecx, 5
    call print_uint_w
    PUTS s_rowc
    mov  eax, [item_stock+ebx*4]
    mov  esi, s_outstock
    test eax, eax
    jz   .status                    ; 0 units  -> Out of Stock
    mov  esi, s_lowstock
    cmp  eax, LOWSTOCK
    jb   .status                    ; below 5  -> Low Stock
    mov  esi, s_instock
.status:
    call print_str
    PUTS s_rowend
    PUTS s_nl
    inc  ebx
    jmp  .row
.end:
    PUTS s_tsep
    PUTS s_reset
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

; ---- print_padded: esi = string, ecx = field width (right-aligned) ---------
print_padded:
    pusha
    xor  edx, edx
.len:
    cmp  byte [esi+edx], 0
    je   .pad
    inc  edx
    jmp  .len
.pad:
    sub  ecx, edx                   ; spaces needed = width - length
    jbe  .print
.sp:
    PUTS s_space
    loop .sp
.print:
    call print_str
    popa
    ret

; ---- print_uint_w: eax = number, ecx = field width -------------------------
print_uint_w:
    pusha
    mov  edi, numbuf+11
    mov  byte [edi], 0
    mov  ebx, 10
.digit:
    xor  edx, edx
    div  ebx
    add  dl, '0'
    dec  edi
    mov  [edi], dl
    test eax, eax
    jnz  .digit
    mov  esi, edi
    call print_padded
    popa
    ret

; ---- print_money_w: eax = cents, ecx = field width for "RM d.dd" -----------
print_money_w:
    pusha
    mov  edi, moneybuf
    mov  byte [edi], 'R'
    mov  byte [edi+1], 'M'
    mov  byte [edi+2], ' '
    add  edi, 3
    xor  edx, edx
    mov  ebx, 100
    div  ebx                        ; eax = ringgit, edx = sen
    push edx
    mov  esi, numbuf+11             ; ringgit digits, built backwards
    mov  ebx, 10
.digit:
    xor  edx, edx
    div  ebx
    add  dl, '0'
    dec  esi
    mov  [esi], dl
    test eax, eax
    jnz  .digit
.copy:
    cmp  esi, numbuf+11
    jae  .sen
    mov  al, [esi]
    mov  [edi], al
    inc  esi
    inc  edi
    jmp  .copy
.sen:
    mov  byte [edi], '.'
    pop  eax
    xor  edx, edx
    mov  ebx, 10
    div  ebx                        ; eax = tens of sen, edx = units
    add  al, '0'
    add  dl, '0'
    mov  [edi+1], al
    mov  [edi+2], dl
    mov  byte [edi+3], 0
    mov  esi, moneybuf
    call print_padded
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
