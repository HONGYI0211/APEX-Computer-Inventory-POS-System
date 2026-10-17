all:
	nasm -f elf32 apex_pos.asm -o apex_pos.o
	ld -m elf_i386 apex_pos.o -o apex_pos
run: all
	./apex_pos
clean:
	rm -f apex_pos apex_pos.o
