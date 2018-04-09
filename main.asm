default rel

bits 64

%define SYSCALL_BASE 0x2000000
%define SYSCALL_EXIT SYSCALL_BASE + 1
%define SYSCALL_READ SYSCALL_BASE + 3
%define SYSCALL_WRITE SYSCALL_BASE + 4
%define SYSCALL_CLOSE SYSCALL_BASE + 6
%define SYSCALL_ACCEPT SYSCALL_BASE + 30
%define SYSCALL_SOCKET SYSCALL_BASE + 97
%define SYSCALL_BIND SYSCALL_BASE + 104
%define SYSCALL_SETSOCKOPT SYSCALL_BASE + 105
%define SYSCALL_LISTEN SYSCALL_BASE + 106
%define SYSCALL_POLL SYSCALL_BASE + 230

%define STDOUT 1

%define POLLIN 1

%define AF_INET 2
%define AF_INET6 0x1E
%define SOCK_STREAM 1
%define PROTO_TCP 6

%define SOL_SOCKET 0xFFFF
%define SO_REUSEADDR 0x4

%define BACKLOG 10
%define TIMEOUT_SEC 10

global start
section .text

print_here:
    mov rax, SYSCALL_WRITE
    mov rdi, STDOUT
    lea rsi, [here_str]
    mov rdx, here_str_len
    syscall
    ret

start:
    ; Open the main server socket
    mov rax, SYSCALL_SOCKET
    mov rdi, AF_INET6
    mov rsi, SOCK_STREAM
    mov rdx, PROTO_TCP
    syscall

    ; Verify that we got a file descriptor, not an error
    cmp rax, 0
    jl error

    ; Save off the server socket file descriptor for later use
    mov [sockfd], eax

    ; Set the socket allow address reuse so that the application
    ; can be restarted quickly during testing
    mov rax, SYSCALL_SETSOCKOPT
    mov rdi, [sockfd]
    mov rsi, SOL_SOCKET
    mov rdx, SO_REUSEADDR
    mov r10, yes
    mov r8, 4
    syscall

    ; Verify that the reuse address option properly applied
    cmp rax, 0
    jl error

    ; Bind to 0.0.0.0:8080
    mov rax, SYSCALL_BIND
    mov rdi, [sockfd]
    mov rsi, sock_addr
    mov rdx, sock_addr_len
    syscall

    ; Verify that the bind succeeded
    cmp rax, -1
    je error

    ; Listen on the bound port, accept an incoming unhandled queue of up to BACKLOG connections
    mov rax, SYSCALL_LISTEN
    mov rdi, [sockfd]
    mov rsi, BACKLOG
    syscall

    ; Verify that the listen succeeded
    cmp rax, 0
    jl error

    ; Set the first poll fd to the server socket
    mov [pollfds], edi
    mov word [pollfds + 4], POLLIN
    mov word [pollfds + 6], 0

poll:
    mov rax, SYSCALL_POLL
    lea rdi, [pollfds]
    mov rsi, pollfds_len
    mov rdx, TIMEOUT_SEC * 1000
    syscall

    cmp rax, 0
    jl error
    je poll

    mov r15, 0
.loop:
    lea r14, [pollfds]
    mov ecx, [r14 + r15 * 8] ; ecx = fd
    mov di, [r14 + r15 * 8 + 6] ; di = revents

    and di, POLLIN

    cmp di, 0
    jg poll.run_io

.inc:
    inc r15
    cmp r15, pollfds_len
    je poll
    jmp poll.loop

.run_io:
    cmp r15, 0
    je accept

    mov [connfd], ecx
    jmp echo

accept:
    ; Accept new connection from the server socket
    mov rax, SYSCALL_ACCEPT
    mov rdi, [sockfd]
    mov rsi, in_conn_addr
    mov rdx, in_conn_size
    syscall

    ; Verify that the accept succeeded
    cmp rax, 0
    jl error

    mov r13, r15
    inc r15

    ; Save off the connection socket file descriptor for later use
    mov [r14 + r15 * 8], eax
    mov word [r14 + r15 * 8 + 4], POLLIN
    mov word [r14 + r15 * 8 + 6], 0

    mov r15, r13

    jmp poll.inc

echo:
    xor r13, r13   ; Init Read Finished
    xor rbx, rbx ; Init Write Finished

.read_pre:
    ; If both read and write are 1, there is no data left to echo; Close the socket
    and r13, rbx
    cmp r13, 1
    je close

    mov r13, 1 ; Start as "finished reading"
    mov r12, buf_len ; Reset buffer pull size to max

.read:
    ; Read data from the connection socket
    mov rax, SYSCALL_READ
    mov rdi, [connfd]
    mov rdx, r12
    mov rsi, buf
    syscall

    cmp rax, 0
    je echo.write_pre ; Jump to write, we've read all the bytes we can
    jl error          ; If this value is negative, read is not happy

    ; Shrink the buffer length for the next read so that we don't overrun memory
    sub r12, rax      ; (prev_buffer_size - read_bytes)
    mov r13, 0         ; Mark this as a read loop that did work so we know we have to run read again later
    jmp echo.read

.write_pre:
    mov rbx, 1 ; Start as "finished writing"

    ; Calculate the size that was read and put it in r12
    mov rcx, r12
    mov r12, buf_len
    sub r12, rcx

.write:
    ; Echo data back to the connection socket
    mov rax, SYSCALL_WRITE
    mov rdi, [connfd]
    mov rdx, r12
    mov rsi, buf
    syscall

    cmp rax, 0
    je echo.read_pre ; Jump back to read, we've written all our bytes in the buffer
    jl error         ; If this value is negative, write is not happy

    sub r12, rax     ; (prev_buffer_size - written_bytes)
    mov rbx, 0       ; Mark this as a write loop that did work so we know we may have to run write again later
    jmp echo.write

close:
    ; Close the connection
    mov rax, SYSCALL_CLOSE
    mov rdi, [connfd]
    syscall

    mov dword [r14 + r15 * 8], -1

    ; Handle the next connection
    jmp poll.inc

exit:
    mov rax, SYSCALL_EXIT
    mov rdi, 0
    syscall

error:
    mov rax, SYSCALL_EXIT
    mov rdi, 1
    syscall

section .data
    sock_addr:
        dw 0x1E1C ; IPv6 << 8 | total len (28 bytes)
        dw 0x901F ; Port 8080 - this is big endian
        dq 0x0    ; The remaining bytes are ip address and zero padding
        dq 0x0
        dq 0x0
    sock_addr_len: equ $ - sock_addr ; total len (28 bytes)

    here_str: db "here", 10
    here_str_len: equ $ - here_str

    yes: dd 1
    buf_len: equ 4096

    pollfd_size: equ 8
    pollfds_len: equ 2

    pollfds: times pollfds_len dq -1

section .bss
    sockfd: resd 1 ; Server's main listening socket fd
    connfd: resd 1 ; Transient connection fd

    ; Space for the ip address of the incoming connection
    in_conn_addr: resb sock_addr_len
    in_conn_size: resb 4

    ; Echo buffer
    buf: resb buf_len
