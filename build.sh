nasm -f macho64 -o main.o main.asm
ld -x main.o -o tinyecho
rm main.o
strip tinyecho
