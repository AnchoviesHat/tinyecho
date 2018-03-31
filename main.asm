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

%define STDOUT 1

%define AF_INET 2
%define AF_INET6 0x1E
%define SOCK_STREAM 1
%define PROTO_TCP 6

%define SOL_SOCKET 0xFFFF
%define SO_REUSEADDR 0x4

%define BACKLOG 10

section .text

global start
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
    mov [rel sockfd], rax

    ; Set the socket allow address reuse so that the application
    ; can be restarted quickly during testing
    mov rax, SYSCALL_SETSOCKOPT
    mov rdi, [rel sockfd]
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
    mov rdi, [rel sockfd]
    mov rsi, sock_addr
    mov rdx, sock_addr_len
    syscall

    ; Verify that the bind succeeded
    cmp rax, -1
    je error

    ; Listen on the bound port, accept an incoming unhandled queue of up to BACKLOG connections
    mov rax, SYSCALL_LISTEN
    mov rdi, [rel sockfd]
    mov rsi, BACKLOG
    syscall

    ; Verify that the listen succeeded
    cmp rax, 0
    jl error

get_conn:

    ; Accept new connection from the server socket
    mov rax, SYSCALL_ACCEPT
    mov rdi, [rel sockfd]
    mov rsi, in_conn_addr
    mov rdx, in_conn_size
    syscall

    ; Verify that the accept succeeded
    cmp rax, 0
    jl error

    ; Save off the connection socket file descriptor for later use
    mov [rel connfd], rax

    ; Read data from the connection socket
    mov rax, SYSCALL_READ
    mov rdi, [rel connfd]
    mov rsi, buf
    mov rdx, buf_len
    syscall

    ; Echo data back to the connection socket
    mov rax, SYSCALL_WRITE
    mov rdi, [rel connfd]
    mov rsi, buf
    mov rdx, buf_len
    syscall

    ; Close the connection
    mov rax, SYSCALL_CLOSE
    mov rdi, [rel connfd]
    syscall

    ; Handle the next connection
    jmp get_conn

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

    yes: dd 1
    buf_len: equ 255

section .bss
    sockfd: resd 1 ; Server's main listening socket fd
    connfd: resd 1 ; Transient connection fd

    ; Space for the ip address of the incoming connection
    in_conn_addr: resb sock_addr_len
    in_conn_size: resb 4

    ; Echo buffer
    buf: resb buf_len
