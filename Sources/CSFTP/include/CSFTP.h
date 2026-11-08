#ifndef WB_SFTP_H
#define WB_SFTP_H
#include <stddef.h>
#include <stdint.h>
typedef struct wb_sftp wb_sftp;
wb_sftp *wb_sftp_create(void);
void wb_sftp_cancel(wb_sftp *c);
void wb_sftp_destroy(wb_sftp *c);
int wb_sftp_connect(wb_sftp *c, const char *host, int port, const char *user, const char *password, const char *known_hosts);
int wb_sftp_list(wb_sftp *c, const char *path, void *context, void (*entry)(void *, const char *, uint64_t, int));
int wb_sftp_download(wb_sftp *c, const char *path, int fd);
int wb_sftp_upload(wb_sftp *c, int fd, const char *temporary_path, const char *destination, int overwrite);
int wb_sftp_version(void);
#endif
