
cdef extern from "<signal.h>":

    ctypedef void *sigset_t

    struct sigaction_t "sigaction":
        void (*sa_handler)(int)
        sigset_t sa_mask
        int sa_flags

    int SIGINT, SIGTSTP, SIGABRT, SIGALRM, SIGFPE, SIGHUP, SIGILL, SIGPIPE
    int sigaction(int signum, sigaction_t *act, sigaction_t *oldact)
    int sigemptyset(sigset_t *set_)