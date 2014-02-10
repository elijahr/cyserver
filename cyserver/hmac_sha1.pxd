

cdef extern from "sha.h" nogil:
    
    #define SHA1_BLOCK_LENGTH 64
    #define SHA1_DIGEST_LENGTH 20
    
    ctypedef unsigned int sha1_quadbyte
    ctypedef unsigned char sha1_byte
    
    ctypedef struct SHA_CTX:
        sha1_quadbyte state[5]
        sha1_quadbyte count[2]
        sha1_byte buffer[64] # aka [SHA1_BLOCK_LENGTH]


cdef extern from "hmac_sha1.h" nogil:
    
    #define HMAC_SHA1_DIGEST_LENGTH 20
    #define HMAC_SHA1_BLOCK_LENGTH 64
    
    ctypedef struct HMAC_SHA1_CTX:
        unsigned char ipad[64] # aka [HMAC_SHA1_BLOCK_LENGTH]
        unsigned char opad[64] # aka [HMAC_SHA1_BLOCK_LENGTH]
        SHA_CTX shactx
        unsigned char key[64] # aka [HMAC_SHA1_BLOCK_LENGTH]
        unsigned int keylen
        unsigned int hashkey

    cdef void HMAC_SHA1_Init(HMAC_SHA1_CTX *ctx)
    cdef void HMAC_SHA1_UpdateKey(HMAC_SHA1_CTX *ctx, unsigned char *key, unsigned int keylen)
    cdef void HMAC_SHA1_EndKey(HMAC_SHA1_CTX *ctx)
    cdef void HMAC_SHA1_StartMessage(HMAC_SHA1_CTX *ctx)
    cdef void HMAC_SHA1_UpdateMessage(HMAC_SHA1_CTX *ctx, unsigned char *data, unsigned int datalen)
    cdef void HMAC_SHA1_EndMessage(unsigned char *out, HMAC_SHA1_CTX *ctx)
    cdef void HMAC_SHA1_Done(HMAC_SHA1_CTX *ctx)