
from cyserver._cyserver cimport *


cdef enum ws_connection_ready_states:
    CONNECTING # The connection is not yet open.
    OPEN       # The connection is open and ready to communicate.
    CLOSING    # The connection is in the process of closing.
    CLOSED     # The connection is closed or couldn't be opened.


cdef struct http_header:
    unsigned char *field
    unsigned int field_length
    unsigned char *value
    unsigned int value_length
    http_header *next # used for linked list


cdef struct ws_connection_t:
    connection_t connection
    unsigned short ready_state
    http_header *headers_list_p


cdef enum WS_FRAME_OPCODES:
    #  |Opcode  | Meaning                             | Reference |
    # -+--------+-------------------------------------+-----------|
    #  | 0      | Continuation Frame                  | RFC 6455  |
    # -+--------+-------------------------------------+-----------|
    #  | 1      | Text Frame                          | RFC 6455  |
    # -+--------+-------------------------------------+-----------|
    #  | 2      | Binary Frame                        | RFC 6455  |
    # -+--------+-------------------------------------+-----------|
    #  | 8      | Connection Close Frame              | RFC 6455  |
    # -+--------+-------------------------------------+-----------|
    #  | 9      | Ping Frame                          | RFC 6455  |
    # -+--------+-------------------------------------+-----------|
    #  | 10     | Pong Frame                          | RFC 6455  |
    # -+--------+-------------------------------------+-----------|
    WS_OPCODE_CONTINUATION = 0
    WS_OPCODE_TEXT = 1
    WS_OPCODE_BINARY = 2
    WS_OPCODE_CONNECTION_CLOSE = 8
    WS_OPCODE_PING = 9
    WS_OPCODE_PONG = 10


cdef struct ws_frame_t:
    # a struct for unpacking / packing the WebSocket frame format as defined in http://tools.ietf.org/html/rfc6455#section-5.2

    #  0                   1                   2                   3
    #  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
    # +-+-+-+-+-------+-+-------------+-------------------------------+
    # |F|R|R|R| opcode|M| Payload len |    Extended payload length    |
    # |I|S|S|S|  (4)  |A|     (7)     |             (16/64)           |
    # |N|V|V|V|       |S|             |   (if payload len==126/127)   |
    # | |1|2|3|       |K|             |                               |
    # +-+-+-+-+-------+-+-------------+ - - - - - - - - - - - - - - - +
    # |     Extended payload length continued, if payload len == 127  |
    # + - - - - - - - - - - - - - - - +-------------------------------+
    # |                               |Masking-key, if MASK set to 1  |
    # +-------------------------------+-------------------------------+
    # | Masking-key (continued)       |          Payload Data         |
    # +-------------------------------- - - - - - - - - - - - - - - - +
    # :                     Payload Data continued ...                :
    # + - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - +
    # |                     Payload Data continued ...                |
    # +---------------------------------------------------------------+
    frame_t _frame # subclass frame_t
    char fin
    char rsv1
    char rsv2
    char rsv3
    char opcode
    int masked
    char *mask

    buffer_t *payload

cdef unsigned char *WS_MAGIC_GUID
cdef unsigned char *WS_HANDSHAKE_RESPONSE_FORMAT


cdef int ws_connection_handshake(ws_connection_t *ws_connection_p) nogil

# callbacks for _cyserver
cdef void ws_connection_on_ready_accept(server_t *server_p) nogil
cdef void ws_connection_on_ready_receive(connection_t *connection_p) nogil

cdef ws_frame_t *ws_frame_new() nogil
cdef void ws_frame_destroy(ws_frame_t* ws_frame_p) nogil
cdef int ws_frame_send(ws_connection_t *ws_connection_p, ws_frame_t *ws_frame_p) nogil
cdef ws_frame_t *ws_frame_receive(ws_connection_t *ws_connection_p) nogil
