#include "CSFTP.h"
#include <assert.h>
int main(void) {
    wb_sftp *client = wb_sftp_create();
    assert(client);
    assert(wb_sftp_connect(client, "localhost", 0, "fixture", 0, "/nonexistent") != 0);
    wb_sftp_cancel(client);
    assert(wb_sftp_connect(client, "localhost", 22, "fixture", 0, "/nonexistent") == -2);
    wb_sftp_cancel(client);
    wb_sftp_destroy(client);
    return 0;
}
