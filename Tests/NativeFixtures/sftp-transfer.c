#include "CSFTP.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
static void content(int fd, const char *text) { assert(ftruncate(fd, 0) == 0); assert(lseek(fd, 0, SEEK_SET) == 0); assert(write(fd, text, strlen(text)) == (ssize_t)strlen(text)); assert(lseek(fd, 0, SEEK_SET) == 0); }
int main(int argc, char **argv) {
    assert(argc == 5);
    wb_sftp *client = wb_sftp_create();
    int connected = wb_sftp_connect(client, "127.0.0.1", atoi(argv[1]), argv[2], NULL, argv[3]);
    if (connected) { printf("Loopback SFTP connection status: %d\n", connected); wb_sftp_destroy(client); return 1; }
    char path[4096]; snprintf(path, sizeof(path), "%s/input", argv[4]);
    int input = open(path, O_CREAT | O_RDWR | O_EXCL, 0600); assert(input >= 0);
    content(input, "original-fixture");
    assert(wb_sftp_upload(client, input, ".fixture-partial-a", "uploaded.txt", 0) == 0);
    content(input, "replacement-fixture");
    assert(wb_sftp_upload(client, input, ".fixture-partial-b", "uploaded.txt", 0) != 0);
    snprintf(path, sizeof(path), "%s/refused-output", argv[4]);
    int refused = open(path, O_CREAT | O_RDWR | O_EXCL, 0600); assert(refused >= 0);
    assert(wb_sftp_download(client, "uploaded.txt", refused) == 0);
    assert(lseek(refused, 0, SEEK_SET) == 0);
    char original[64] = {0}; assert(read(refused, original, sizeof(original)-1) == 16);
    assert(strcmp(original, "original-fixture") == 0); close(refused);
    assert(lseek(input, 0, SEEK_SET) == 0);
    assert(wb_sftp_upload(client, input, ".fixture-partial-c", "uploaded.txt", 1) == 0);
    snprintf(path, sizeof(path), "%s/output", argv[4]);
    int output = open(path, O_CREAT | O_RDWR | O_EXCL, 0600); assert(output >= 0);
    assert(wb_sftp_download(client, "uploaded.txt", output) == 0);
    assert(lseek(output, 0, SEEK_SET) == 0);
    char result[64] = {0}; assert(read(output, result, sizeof(result)-1) == 19);
    assert(strcmp(result, "replacement-fixture") == 0);
    close(input); close(output); wb_sftp_destroy(client);
    puts("Loopback SFTP upload/download and overwrite checks passed.");
    return 0;
}
