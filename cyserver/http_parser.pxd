from libc.stdint cimport uint32_t, uint64_t


cdef extern from "http-parser/http_parser.h" nogil:

    cdef enum http_parser_type:
        HTTP_REQUEST, HTTP_RESPONSE, HTTP_BOTH


    ctypedef int (*http_data_cb) (http_parser*, const char *at, size_t length)
    ctypedef int (*http_cb) (http_parser*)

    cdef struct http_parser:
        # /** PRIVATE **/
        unsigned int type # = 2         #/* enum http_parser_type */
        unsigned int flags# = 6        #/* F_* values from 'flags' enum semi-public */
        unsigned int state# = 8        #/* enum state from http_parser.c */
        unsigned int header_state# = 8 #/* enum header_state from http_parser.c */
        unsigned int index# = 8        #/* index into current matcher */
        
        uint32_t nread          #/* # bytes read in various scenarios */
        uint64_t content_length #/* # bytes in body (0 if no Content-Length header) */
        
        # /** READ-ONLY **/
        unsigned short http_major
        unsigned short http_minor
        unsigned int status_code# = 16 #/* responses only */
        unsigned int method# = 8       #/* requests only */
        unsigned int http_errno# = 7
        
        # /* 1 = Upgrade header was present and the parser has exited because of that.
        # * 0 = No upgrade header present.
        # * Should be checked when http_parser_execute() returns in addition to
        # * error checking.
        # */
        unsigned int upgrade# = 1
        
        # /** PUBLIC **/
        void *data #/* A pointer to get hook to the "connection" or "socket" object */


    cdef struct http_parser_settings:
        http_cb      on_message_begin
        http_data_cb on_url
        http_data_cb on_status
        http_data_cb on_header_field
        http_data_cb on_header_value
        http_cb      on_headers_complete
        http_data_cb on_body
        http_cb      on_message_complete


    cdef void http_parser_init(http_parser *parser, int type)
    cdef size_t http_parser_execute(http_parser *parser, const http_parser_settings *settings, const char *data,
                                    size_t len_)