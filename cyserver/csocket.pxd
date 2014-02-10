from libc.stdint cimport uint8_t, uint16_t, uint32_t, uint64_t


cdef extern from "netinet/in.h" nogil:
    uint16_t htons(uint16_t hostshort)
    uint16_t htonl(uint32_t hostlong)
    uint16_t ntohs(uint16_t netshort)
    uint16_t ntohl(uint32_t netlong)


cdef extern from "portable_endian.h" nogil:

    uint16_t htobe16(uint16_t host_16bits)
    uint16_t htole16(uint16_t host_16bits)
    uint16_t be16toh(uint16_t big_endian_16bits)
    uint16_t le16toh(uint16_t little_endian_16bits)

    uint32_t htobe32(uint32_t host_32bits)
    uint32_t htole32(uint32_t host_32bits)
    uint32_t be32toh(uint32_t big_endian_32bits)
    uint32_t le32toh(uint32_t little_endian_32bits)

    uint64_t htobe64(uint64_t host_64bits)
    uint64_t htole64(uint64_t host_64bits)
    uint64_t be64toh(uint64_t big_endian_64bits)
    uint64_t le64toh(uint64_t little_endian_64bits)


cdef extern from "sys/socket.h" nogil:
    int AF_UNSPEC, AF_INET, AF_INET6, AF_UNIX, SOCK_STREAM, SOCK_DGRAM, SOL_SOCKET, INADDR_ANY, SHUT_RD, SHUT_WR, \
        SHUT_RDWR, SO_DEBUG, SO_REUSEADDR, SO_KEEPALIVE, SO_DONTROUTE, SO_LINGER, SO_BROADCAST, SO_OOBINLINE, \
        SO_SNDBUF, SO_RCVBUF, SO_SNDLOWAT, SO_RCVLOWAT, SO_SNDTIMEO, SO_RCVTIMEO, SO_TYPE, SO_ERROR, SO_DONTROUTE, \
        SO_LINGER, SO_BROADCAST, SO_OOBINLINE, SO_SNDBUF, SO_REUSEADDR, SO_DEBUG, SO_RCVBUF, SO_SNDLOWAT, SO_RCVLOWAT, \
        SO_SNDTIMEO, SO_RCVTIMEO, SO_KEEPALIVE, SO_TYPE, SO_ERROR, SOMAXCONN, MSG_WAITALL

    ctypedef unsigned int sa_family_t
    ctypedef unsigned int in_port_t
    ctypedef unsigned int in_addr_t
    ctypedef unsigned int socklen_t

    cdef struct in_addr:
        in_addr_t s_addr

    union ip__u6_addr:
        uint8_t  __u6_addr8[16]
        uint16_t __u6_addr16[8]
        uint32_t __u6_addr32[4]

    cdef struct sockaddr:
        pass

    cdef struct sockaddr_in:
        unsigned char sin_len
        sa_family_t sin_family
        in_port_t sin_port
        in_addr sin_addr

    int socket      (int domain, int type, int protocol)
    int connect     (int fd, sockaddr * addr, socklen_t addr_len)
    int accept      (int fd, sockaddr * addr, socklen_t * addr_len)
    int bind        (int fd, sockaddr * addr, socklen_t addr_len)
    int listen      (int fd, int backlog)
    int shutdown    (int fd, int how)
    int close       (int fd)
    int getsockopt  (int fd, int level, int optname, void * optval, socklen_t * optlen)
    int setsockopt  (int fd, int level, int optname, void * optval, socklen_t optlen)
    int getpeername (int fd, sockaddr * name, socklen_t * namelen)
    int getsockname (int fd, sockaddr * name, socklen_t * namelen)
    int sendto      (int fd, void * buf, size_t len, int flags, sockaddr * addr, socklen_t addr_len)
    int send        (int fd, void * buf, size_t len, int flags)
    int recv        (int fd, void * buf, size_t len, int flags)
    int recvfrom    (int fd, void * buf, size_t len, int flags, sockaddr * addr, socklen_t * addr_len)
    int _c_socketpair "socketpair"  (int d, int type, int protocol, int *sv)


cdef extern from "arpa/inet.h" nogil:
    int INET_ADDRSTRLEN

    int inet_pton   (int af, char *src, void *dst)
    char *inet_ntop (int af, void *src, char *dst, socklen_t size)
    char * inet_ntoa (in_addr pin)
    int inet_aton   (char * cp, in_addr * pin)
