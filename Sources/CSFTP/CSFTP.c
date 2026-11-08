#include "CSFTP.h"
#include <libssh2.h>
#include <libssh2_sftp.h>
#include <sys/socket.h>
#include <netdb.h>
#include <unistd.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <stdio.h>
#include <fcntl.h>
#include <poll.h>

struct wb_sftp { pthread_mutex_t lock; int socket; atomic_int cancelled; LIBSSH2_SESSION *session; LIBSSH2_SFTP *sftp; };
static pthread_once_t once = PTHREAD_ONCE_INIT;
static void initialize(void) { libssh2_init(0); }
wb_sftp *wb_sftp_create(void) {
    pthread_once(&once, initialize);
    wb_sftp *c = calloc(1, sizeof(*c));
    if (c) { pthread_mutex_init(&c->lock, NULL); c->socket = -1; }
    return c;
}
void wb_sftp_cancel(wb_sftp *c) {
    if (!c) return;
    atomic_store(&c->cancelled, 1);
    pthread_mutex_lock(&c->lock);
    if (c->socket >= 0) shutdown(c->socket, SHUT_RDWR);
    pthread_mutex_unlock(&c->lock);
}
void wb_sftp_destroy(wb_sftp *c) {
    if (!c) return;
    wb_sftp_cancel(c);
    if (c->sftp) libssh2_sftp_shutdown(c->sftp);
    if (c->session) libssh2_session_free(c->session);
    if (c->socket >= 0) close(c->socket);
    pthread_mutex_destroy(&c->lock); free(c);
}
int wb_sftp_version(void) { return LIBSSH2_VERSION_NUM; }
static int valid_path(const char *path) { return path && *path && strlen(path) <= 4096; }
int wb_sftp_connect(wb_sftp *c, const char *host, int port, const char *user, const char *password, const char *known_hosts) {
    if (!c || atomic_load(&c->cancelled)) return -2;
    if (!host || !*host || !user || !*user || port < 1 || port > 65535 || c->session) return -1;
    struct addrinfo hints = {0}, *addresses = NULL;
    hints.ai_socktype = SOCK_STREAM; hints.ai_family = AF_UNSPEC;
    char service[6]; snprintf(service, sizeof(service), "%d", port);
    if (getaddrinfo(host, service, &hints, &addresses)) return -1;
    int connected = 0;
    for (struct addrinfo *a = addresses; a && !atomic_load(&c->cancelled); a = a->ai_next) {
        int fd = socket(a->ai_family, a->ai_socktype, a->ai_protocol);
        if (fd < 0) continue;
        fcntl(fd, F_SETFL, O_NONBLOCK);
        pthread_mutex_lock(&c->lock);
        if (atomic_load(&c->cancelled)) { close(fd); pthread_mutex_unlock(&c->lock); break; }
        c->socket = fd; pthread_mutex_unlock(&c->lock);
        int result = connect(fd, a->ai_addr, a->ai_addrlen);
        if (result == 0 || errno == EINPROGRESS) {
            struct pollfd p = {fd, POLLOUT, 0};
            int error = 0; socklen_t length = sizeof(error);
            if ((result == 0 || poll(&p, 1, 10000) > 0) && getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &length) == 0 && error == 0) connected = 1;
        }
        if (connected) { fcntl(fd, F_SETFL, 0); break; }
        pthread_mutex_lock(&c->lock); c->socket = -1; close(fd); pthread_mutex_unlock(&c->lock);
    }
    freeaddrinfo(addresses);
    if (atomic_load(&c->cancelled)) return -2;
    if (!connected) return -1;
    int no_sigpipe = 1; setsockopt(c->socket, SOL_SOCKET, SO_NOSIGPIPE, &no_sigpipe, sizeof(no_sigpipe));
    struct timeval timeout = {15, 0};
    setsockopt(c->socket, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    setsockopt(c->socket, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
    c->session = libssh2_session_init();
    if (!c->session) return -1;
    libssh2_session_set_timeout(c->session, 15000);
    if (libssh2_session_handshake(c->session, c->socket)) return -1;
    size_t key_length = 0; int type = 0;
    const char *key = libssh2_session_hostkey(c->session, &key_length, &type);
    int mask = LIBSSH2_KNOWNHOST_TYPE_PLAIN | LIBSSH2_KNOWNHOST_KEYENC_RAW;
    switch (type) {
        case LIBSSH2_HOSTKEY_TYPE_RSA: mask |= LIBSSH2_KNOWNHOST_KEY_SSHRSA; break;
        case LIBSSH2_HOSTKEY_TYPE_ECDSA_256: mask |= LIBSSH2_KNOWNHOST_KEY_ECDSA_256; break;
        case LIBSSH2_HOSTKEY_TYPE_ECDSA_384: mask |= LIBSSH2_KNOWNHOST_KEY_ECDSA_384; break;
        case LIBSSH2_HOSTKEY_TYPE_ECDSA_521: mask |= LIBSSH2_KNOWNHOST_KEY_ECDSA_521; break;
        case LIBSSH2_HOSTKEY_TYPE_ED25519: mask |= LIBSSH2_KNOWNHOST_KEY_ED25519; break;
        default: return -3;
    }
    LIBSSH2_KNOWNHOSTS *hosts = libssh2_knownhost_init(c->session);
    if (!hosts) return -3;
    int trusted = key && known_hosts && libssh2_knownhost_readfile(hosts, known_hosts, LIBSSH2_KNOWNHOST_FILE_OPENSSH) >= 0 && libssh2_knownhost_checkp(hosts, host, port, key, key_length, mask, NULL) == LIBSSH2_KNOWNHOST_CHECK_MATCH;
    libssh2_knownhost_free(hosts);
    if (!trusted) return -3;
    if (atomic_load(&c->cancelled)) return -2;
    if (password) {
        if (libssh2_userauth_password(c->session, user, password)) return -4;
    } else {
        LIBSSH2_AGENT *agent = libssh2_agent_init(c->session);
        int authenticated = 0;
        if (agent && !libssh2_agent_connect(agent) && !libssh2_agent_list_identities(agent)) {
            struct libssh2_agent_publickey *identity = NULL, *previous = NULL;
            for (int count = 0; count < 64 && !atomic_load(&c->cancelled) && !libssh2_agent_get_identity(agent, &identity, previous); count++) {
                if (!libssh2_agent_userauth(agent, user, identity)) { authenticated = 1; break; }
                previous = identity;
            }
        }
        if (agent) { libssh2_agent_disconnect(agent); libssh2_agent_free(agent); }
        if (!authenticated) return -4;
    }
    c->sftp = libssh2_sftp_init(c->session);
    return c->sftp ? 0 : -5;
}
int wb_sftp_list(wb_sftp *c, const char *path, void *context, void (*entry)(void *, const char *, uint64_t, int)) {
    if (!c || !c->sftp || !valid_path(path) || !entry) return -5;
    LIBSSH2_SFTP_HANDLE *dir = libssh2_sftp_opendir(c->sftp, path);
    if (!dir) return -5;
    char name[4097]; LIBSSH2_SFTP_ATTRIBUTES attrs; int n = 0, count = 0, result = 0;
    while (!atomic_load(&c->cancelled) && (n = libssh2_sftp_readdir(dir, name, sizeof(name)-1, &attrs)) > 0) {
        if (++count > 10000) { result = -6; break; }
        name[n] = 0;
        if (!strcmp(name, ".") || !strcmp(name, "..") || memchr(name, '/', n) || memchr(name, 0, n)) continue;
        entry(context, name, (attrs.flags & LIBSSH2_SFTP_ATTR_SIZE) ? attrs.filesize : 0, (attrs.flags & LIBSSH2_SFTP_ATTR_PERMISSIONS) && LIBSSH2_SFTP_S_ISDIR(attrs.permissions));
    }
    if (n < 0) result = -5;
    libssh2_sftp_closedir(dir);
    return atomic_load(&c->cancelled) ? -2 : result;
}
int wb_sftp_download(wb_sftp *c, const char *path, int fd) {
    if (!c || !c->sftp || !valid_path(path)) return -5;
    LIBSSH2_SFTP_HANDLE *file = libssh2_sftp_open(c->sftp, path, LIBSSH2_FXF_READ, 0);
    if (!file) return -5;
    char buffer[65536]; ssize_t n = 0; int result = 0;
    while (!atomic_load(&c->cancelled) && (n = libssh2_sftp_read(file, buffer, sizeof(buffer))) > 0) {
        ssize_t offset = 0;
        while (offset < n) { ssize_t written = write(fd, buffer + offset, n - offset); if (written <= 0) { result = -5; break; } offset += written; }
        if (result) break;
    }
    if (!atomic_load(&c->cancelled) && n < 0) result = -5;
    libssh2_sftp_close(file); return atomic_load(&c->cancelled) ? -2 : result;
}
int wb_sftp_upload(wb_sftp *c, int fd, const char *temporary_path, const char *destination, int overwrite) {
    if (!c || !c->sftp || !valid_path(temporary_path) || !valid_path(destination)) return -5;
    LIBSSH2_SFTP_HANDLE *file = libssh2_sftp_open(c->sftp, temporary_path, LIBSSH2_FXF_WRITE | LIBSSH2_FXF_CREAT | LIBSSH2_FXF_EXCL, 0600);
    if (!file) return -5;
    char buffer[65536]; ssize_t n = 0; int result = 0;
    while (!atomic_load(&c->cancelled) && (n = read(fd, buffer, sizeof(buffer))) > 0) {
        ssize_t offset = 0;
        while (offset < n && !atomic_load(&c->cancelled)) { ssize_t written = libssh2_sftp_write(file, buffer + offset, n - offset); if (written <= 0) { result = -5; break; } offset += written; }
        if (result) break;
    }
    if (n < 0) result = -5;
    if (libssh2_sftp_close(file)) result = -5;
    if (atomic_load(&c->cancelled)) result = -2;
    if (!result) {
        long flags = LIBSSH2_SFTP_RENAME_ATOMIC | LIBSSH2_SFTP_RENAME_NATIVE;
        if (overwrite) flags |= LIBSSH2_SFTP_RENAME_OVERWRITE;
        int renamed = overwrite ? libssh2_sftp_posix_rename(c->sftp, temporary_path, destination) : libssh2_sftp_rename_ex(c->sftp, temporary_path, (unsigned int)strlen(temporary_path), destination, (unsigned int)strlen(destination), flags);
        if (renamed) result = -5;
    }
    if (result) libssh2_sftp_unlink(c->sftp, temporary_path);
    return result;
}
