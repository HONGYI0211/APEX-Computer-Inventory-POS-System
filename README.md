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
* **Loops** – `loop` (PIN compare); `cmp/jae/jmp` loops over the cart, inventory table, report rows, digit conversion, input parsing, payment retry.
* **Jumps** – conditional (`je jne ja jb jle jz ...`) for validation, stock checks, discount tiers, divide-by-zero guard; unconditional `jmp` for the menu loop and retries; `call/ret` for subroutines.

## Additional control and robustness features
* **Access control** – staff PIN with 3 attempts, then the system locks and exits with an error code.
* **Input validation** – menu choices, item numbers, quantities and cash amounts are checked; letters, empty input, zero, out-of-range values and over-long numbers are rejected and the user is asked again.
* **Stock control** – a sale cannot exceed available stock; stock is reserved when an item is added to the cart and returned if the sale is cancelled; items below 5 units show as "Low Stock" and 0 units as "Out of Stock". During a sale, the number after the last product returns to the main menu and cancels the cart.
* **Payment control** – insufficient cash is rejected and entering 0 cancels the sale.
* **Limits** – the cart holds at most 10 lines, a sale is capped at RM 400000, stock at 999 units, a new product price at RM 99999.99, and the product table at 12 products.
* **Error safety** – divide-by-zero guard in the sales report and a clean exit if input ends.
* **Business rules** – tiered discounts and 6 % tax.
* **Reports** – totals, average sale and best seller.
* **Usability** – coloured messages and money shown in RM with sen.

## System flowchart
```mermaid
flowchart TD
    A([Start]) --> B[/Enter PIN/]
    B --> C{PIN correct?}
    C -- No --> D{Attempts left?}
    D -- Yes --> B
    D -- No --> X([Locked - exit])
    C -- Yes --> M[Show main menu]
    M --> I[/Read choice/]
    I --> J{Choice}
    J -- 1 --> S1[Show inventory]
    J -- 2 --> V[Show inventory] --> M
    J -- 3 --> R1[Show inventory]
    J -- 4 --> N1[/Name, price, initial stock/]
    J -- 5 --> P[Sales report] --> M
    J -- 6 --> E([Exit])
    J -- other --> W[Invalid input] --> M

    N1 --> N2{Valid and table not full?}
    N2 -- No --> N1
    N2 -- Yes --> N3[Add product to table] --> M

    S1 --> S2[/Item no. and quantity/]
    S2 --> S3{Item = 0?}
    S3 -- No --> S9{Back to menu?}
    S9 -- Yes --> S10[Cancel cart, restore stock] --> M
    S9 -- No --> S4{Valid item and qty?}
    S4 -- No --> S2
    S4 -- Yes --> S5{Stock enough?}
    S5 -- No --> S2
    S5 -- Yes --> S6[Add to cart, reserve stock]
    S6 --> S7{Cart full?}
    S7 -- No --> S2
    S7 -- Yes --> K
    S3 -- Yes --> S8{Cart empty?}
    S8 -- Yes --> M
    S8 -- No --> K[Checkout]

    K --> K1[Loop cart lines: price x qty, subtotal]
    K1 --> K2{Subtotal >= 500?}
    K2 -- Yes --> K3[10% discount]
    K2 -- No --> K4{Subtotal >= 100?}
    K4 -- Yes --> K5[5% discount]
    K4 -- No --> K6[No discount]
    K3 & K5 & K6 --> K7[Tax 6%, total]
    K7 --> K8[/Cash received/]
    K8 --> K9{Cash = 0?}
    K9 -- Yes --> K10[Restore stock] --> M
    K9 -- No --> K11{Cash >= total?}
    K11 -- No --> K8
    K11 -- Yes --> K12[Change, update sales totals] --> M

    R1 --> R2[/Item no. and units/]
    R2 --> R3{Item = 0?}
    R3 -- Yes --> M
    R3 -- No --> R4{Valid and stock <= 999?}
    R4 -- No --> R2
    R4 -- Yes --> R5[Add stock] --> R2
```

### Subroutine flow (number printing)
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
