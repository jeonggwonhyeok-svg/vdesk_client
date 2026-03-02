#include <string.h>
#include <poll.h>
#include <unistd.h>

// Stub implementations for fortified functions missing in NDK API 28 stubs
void *__memchr_chk(const void *s, int c, size_t n, size_t buf_size) {
    return memchr(s, c, n);
}

int __poll_chk(struct pollfd *fds, nfds_t nfds, int timeout, size_t fds_size) {
    return poll(fds, nfds, timeout);
}
