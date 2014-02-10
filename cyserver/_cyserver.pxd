
from libc.stdint cimport uint8_t, uint64_t

from cyserver.csocket cimport *
from cyserver.libev cimport *


ctypedef void (*ev_on_ready_accept_callback_t)(server_t*) nogil
ctypedef void (*ev_on_ready_receive_callback_t)(connection_t*) nogil
ctypedef void (*send_callback_t)(connection_t*) nogil



cdef struct server_t:
    ev_io io
    ev_loop *ev_loop_p
    sockaddr_in *address_p
    size_t max_buffer_length
    ev_on_ready_accept_callback_t ev_on_ready_accept_callback_p
    ev_on_ready_receive_callback_t ev_on_ready_receive_callback_p
    send_callback_t send_callback_p


cdef struct buffer_t:
    uint8_t *bytes
    uint64_t length
    uint64_t max_length


cdef struct frame_t:
    frame_t *next_frame_p


cdef struct connection_t:
    ev_io io
    frame_t *frames_out_p
    server_t *server_p
    sockaddr_in *client_address_p
    socklen_t client_address_length


cdef int DEFAULT_SERVER_CONNECTION_BUFFER_SIZE
cdef server_t *server_new(char *interface, int port, ev_on_ready_accept_callback_t ev_on_ready_accept_callback_p,
                          ev_on_ready_receive_callback_t ev_on_ready_receive_callback_p) nogil
cdef void server_destroy(server_t *server) nogil
cdef int fd_set_non_blocking(int fd) nogil
cdef int server_run(server_t *server) nogil
cdef int server_stop(server_t *server) nogil
cdef void server_debug(char *prefix, server_t *server_p) nogil
cdef void address_debug(char *prefix, sockaddr_in *address_p) nogil
cdef int server_accept(server_t *server_p, connection_t *connection_p) nogil
cdef void ev_on_ready_accept(ev_loop *loop, ev_io *io, int events) nogil
cdef void ev_on_ready_receive(ev_loop *loop, ev_io *io, int events) nogil


cdef buffer_t* buffer_new(size_t max_length) nogil
cdef int buffer_resize(buffer_t *buffer_p, size_t new_max_length) nogil
cdef void buffer_destroy(buffer_t *buffer_p) nogil
cdef buffer_t *buffer_clone(buffer_t *buffer_p) nogil
cdef void buffer_debug(char *prefix, buffer_t *buffer_p) nogil
cdef void buffer_debug_binary(char *prefix, buffer_t *buffer_p) nogil
cdef buffer_t *buffer_b64_encode(buffer_t *input_buffer_p) nogil


cdef void connection_init(connection_t *connection_p, server_t *server_p) nogil
cdef int connection_receive(connection_t *connection_p, buffer_t *buffer_p, uint64_t offset,
                            uint64_t bytes_requested) nogil
cdef int connection_send(connection_t *connection_p, buffer_t *buffer_p) nogil
cdef void connection_destroy(connection_t *connection_p) nogil
cdef int connection_close(connection_t *connection_p) nogil
cdef void connection_enqueue_out_frame(connection_t *connection_p, frame_t *frame_out_p) nogil
cdef frame_t *connection_dequeue_out_frame(connection_t *connection_p) nogil
cdef void connection_push_out_frame(connection_t *connection_p, frame_t *frame_out_p) nogil
cdef void connection_debug(char *prefix, connection_t *connection_p) nogil

