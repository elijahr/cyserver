

from libc.stdio cimport fprintf, stderr, perror, sprintf
from libc.stdlib cimport malloc, calloc, realloc, free
from libc.string cimport memcpy
from libc.stdint cimport uint8_t, uint64_t
from posix.fcntl cimport fcntl, F_GETFL, O_NONBLOCK, F_SETFL

from libc cimport errno

from cyserver.csocket cimport *
from cyserver.libev cimport *


cdef buffer_t* buffer_new(size_t max_length) nogil:
    cdef buffer_t *buffer_p
    buffer_p = <buffer_t*>malloc(sizeof(buffer_t))
    buffer_p.bytes = <uint8_t*>calloc(max_length, sizeof(uint8_t))
    buffer_p.length = 0
    buffer_p.max_length = max_length
    return buffer_p


cdef int buffer_resize(buffer_t *buffer_p, size_t new_max_length) nogil:
    cdef uint8_t *new_data = <uint8_t*>realloc(buffer_p.bytes, new_max_length * sizeof(uint8_t))
    if new_data == NULL:
        perror ("buffer_resize() could not resize buffer")
        return -1
    buffer_p.bytes = new_data
    buffer_p.max_length = new_max_length
    return 0


cdef void buffer_destroy(buffer_t *buffer_p) nogil:
    free(buffer_p.bytes)
    free(buffer_p)
    buffer_p = NULL


cdef buffer_t *buffer_clone(buffer_t *buffer_p) nogil:
    cdef buffer_t *cloned
    cloned = buffer_new(buffer_p.max_length)
    cloned.length = buffer_p.length
    memcpy(cloned.bytes, buffer_p.bytes, buffer_p.max_length)
    cdef int offset
    offset = <int>buffer_p.bytes - <int>buffer_p.bytes
    cloned.bytes = cloned.bytes + offset
    return cloned


cdef void buffer_debug(char *prefix, buffer_t *buffer_p) nogil:
    if buffer_p == NULL:
        fprintf(stderr, "%s: <buffer_t(NULL) %p>\n", prefix, &buffer_p)
        return
    fprintf(stderr, "%s: <buffer_t(data=\"%.*s\", length=%u) %p>\n", prefix,
            buffer_p.length, buffer_p.bytes, buffer_p.length, &buffer_p)


cdef char* BYTE_TO_BINARY_PATTERN = "%d%d%d%d%d%d%d%d"


cdef void byte_to_binary(char *binary, char byte) nogil:
     sprintf(binary, BYTE_TO_BINARY_PATTERN,
        (1 if (byte & 0x80) else 0),
        (1 if (byte & 0x40) else 0),
        (1 if (byte & 0x20) else 0),
        (1 if (byte & 0x10) else 0),
        (1 if (byte & 0x08) else 0),
        (1 if (byte & 0x04) else 0),
        (1 if (byte & 0x02) else 0),
        (1 if (byte & 0x01) else 0))


cdef void buffer_debug_binary(char *prefix, buffer_t *buffer_p) nogil:
    if buffer_p == NULL:
        fprintf(stderr, "%s: <buffer_t(NULL) %p>\n", prefix, &buffer_p)
        return

    cdef int binary_size = ((11*sizeof(uint8_t))*buffer_p.length)
    cdef char *binary = <char*>malloc(binary_size)

    cdef int i = 0, j = 0
    while i < buffer_p.length:
        binary[j] = "0"
        binary[j+1] = "b"
        byte_to_binary(binary+j+2, <char>buffer_p.bytes[i])
        binary[j+10] = ","
        j += 11
        i += 1
    fprintf(stderr, "%s: <buffer_t(bytes=[%.*s], bytes=\"%.*s\", length=%u) %p>\n", prefix,
            binary_size-1, binary, buffer_p.length, buffer_p.bytes, buffer_p.length, &buffer_p)

    free(binary)


cdef buffer_t *buffer_b64_encode(buffer_t *input_buffer_p) nogil:
    # TODO - b64 encode without GIL
    cdef buffer_t *output_buffer_p
    cdef char *buffer_string

    buffer_string = <char*>malloc(sizeof(char)*(1+input_buffer_p.length))
    memcpy(buffer_string, input_buffer_p.bytes, input_buffer_p.length)
    buffer_string[-1] = '\0'
    with gil:
        import base64
        output_buffer_string = base64.b64encode(buffer_string)
        output_buffer_p = buffer_new(len(output_buffer_string))
        output_buffer_p.length = len(output_buffer_string)
        memcpy(output_buffer_p.bytes, <char*>output_buffer_string, output_buffer_p.length)
    free(buffer_string)
    return output_buffer_p


### server_t - struct and methods for managing a socket listener
cdef int DEFAULT_SERVER_CONNECTION_BUFFER_SIZE = 4096


cdef server_t *server_new(char *interface, int port, ev_on_ready_accept_callback_t ev_on_ready_accept_callback_p, ev_on_ready_receive_callback_t ev_on_ready_receive_callback_p) nogil:
    cdef server_t *server_p
    server_p = <server_t*>malloc(sizeof(server_t))

    server_p.address_p = <sockaddr_in*>calloc(1, sizeof(sockaddr_in))
    server_p.address_p.sin_family = AF_INET

    inet_pton(AF_INET, interface, <void*>&server_p.address_p.sin_addr)
    server_p.address_p.sin_port = htons(port)

    server_p.max_buffer_length = DEFAULT_SERVER_CONNECTION_BUFFER_SIZE

    cdef int fd = socket(AF_INET, SOCK_STREAM, 0)
    if fd < 0:
        server_destroy(server_p)
        perror("server_new() could not create socket")
        return NULL

    # attach the accept callback to the server's ev loop
    fd_set_non_blocking(fd)
    server_p.ev_on_ready_accept_callback_p = ev_on_ready_accept_callback_p
    server_p.ev_on_ready_receive_callback_p = ev_on_ready_receive_callback_p
    server_p.ev_loop_p = ev_loop_new(0)
    ev_io_init(&server_p.io, <void*>ev_on_ready_accept, fd, EV_READ)

    return server_p


cdef void server_destroy(server_t *server_p) nogil:
    ev_loop_destroy(server_p.ev_loop_p)
    free(server_p.address_p)
    free(server_p)
    server_p = NULL


cdef int server_run(server_t *server_p) nogil:
    cdef int bound, listening

    bound = bind(server_p.io.fd, <sockaddr*>server_p.address_p, sizeof(sockaddr_in))
    if bound < 0:
        perror("server_run() could not bind")
        return bound

    listening = listen(server_p.io.fd, SOMAXCONN)
    if listening < 0:
        perror("server_run() could not listen")
        return listening

    address_debug("Server listening on", server_p.address_p)

    # make ev start listening to the server's fd and run the server's ev loop
    ev_io_start(server_p.ev_loop_p, &server_p.io)
    ev_run(server_p.ev_loop_p, 0)

    return 0


cdef int server_stop(server_t *server_p) nogil:
    cdef int closed
    ev_io_stop(server_p.ev_loop_p, &server_p.io)
    ev_break(server_p.ev_loop_p, EVBREAK_CANCEL)
    closed = close(server_p.io.fd)
    if closed < 0:
        perror("server_stop() could not close")
    return closed


cdef void server_debug(char *prefix, server_t *server_p) nogil:
    fprintf(stderr, "%s: <server_t(io.fd=%u, address_p=%p) %p>\n", prefix, server_p.io.fd, <int>server_p.address_p, <int>server_p)


cdef void address_debug(char *prefix, sockaddr_in *address_p) nogil:
    cdef char *ip = <char*>malloc(sizeof(char)*INET_ADDRSTRLEN)
    inet_ntop(AF_INET, <void*>&address_p.sin_addr, ip, INET_ADDRSTRLEN)
    fprintf(stderr, "%s %s:%u\n", prefix, ip, ntohs(address_p.sin_port))
    free(ip)


cdef int server_accept(server_t *server_p, connection_t *connection_p) nogil:
    cdef int fd
    fd = accept(server_p.io.fd, <sockaddr*>connection_p.client_address_p, &connection_p.client_address_length)
    if fd < 0:
        perror("server_accept() could not accept")
    else:
        address_debug("Connection from", connection_p.client_address_p)

        # make the connection's fd non-blocking and set the receive callback
        fd_set_non_blocking(fd)
        ev_io_init(&connection_p.io, <void*>ev_on_ready_receive, fd, EV_READ)
        ev_io_start(server_p.ev_loop_p, &connection_p.io)
    return fd

    #
    # # notify the thread to self-destruct when work has finished
    # cdef ev_on_ready_accept_callback_arg_t *ev_on_ready_accept_callback_arg_p
    # ev_on_ready_accept_callback_arg_p = ev_on_ready_accept_callback_arg_new(ev_on_ready_accept_callback_p, connection_p)
    # pthread_create(thread_p, NULL, ev_on_ready_accept_callback_wrapper, <void*>ev_on_ready_accept_callback_arg_p)
    # pthread_detach(thread_p[0])


cdef void connection_init(connection_t *connection_p, server_t *server_p) nogil:
    connection_p.frames_out_p = NULL
    connection_p.server_p = server_p
    connection_p.client_address_p = <sockaddr_in*>malloc(sizeof(sockaddr_in))
    connection_p.client_address_length = sizeof(sockaddr_in)


cdef int fd_set_non_blocking(int fd) nogil:
    cdef int flags, ret
    flags = fcntl(fd, F_GETFL)
    if flags == -1:
        perror('fd_set_non_blocking()')
        return flags
    flags |= O_NONBLOCK
    ret = fcntl(fd, F_SETFL, flags)
    if ret == -1:
        perror('fd_set_non_blocking()')
    return ret


cdef int connection_receive(connection_t *connection_p, buffer_t *buffer_p, uint64_t offset, uint64_t bytes_requested) nogil:
    cdef int bytes_received

    if (buffer_p.length + offset + bytes_requested) > buffer_p.max_length:
        errno.errno = errno.EOVERFLOW
        perror("connection_receive() could not receive")
        return -1

    bytes_received = recv(connection_p.io.fd, buffer_p.bytes+offset, bytes_requested, 0)
    if bytes_received < 0:
        perror("connection_receive() could not receive")
        buffer_p.length = 0
    # elif bytes_received == 0:
    #     perror("connection_receive() 0 bytes received, closing connection")
    #     connection_close(connection_p)
    else:
        buffer_p.length = offset+bytes_received

    return bytes_received


cdef int connection_send(connection_t *connection_p, buffer_t *buffer_p) nogil:
    cdef int sent, total_sent = 0
    while total_sent < buffer_p.length:
        sent = send(connection_p.io.fd, &buffer_p.bytes[total_sent], buffer_p.length-total_sent, 0)
        if sent < 0:
            perror("connection_send() failed to send")
            break
        total_sent += sent
    return total_sent


cdef void connection_destroy(connection_t *connection_p) nogil:
    ev_io_stop(connection_p.server_p.ev_loop_p, &connection_p.io)
    free(connection_p.client_address_p)
    free(connection_p)
    connection_p = NULL


cdef int connection_close(connection_t *connection_p) nogil:
    cdef int closed
    closed = close(connection_p.io.fd)
    if closed < 0:
        perror("connection_close() could not close")
    return closed


cdef void connection_enqueue_out_frame(connection_t *connection_p, frame_t *frame_out_p) nogil:
    cdef frame_t *frame_p = connection_p.frames_out_p
    if frame_p == NULL:
        connection_p.frames_out_p = frame_out_p
    else:
        while 1:
            if frame_p.next_frame_p == NULL:
                frame_p.next_frame_p = frame_out_p
                break
            else:
                frame_p = frame_p.next_frame_p


cdef frame_t *connection_dequeue_out_frame(connection_t *connection_p) nogil:
    cdef frame_t *out_frame_p = connection_p.frames_out_p

    if out_frame_p != NULL:
        connection_p.frames_out_p = out_frame_p.next_frame_p
        out_frame_p.next_frame_p = NULL

    return out_frame_p


cdef void connection_push_out_frame(connection_t *connection_p, frame_t *frame_out_p) nogil:
    frame_out_p.next_frame_p = connection_p.frames_out_p
    connection_p.frames_out_p = frame_out_p



cdef void connection_debug(char *prefix, connection_t *connection_p) nogil:
    fprintf(stderr, "%s: <connection_t(frames_out_p=%p, server_p=%p, client_address_p=%p, client_address_length=%u, io.fd=%u) %p>\n",
            prefix, connection_p.frames_out_p, connection_p.server_p, connection_p.client_address_p,
            <int>connection_p.client_address_length, connection_p.io.fd, <int>connection_p)


cdef void ev_on_ready_accept(ev_loop *loop, ev_io *io, int events) nogil:
    cdef server_t *server_p = <server_t*>io #since io is the first element of server_t, we can cast as a sever_t pointer

    # call the callback, passing the server
    if server_p.ev_on_ready_accept_callback_p != NULL:
        server_p.ev_on_ready_accept_callback_p(server_p)



cdef void ev_on_ready_receive(ev_loop *loop, ev_io *io, int events) nogil:
    cdef connection_t *connection_p = <connection_t*>io #since io is the first element of connection_t, we can cast as a connection_t pointer

    # call the callback, passing the connection
    if connection_p.server_p.ev_on_ready_receive_callback_p != NULL:
        connection_p.server_p.ev_on_ready_receive_callback_p(connection_p)

