# APEX Computer Shop – Inventory & POS (NASM, 32-bit x86, Linux)

A console point-of-sale and inventory system written in pure assembly (no libc, only `int 0x80` system calls).

## Build & run (Linux, or WSL)
```bash
sudo apt install nasm          # once (on 64-bit systems ld handles -m elf_i386)
make run                       # or:
nasm -f elf32 apex_pos.asm -o apex_pos.o && ld -m elf_i386 apex_pos.o -o apex_pos && ./apex_pos
```
Staff PIN: **1234** (3 attempts, then locked).

## Ubuntu (WSL) setup guide

### Guide 1: Ubuntu's own folder (`~/asm-pos`)
1. Go to the folder: `cd ~/asm-pos`
2. Check the source file is there: `ls` (you should see `apex_pos.asm`; if missing, create it with `nano apex_pos.asm` and paste the code, save with Ctrl+O then Enter, exit with Ctrl+X)
3. Assemble: `nasm -f elf32 apex_pos.asm -o apex_pos.o`
4. Link: `ld -m elf_i386 apex_pos.o -o apex_pos`
5. Run, then enter the PIN `1234`: `./apex_pos`

### Guide 2: the D: drive (`/mnt/d/...`)
1. Go to the folder: `cd /mnt/d/Coding/APEX-Computer-Inventory-POS-System/asm-pos`
2. Check the files: `ls` (you should see `apex_pos.asm` and `Makefile`)
3. Assemble: `nasm -f elf32 apex_pos.asm -o apex_pos.o`
4. Link: `ld -m elf_i386 apex_pos.o -o apex_pos`
5. Run: `./apex_pos`

In either folder, steps 3-5 can be done with `make run` if `make` is installed.

## Functionality
| Menu | Feature |
|---|---|
| Login | PIN check, 3-attempt loop, lock-out |
| 1 New sale | Add items to a cart (max 10 lines), stock check, receipt, tiered discount, 6 % tax, cash payment, change |
| 2 View inventory | Table of all products with price, stock and status (In Stock / Low Stock / Out of Stock) |
| 3 Restock | Add units to a product (max 999) |
| 4 Add new product | Enter name (max 12 characters), price and initial stock; the 5 default products are kept (table holds up to 12) |
| 5 Sales report | Units/revenue per product, totals, average sale, best seller |
| 6 Exit | Clean exit |

Discount rules: subtotal ≥ RM100 → 5 %, ≥ RM500 → 10 %. Cancelling payment returns reserved stock.

## Where the required constructs are used
* **Arithmetic** – `mul/imul` (line total, RM→cents), `div` (discount %, tax %, average sale, digit extraction for printing), `add/sub` (subtotal, stock, change). Money is held as integer cents.
* **Loops** – `loop` (PIN compare, padding spaces); `rep movsb/stosb` (copying and padding a new product name); `cmp/jae/jmp` loops over the cart, inventory table, report rows, digit conversion, input parsing, input retries.
* **Jumps** – conditional (`je jne ja jb jle jz ...`) for validation, stock checks, discount tiers, divide-by-zero guard; unconditional `jmp` for the menu loop and retries; `call/ret` for subroutines.

## Additional control and robustness features
* **Access control** – staff PIN with 3 attempts, then the system locks and exits with an error code.
* **Input validation** – menu choices, item numbers, quantities, stock levels and cash amounts are checked. Letters, empty input, zero, out-of-range values, over-long numbers and trailing characters (for example `5.5` or `3x` where a whole number is needed) are rejected and the user is asked again. Product names must be 1-12 printable characters.
* **Stock control** – a sale cannot exceed available stock; stock is reserved when an item is added to the cart and returned if the sale is cancelled. The Status column shows "In Stock", "Low Stock" (below 5 units) or "Out of Stock" (0 units).
* **Cart control** – during a sale, `0` goes to checkout and the number after the last product returns to the main menu, cancelling the cart and restoring its stock.
* **Payment control** – cash may be entered with sen (for example `2861.04`); insufficient or invalid amounts are rejected and entering `0` cancels the sale and restores stock.
* **Product management** – new products can be added at run time (name, price, initial stock) while the 5 default products are kept; entering an empty name or a price of `0` cancels, and a full table (12 products) is reported.
* **Limits** – the cart holds at most 10 lines, one sale is capped at RM 400000 (keeps the 32-bit arithmetic from overflowing), stock at 999 units, a new product price at RM 99999.99, and the product table at 12 products.
* **Error safety** – divide-by-zero guard for the average sale in the sales report, and a clean exit if input ends.
* **Business rules** – tiered discounts (5 % / 10 %) and 6 % tax.
* **Reports** – per-product units and revenue (before discount and tax), transactions, units sold, gross revenue (what customers paid), average sale and best seller.
* **Usability** – coloured messages, yellow bordered tables with right-aligned columns, and money shown in RM with sen.

## System flowchart
```mermaid
flowchart TD
    A([Start]) --> B[/Enter staff PIN/]
    B --> C{PIN correct?}
    C -->|No| D{Attempts left?}
    D -->|Yes| B
    D -->|No| X(["System locked - exit"])
    C -->|Yes| M[Show main menu]
    M --> I[/Enter menu choice/]
    I --> J{Choice?}
    J -->|"1 New sale"| S0["Clear cart, show inventory"]
    J -->|"2 Inventory"| V[Show inventory table]
    V --> M
    J -->|"3 Restock"| R0[Show inventory table]
    J -->|"4 Add product"| N0{Product table full?}
    J -->|"5 Report"| P1["Print units and revenue per product"]
    J -->|"6 Exit"| E(["Goodbye - exit"])
    J -->|Other| W[Invalid input]
    W --> M

    S0 --> S1[/Enter item number/]
    S1 --> S2{"Item = 0?"}
    S2 -->|Yes| S3{Cart empty?}
    S3 -->|Yes| M
    S3 -->|No| K0["Line total = price × qty, add to subtotal"]
    S2 -->|No| S4{Back to menu number?}
    S4 -->|Yes| S5["Restore stock, clear cart"]
    S5 --> M
    S4 -->|No| S6{Valid product number?}
    S6 -->|No| S1
    S6 -->|Yes| S7[/Enter quantity/]
    S7 --> S8{"Qty ≥ 1 and stock enough?"}
    S8 -->|No| S1
    S8 -->|Yes| S9{"Sale value ≤ RM400000?"}
    S9 -->|No| S1
    S9 -->|Yes| S10["Add line to cart, reserve stock"]
    S10 --> S11{"Cart full (10 lines)?"}
    S11 -->|No| S1
    S11 -->|Yes| K0

    K0 --> K1{"Subtotal ≥ RM500?"}
    K1 -->|Yes| K2["Discount 10%"]
    K1 -->|No| K3{"Subtotal ≥ RM100?"}
    K3 -->|Yes| K4["Discount 5%"]
    K3 -->|No| K5[No discount]
    K2 --> K6["Tax 6% of net, print total"]
    K4 --> K6
    K5 --> K6
    K6 --> K7[/Enter cash received/]
    K7 --> K8{Valid amount?}
    K8 -->|No| K7
    K8 -->|Yes| K9{"Cash = 0?"}
    K9 -->|Yes| K10["Cancel sale, restore stock"]
    K10 --> M
    K9 -->|No| K11{"Cash ≥ total?"}
    K11 -->|No| K7
    K11 -->|Yes| K12["Print change, record sale"]
    K12 --> M

    R0 --> R1[/Enter item number/]
    R1 --> R2{"Item = 0?"}
    R2 -->|Yes| M
    R2 -->|No| R3{Valid product number?}
    R3 -->|No| R1
    R3 -->|Yes| R4[/Enter units to add/]
    R4 --> R5{"Units ≥ 1 and new stock ≤ 999?"}
    R5 -->|No| R1
    R5 -->|Yes| R6[Update stock]
    R6 --> R1

    N0 -->|Yes| N1[Show list full message]
    N1 --> M
    N0 -->|No| N2[/Enter product name/]
    N2 --> N3{"Name printable, ≤ 12 chars?"}
    N3 -->|No| N2
    N3 -->|Yes| N4{Name empty?}
    N4 -->|Yes| M
    N4 -->|No| N5[Store padded name in next slot]
    N5 --> N6[/Enter price/]
    N6 --> N7{"Price = 0?"}
    N7 -->|Yes| M
    N7 -->|No| N8{"Valid and ≤ RM99999.99?"}
    N8 -->|No| N6
    N8 -->|Yes| N9[/Enter initial stock/]
    N9 --> N10{"Stock 0 to 999?"}
    N10 -->|No| N9
    N10 -->|Yes| N11["Save product, count + 1"]
    N11 --> N12[Show inventory table]
    N12 --> M

    P1 --> P2["Print transactions, units, gross revenue"]
    P2 --> P3{"Transactions = 0?"}
    P3 -->|Yes| P4[Show no sales message]
    P4 --> M
    P3 -->|No| P5["Average = revenue ÷ transactions"]
    P5 --> P6[Show best seller]
    P6 --> M

    classDef term fill:#d5e8d4,stroke:#82b366
    classDef io fill:#ffe6cc,stroke:#d79b00
    classDef proc fill:#dae8fc,stroke:#6c8ebf
    classDef dec fill:#fff2cc,stroke:#d6b656
    classDef ok fill:#d5e8d4,stroke:#82b366
    classDef err fill:#f8cecc,stroke:#b85450
    class A,E term
    class B,I,S1,S7,K7,R1,R4,N2,N6,N9 io
    class M,V,S0,R0,P1,P2,P4,P5,P6,K0,K2,K4,K5,K6,N5,N12 proc
    class C,D,J,S2,S3,S4,S6,S8,S9,S11,K1,K3,K8,K9,K11,R2,R3,R5,N0,N3,N4,N7,N8,N10,P3 dec
    class S10,K12,R6,N11 ok
    class X,W,S5,K10,N1 err
```

### Subroutine flow (number printing)
`print_money_w` and `print_uint_w` use the same steps and then pad the text on the left to a fixed width, which keeps the table and receipt columns aligned.

```mermaid
flowchart LR
    A[print_money cents] --> B[div by 100 -> RM and sen]
    B --> C[print_uint RM]
    C --> D[print '.']
    D --> E{sen < 10?}
    E -- Yes --> F[print '0']
    E -- No --> G
    F --> G[print_uint sen]
```
