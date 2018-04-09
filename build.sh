nasm -f macho64 -o main.o main.asm
ld main.o -o tinyecho
rm main.o
