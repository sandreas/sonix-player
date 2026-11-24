#include "src/system/input/seekpolicy.h"
#include <linux/input.h>
#include <stdio.h>

#define EXPECT(cond) do { if (!(cond)) { \
    fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); return 1; } } while (0)

int main(void) {
    EXPECT(seekpolicy_clamp_step(10) == 10);
    EXPECT(seekpolicy_clamp_step(30) == 30);
    EXPECT(seekpolicy_clamp_step(60) == 60);
    EXPECT(seekpolicy_clamp_step(25) == 10);
    EXPECT(seekpolicy_clamp_step(-1) == 10);

    EXPECT(seekpolicy_mode_from_name("seek") == SEEK_SKIP_SEEK);
    EXPECT(seekpolicy_mode_from_name("track") == SEEK_SKIP_TRACK);
    EXPECT(seekpolicy_mode_from_name("bogus") == SEEK_SKIP_TRACK);
    EXPECT(seekpolicy_mode_from_name(NULL) == SEEK_SKIP_TRACK);
    EXPECT(seekpolicy_mode_name(SEEK_SKIP_SEEK)[0] == 's');

    EXPECT(seekpolicy_skip_mode_applies(false, false));
    EXPECT(!seekpolicy_skip_mode_applies(true, false));
    EXPECT(!seekpolicy_skip_mode_applies(false, true));

    /* The shipped earpods driver emits FF for a plain hold and REW for
       click-then-hold; the player convention is plain hold = rewind. */
    EXPECT(!seekpolicy_headset_forward(KEY_FASTFORWARD));
    EXPECT(seekpolicy_headset_forward(KEY_REWIND));

    EXPECT(!seekpolicy_can_start(SEEK_STATUS_STOPPED, false, 300.0));
    EXPECT(!seekpolicy_can_start(SEEK_STATUS_PLAYING, true, 300.0));
    EXPECT(!seekpolicy_can_start(SEEK_STATUS_PLAYING, false, 0.0));
    EXPECT(seekpolicy_can_start(SEEK_STATUS_PLAYING, false, 300.0));
    EXPECT(seekpolicy_can_start(SEEK_STATUS_PAUSED, false, 300.0));

    EXPECT(!seekpolicy_can_commit(SEEK_STATUS_STOPPED));
    EXPECT(seekpolicy_can_commit(SEEK_STATUS_PLAYING));
    EXPECT(seekpolicy_can_commit(SEEK_STATUS_PAUSED));

    puts("test_seekpolicy: ok");
    return 0;
}
