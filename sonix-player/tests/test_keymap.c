#include "src/system/core/config.h"
#include "src/system/input/keymap.h"
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#define EXPECT(cond) do { if (!(cond)) { \
    fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); return 1; } } while (0)

int main(void) {
    char path[] = "/tmp/sonix-keymap-XXXXXX";
    int fd = mkstemp(path);
    if (fd < 0) return 1;
    close(fd);
    EXPECT(config_init(path));

    keymap_init();
    EXPECT(keymap_skip_mode() == SEEK_SKIP_TRACK);
    EXPECT(keymap_seek_step() == 10);

    keymap_set_skip_mode(SEEK_SKIP_SEEK);
    keymap_set_seek_step(30);
    EXPECT(keymap_skip_mode() == SEEK_SKIP_SEEK);
    EXPECT(keymap_seek_step() == 30);

    config_set("keys", "skip_mode", "bogus");
    config_set("keys", "seek_step", "25");
    keymap_init();
    EXPECT(keymap_skip_mode() == SEEK_SKIP_TRACK);
    EXPECT(keymap_seek_step() == 10);

    unlink(path);
    puts("test_keymap: ok");
    return 0;
}
