

from libc.stdio cimport fprintf, stderr, perror, sprintf
from libc.stdlib cimport calloc, malloc, free
from libc.string cimport memcpy, strlen, strncmp
from libc.stdint cimport uint8_t, uint16_t, uint32_t, uint64_t
from libc cimport errno


from cyserver.csocket cimport *
from cyserver._cyserver cimport *
from cyserver.http_parser cimport *
from cyserver.hmac_sha1 cimport *


cdef const unsigned char *WS_MAGIC_GUID = b"258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
cdef const unsigned char *WS_HANDSHAKE_RESPONSE_FORMAT = (
    b"HTTP/1.1 101 Switching Protocols\r\n"
    b"Upgrade: websocket\r\n"
    b"Connection: Upgrade\r\n"
    b"Sec-WebSocket-Accept: %*s\r\n"
    b"\r\n"
)


cdef http_header *http_header_new() nogil:
    cdef http_header *http_header_p = <http_header*>calloc(1, sizeof(http_header))
    return http_header_p


cdef int http_parser_on_header_field(http_parser *parser, const char *at, size_t length) nogil:
    cdef unsigned char *header_field = <unsigned char*>malloc(length)
    cdef ws_connection_t *ws_connection_p = <ws_connection_t*>parser.data
    cdef http_header *http_header_p = http_header_new()
    memcpy(header_field, at, length)
    http_header_p.field = header_field
    http_header_p.field_length = length
    http_header_p.next = ws_connection_p.headers_list_p
    ws_connection_p.headers_list_p = http_header_p


cdef int http_parser_on_header_value(http_parser *parser, const char *at, size_t length) nogil:
    cdef unsigned char *header_field = <unsigned char*>malloc(length)
    cdef ws_connection_t *ws_connection_p = <ws_connection_t*>parser.data
    cdef http_header *http_header_p = ws_connection_p.headers_list_p
    memcpy(header_field, at, length)
    http_header_p.value = header_field
    http_header_p.value_length = length


cdef http_parser *http_parser_new() nogil:
    # since we cannot define default values for a struct in Cython, we mirror what http_parser.h defines
    cdef http_parser *http_parser_p = <http_parser*>calloc(1, sizeof(http_parser))
    http_parser_p.type = 2
    http_parser_p.flags = 6
    http_parser_p.state = 8
    http_parser_p.header_state = 8
    http_parser_p.index = 8
    http_parser_p.status_code = 16
    http_parser_p.method = 8
    http_parser_p.http_errno = 7
    http_parser_p.upgrade = 1
    return http_parser_p


cdef int ws_connection_handshake(ws_connection_t *ws_connection_p) nogil:
    cdef int length = 80*1024
    cdef buffer_t *response_buffer_p = buffer_new(length)
    cdef http_parser_settings *http_parser_settings_p = <http_parser_settings*>calloc(1, sizeof(http_parser_settings))
    cdef http_parser *http_parser_p = http_parser_new()

    http_parser_p.data = <void*>ws_connection_p
    http_parser_init(http_parser_p, HTTP_REQUEST)
    http_parser_settings_p.on_header_field = http_parser_on_header_field
    http_parser_settings_p.on_header_value = http_parser_on_header_value

    cdef int bytes_received = connection_receive(&ws_connection_p.connection, response_buffer_p, 0, response_buffer_p.max_length)

    if 0 > bytes_received:
        fprintf(stderr, "no bytes received, yowza!\n")
        buffer_destroy(response_buffer_p)
        free(http_parser_settings_p)
        free(http_parser_p)
        return bytes_received

    # terminate the buffer string
    response_buffer_p.bytes[response_buffer_p.length] = "\0"
    response_buffer_p.length += 1

    cdef size_t n_parsed = http_parser_execute(http_parser_p, http_parser_settings_p, <const char*>response_buffer_p.bytes,
                                               response_buffer_p.length)
    if http_parser_p.upgrade == 0:
        free(response_buffer_p)
        free(http_parser_settings_p)
        free(http_parser_p)
        return -1

    free(http_parser_settings_p)
    free(http_parser_p)

    cdef char *key
    cdef char *response_key

    cdef http_header *http_header_p
    cdef char *sec_websocket_key_field = b'Sec-WebSocket-Key'
    cdef int compared
    http_header_p = ws_connection_p.headers_list_p
    while 1:
        # if case-insensitive match of header field
        compared = strncmp(<const char*>http_header_p.field, sec_websocket_key_field, 18)
        if 0 == compared or 32 == compared:
            break
        if http_header_p.next == NULL:
            fprintf(stderr, "ws_connection_handshake() could not find Sec-WebSocket-Key header")
            return -1
        http_header_p = http_header_p.next

    cdef HMAC_SHA1_CTX ctx
    HMAC_SHA1_Init(&ctx)
    HMAC_SHA1_UpdateKey(&ctx, http_header_p.value, http_header_p.value_length)
    HMAC_SHA1_UpdateKey(&ctx, WS_MAGIC_GUID, 36)
    HMAC_SHA1_EndKey(&ctx)

    cdef buffer_t *encode_buffer_p, *key_buffer_p
    encode_buffer_p = buffer_new(20)
    HMAC_SHA1_StartMessage(&ctx)
    HMAC_SHA1_EndMessage(encode_buffer_p.bytes, &ctx)
    encode_buffer_p.length = 20
    key_buffer_p = buffer_b64_encode(encode_buffer_p)

    # re-use the buffer to assemble the handshake response and sent it
    response_buffer_p.length = sprintf(<char*>response_buffer_p.bytes, <const char*>WS_HANDSHAKE_RESPONSE_FORMAT, key_buffer_p.length, key_buffer_p.bytes)

    buffer_debug_binary("about to send", response_buffer_p)

    buffer_destroy(encode_buffer_p)
    buffer_destroy(key_buffer_p)

    cdef int sent = 0

    while sent == 0:
        sent = connection_send(<connection_t*>ws_connection_p, response_buffer_p)

    buffer_destroy(response_buffer_p)

    if sent < 0:
        perror('ws_connection_handshake() could not send')

    return sent


cdef int ws_frame_send(ws_connection_t *ws_connection_p, ws_frame_t *ws_frame_p) nogil:
    cdef buffer_t *buffer_p = buffer_new(ws_frame_p.payload.length+14)

    # assert values
    if ws_frame_p.fin > 0x1:
        return -1
        # raise ValueError('FIN bit parameter must be 0 or 1')

    if ws_frame_p.rsv1 > 0x1:
        return -1
        # raise ValueError('RSV1 bit parameter must be 0 or 1')

    if ws_frame_p.rsv2 > 0x1:
        return -1
        # raise ValueError('RSV2 bit parameter must be 0 or 1')

    if ws_frame_p.rsv3 > 0x1:
        return -1
        # raise ValueError('RSV3 bit parameter must be 0 or 1')

    if ws_frame_p.opcode > 0x7F:
        return -1
        # raise ValueError('Opcode must be less than 127')

    if 0x3 <= ws_frame_p.opcode <= 0x7 or 0xB <= ws_frame_p.opcode:
        return -1
        # raise ValueError('Opcode cannot be a reserved opcode')

    cdef uint8_t first_byte
    first_byte = (ws_frame_p.fin << 7)
    first_byte |= (ws_frame_p.rsv1 << 6)
    first_byte |= (ws_frame_p.rsv2 << 5)
    first_byte |= (ws_frame_p.rsv3 << 4)
    first_byte |= ws_frame_p.opcode

    buffer_p.bytes[0] = first_byte
    buffer_p.length = 1

    if ws_frame_p.masked > 0x1:
        return -1
        #raise ValueError('MASK bit parameter must be 0 or 1')

    cdef uint64_t length = ws_frame_p.payload.length
    cdef uint16_t length_16_big_endian
    cdef uint64_t length_64_big_endian

    cdef uint64_t MAX_UINT_64_VALUE = 0x8000000000000000

    if length < 126:
        # length is an 8 bit uint
        buffer_p.bytes[1] = (ws_frame_p.masked | length)
        buffer_p.length = 2

    elif length < 0x10000:
        # length is 16 bit uint
        buffer_p.bytes[1] = <uint8_t>(ws_frame_p.masked | 126)

        length_16_big_endian = htons(length)
        memcpy(&buffer_p.bytes[2], &length_16_big_endian, 2)

        buffer_p.length = 4
    elif length < MAX_UINT_64_VALUE:
        # length is a 64 bit uint
        buffer_p.bytes[1] = <uint8_t>(ws_frame_p.masked | 127)

        length_64_big_endian = htobe64(length)
        memcpy(&buffer_p.bytes[2], &length_64_big_endian, 8)

        buffer_p.length = 10
    else:
        return -1
        # raise FrameTooLargeException()

    if ws_frame_p.masked == 1:
        if ws_frame_p.mask == NULL:
            # frame should be masked but mask is invalid
            fprintf(stderr, 'Mask invalid\n')
            return -1

        memcpy(&buffer_p.bytes[buffer_p.length], ws_frame_p.mask, 4)
        buffer_p.length += 4

    # should be the case since we malloc'ed the buffer above with some padding, but just to be sure...
    if ws_frame_p.payload.length > (buffer_p.max_length - buffer_p.length):
        # not enough room in buffer for payload!
        fprintf(stderr, 'not enough room for payload\n')
        return -1

    # copy the data from the frame into the buffer
    cdef uint64_t i = 0
    if ws_frame_p.masked:
        while i < ws_frame_p.payload.length:
            ws_frame_p.payload.bytes[i+buffer_p.length] ^= ws_frame_p.mask[i%4]
            i += 1
    else:
        memcpy(&buffer_p.bytes[buffer_p.length], ws_frame_p.payload.bytes, ws_frame_p.payload.length)

    buffer_p.length += ws_frame_p.payload.length

    # send the buffer
    cdef int bytes_sent = connection_send(&ws_connection_p.connection, buffer_p)

    buffer_destroy(buffer_p)

    return bytes_sent


cdef uint64_t MAX_UINT64_T = 0x7FFFFFFFFFFFFFFF+1


cdef ws_frame_t *ws_frame_new() nogil:
    cdef ws_frame_t *ws_frame_p = <ws_frame_t*>calloc(1, sizeof(ws_frame_t))
    ws_frame_p._frame.next_frame_p = NULL
    ws_frame_p.fin = 1
    ws_frame_p.rsv1 = 0
    ws_frame_p.rsv2 = 0
    ws_frame_p.rsv3 = 0
    ws_frame_p.opcode = 0
    ws_frame_p.masked = 0
    ws_frame_p.payload = NULL
    ws_frame_p.mask = NULL
    return ws_frame_p


cdef ws_frame_t *ws_frame_receive(ws_connection_t *ws_connection_p) nogil:
    # somewhat based on https://github.com/Lawouach/WebSocket-for-Python/blob/master/ws4py/framing.py

    cdef ws_frame_t *ws_frame_p = ws_frame_new()
    cdef buffer_t *buffer_p = buffer_new(14)
    cdef char first_byte, second_byte
    cdef uint64_t payload_length, buffer_bytes_offset

    while buffer_p.length == 0:
        if 0 > connection_receive(&ws_connection_p.connection, buffer_p, 0, 1):
            perror('ws_frame_receive() couldn\'t get first byte')
            ws_frame_destroy(ws_frame_p)
            return NULL

    buffer_bytes_offset = 1

    first_byte =        buffer_p.bytes[0]
    ws_frame_p.fin =    (first_byte >> 7) & 1
    ws_frame_p.rsv1 =   (first_byte >> 6) & 1
    ws_frame_p.rsv2 =   (first_byte >> 5) & 1
    ws_frame_p.rsv3 =   (first_byte >> 4) & 1
    ws_frame_p.opcode = (first_byte & 0xf)

    # frame-rsv1 = %x0 ; 1 bit, MUST be 0 unless negotiated otherwise
    # frame-rsv2 = %x0 ; 1 bit, MUST be 0 unless negotiated otherwise
    # frame-rsv3 = %x0 ; 1 bit, MUST be 0 unless negotiated otherwise
    if 0 < ws_frame_p.rsv1 <= ws_frame_p.rsv2 <= ws_frame_p.rsv3:
        # TODO do something to set errno?
        perror('ws_frame_receive() invalid rsv1, rsv2, or rsv3')
        ws_frame_destroy(ws_frame_p)
        return NULL

    # control frames between 3 and 7 as well as above 0xA are currently reserved
    if 2 < ws_frame_p.opcode < 8 or ws_frame_p.opcode > 0xA:
        # TODO do something to set errno?
        perror('ws_frame_receive() invalid opcode')
        ws_frame_destroy(ws_frame_p)
        return NULL

    # control frames cannot be fragmented
    if ws_frame_p.opcode > 0x7 and ws_frame_p.fin == 0:
        # TODO do something to set errno?
        perror('ws_frame_receive() fragmented control frame')
        ws_frame_destroy(ws_frame_p)
        return NULL

    # get next byte to get the payload length
    while buffer_p.length < 2:
        if 0 > connection_receive(&ws_connection_p.connection, buffer_p, buffer_p.length, 1):
            # TODO do something to set errno?
            perror('ws_frame_receive() couldn\'t receive second byte')
            ws_frame_destroy(ws_frame_p)
            return NULL

    second_byte =       buffer_p.bytes[1]
    ws_frame_p.masked = (second_byte >> 7) & 1
    payload_length =    (second_byte & 0x7f)
    buffer_bytes_offset = 2

    # if payload_length is extended by 8 additional bytes
    if payload_length == 127:
        # get next 8 bytes to get the extended payload length
        while buffer_p.length < 10:
            if 0 > connection_receive(&ws_connection_p.connection, buffer_p, buffer_p.length, 8-(buffer_p.length-buffer_bytes_offset)):
                perror('ws_frame_receive() couldn\'t receive next 8 bytes')
                ws_frame_destroy(ws_frame_p)
                return NULL

        # convert the size from network byte order to host byte order
        payload_length = ntohl((<uint64_t*>buffer_p.bytes)[0])

        with gil:
            if payload_length > MAX_UINT64_T:
                # TODO do something to set errno?
                perror('ws_frame_receive() payload length too large')
                ws_frame_destroy(ws_frame_p)
                return NULL

        buffer_bytes_offset = 10

    # if payload_length is extended by 2 additional bytes
    elif payload_length == 126:

        # get next 2 bytes to get the extended payload length
        while buffer_p.length < 4:
            if 0 > connection_receive(&ws_connection_p.connection, buffer_p, buffer_p.length, 2-(buffer_p.length-buffer_bytes_offset)):
                perror('ws_frame_receive() couldn\'t get next 2 bytes')
                ws_frame_destroy(ws_frame_p)
                return NULL

        payload_length = ntohs((<uint16_t*>buffer_p.bytes)[0])

        buffer_bytes_offset = 4

    if ws_frame_p.masked == 1:
        # the mask is the next 4 bytes
        while buffer_p.length < buffer_bytes_offset+4:
            if 0 > connection_receive(&ws_connection_p.connection, buffer_p, buffer_p.length, 4-(buffer_p.length-buffer_bytes_offset)):
                perror('ws_frame_receive() couldn\'t get mask bytes')
                ws_frame_destroy(ws_frame_p)
                return NULL

        ws_frame_p.mask = <char*>malloc(sizeof(uint8_t)*4)
        memcpy(ws_frame_p.mask, buffer_p.bytes+buffer_bytes_offset, 4)

    # we're done with the frame headers buffer, now lets receive the payload data
    buffer_destroy(buffer_p)
    ws_frame_p.payload = buffer_new(payload_length)

    while ws_frame_p.payload.length < payload_length:
        if 0 > connection_receive(&ws_connection_p.connection, ws_frame_p.payload, ws_frame_p.payload.length, payload_length-ws_frame_p.payload.length):
            perror('ws_frame_receive() couldn\'t receive payload')
            ws_frame_destroy(ws_frame_p)
            return NULL

    cdef uint64_t i = 0
    if ws_frame_p.masked:
        while i < payload_length:
            ws_frame_p.payload.bytes[i] ^= ws_frame_p.mask[i%4]
            i += 1

    return ws_frame_p


cdef void ws_frame_destroy(ws_frame_t* ws_frame_p) nogil:
    if ws_frame_p.payload != NULL:
        buffer_destroy(ws_frame_p.payload)
    if ws_frame_p.mask != NULL:
        free(ws_frame_p.mask)
    free(ws_frame_p)
    ws_frame_p = NULL


cdef void ws_frame_debug(char *prefix, ws_frame_t* ws_frame_p) nogil:
    if ws_frame_p == NULL:
        fprintf(stderr, "%s: ws_frame_t(NULL)\n", prefix)
        return
    fprintf(stderr, "%s: <ws_frame_t(fin=%u, rsv1=%u, rsv2=%u, rsv3=%u, opcode=%u, masked=%u, mask=[%u,%u,%u,%u], payload=%p) %p\n",
            prefix, ws_frame_p.fin, ws_frame_p.rsv1, ws_frame_p.rsv2, ws_frame_p.rsv3,
            ws_frame_p.opcode, ws_frame_p.masked,
            ws_frame_p.mask[0] if ws_frame_p.mask != NULL else 0,
            ws_frame_p.mask[1] if ws_frame_p.mask != NULL else 0,
            ws_frame_p.mask[2] if ws_frame_p.mask != NULL else 0,
            ws_frame_p.mask[3] if ws_frame_p.mask != NULL else 0,
            &ws_frame_p.payload, &ws_frame_p)


cdef void ws_connection_on_ready_accept(server_t *server_p) nogil:
    cdef ws_connection_t *ws_connection_p = <ws_connection_t*>calloc(1, sizeof(ws_connection_t))
    connection_init(&ws_connection_p.connection, server_p)
    ws_connection_p.ready_state = CONNECTING
    server_accept(server_p, &ws_connection_p.connection)


cdef void ws_connection_on_ready_receive(connection_t *connection_p) nogil:
    cdef int received, sent
    cdef ws_frame_t *ws_frame_p
    cdef ws_connection_t *ws_connection_p = <ws_connection_t*>connection_p

    if ws_connection_p.ready_state == CONNECTING:
        if 0 > ws_connection_handshake(ws_connection_p):
            perror("ws_connection_on_ready_receive: couldn't perform handshake")
            connection_close(connection_p)
            connection_destroy(connection_p)
        else:
            ws_connection_p.ready_state = OPEN

    elif ws_connection_p.ready_state == OPEN:
        ws_frame_p = ws_frame_receive(ws_connection_p)

        if ws_frame_p == NULL:
            address_debug("Lost connection from", connection_p.client_address_p)
            connection_close(connection_p) # ?
            connection_destroy(connection_p) # ?
            return

        if ws_frame_p.opcode == WS_OPCODE_CONNECTION_CLOSE:
            address_debug("Disconnect from", connection_p.client_address_p)
            ws_connection_p.ready_state = CLOSING
            ws_connection_send_closing_frame(ws_connection_p)
            connection_close(connection_p)
            ws_connection_p.ready_state = CLOSED
            connection_destroy(connection_p)
            ws_frame_destroy(ws_frame_p)
            return

        ws_frame_p.masked = 0
        connection_enqueue_out_frame(connection_p, <frame_t*>ws_frame_p)

        # echo the frame back to the client
        while 1:
            ws_frame_p = <ws_frame_t*>connection_dequeue_out_frame(connection_p)
            if ws_frame_p != NULL:
                ws_frame_debug("sending frame", ws_frame_p)
                sent = ws_frame_send(ws_connection_p, ws_frame_p)
                if sent < 0:
                    # place it back at the front of the queue

                    connection_debug("sending frame failed, will retry", connection_p)
                    connection_push_out_frame(connection_p, <frame_t*>ws_frame_p)
                else:
                    ws_frame_destroy(ws_frame_p)
            else:
                break


cdef int ws_connection_send_closing_frame(ws_connection_t *ws_connection_p) nogil:
    cdef ws_frame_t *ws_frame_p = ws_frame_new()
    ws_frame_p.fin = 1
    ws_frame_p.opcode = WS_OPCODE_CONNECTION_CLOSE
    ws_frame_p.payload = buffer_new(0)
    ws_frame_send(ws_connection_p, ws_frame_p)
    ws_frame_destroy(ws_frame_p)