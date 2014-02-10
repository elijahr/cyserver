from cyserver._cyserver cimport server_new, server_stop, server_destroy, server_debug
from cyserver.cywebsocket cimport *
from libc.stdio cimport fprintf, stderr
from posix.unistd cimport usleep


cdef class WebSocketServer(object):
    cdef int port
    cdef server_t *server_p

    def __init__(self, *args, **kwargs):
        pass

    def __cinit__(self, int port=9090, *args, **kwargs):
        self.port = port
        with nogil:
            self.server_p = server_new("0.0.0.0", self.port, ws_connection_on_ready_accept, ws_connection_on_ready_receive)

    cpdef run(self):
        cdef int started = -1
        with nogil:
            while started < 0:
                started = server_run(self.server_p)
                server_debug('Started', self.server_p)

    cpdef stop(self):
        with nogil:
            if self.server_p != NULL:
                server_stop(self.server_p)
                server_debug('Stopped', self.server_p)
                server_destroy(self.server_p)

