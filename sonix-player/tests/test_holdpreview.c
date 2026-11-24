#include "src/system/input/holdpreview.h"
#include "src/system/input/seekpolicy.h"

#include <stdio.h>

#define EXPECT(cond) do { if (!(cond)) { \
    fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); return 1; } } while (0)

static int fake_seek_calls;
static double fake_last_target;
static int fake_note_calls;
static double fake_last_note;
static bool fake_allowed;
static seek_status_t fake_status;

static bool fake_allowed_fn(void) { return fake_allowed; }
static seek_status_t fake_status_fn(void) { return fake_status; }

static void fake_seek(double target) {
    fake_seek_calls++;
    fake_last_target = target;
}

static void fake_note(const char *file, double pos, double total) {
    (void)file;
    (void)total;
    fake_note_calls++;
    fake_last_note = pos;
}

static void reset_fakes(void) {
    fake_seek_calls = 0;
    fake_last_target = -1.0;
    fake_note_calls = 0;
    fake_last_note = -1.0;
    fake_allowed = true;
    fake_status = SEEK_STATUS_PLAYING;
    holdpreview_ops_t ops = {fake_allowed_fn, fake_status_fn, fake_seek, fake_note};
    holdpreview_init(&ops);
}

static int test_target_clamps(void) {
    EXPECT(holdpreview_target(30.0, 10.0, 600.0, false) == 20.0);
    EXPECT(holdpreview_target(5.0, 10.0, 600.0, false) == 0.0);
    EXPECT(holdpreview_target(0.0, 10.0, 600.0, false) == 0.0);
    EXPECT(holdpreview_target(595.0, 10.0, 600.0, true) == 599.0);
    return 0;
}

static int test_begin_seeks_first_step(void) {
    reset_fakes();
    EXPECT(holdpreview_begin(10.0, false, false, 600.0, 30.0, "book.flac") == true);
    EXPECT(fake_seek_calls == 1);
    EXPECT(fake_last_target == 20.0);
    EXPECT(holdpreview_active() == true);
    EXPECT(fake_note_calls == 0);
    return 0;
}

static int test_begin_refuses_paused_and_live(void) {
    reset_fakes();
    fake_status = SEEK_STATUS_PAUSED;
    EXPECT(holdpreview_begin(10.0, false, false, 600.0, 30.0, "book.flac") == false);
    EXPECT(fake_seek_calls == 0);
    EXPECT(holdpreview_active() == false);

    reset_fakes();
    EXPECT(holdpreview_begin(10.0, false, true, 600.0, 30.0, "book.flac") == false);
    EXPECT(fake_seek_calls == 0);
    EXPECT(holdpreview_active() == false);
    return 0;
}

int main(void) {
    int rc = test_target_clamps();
    if (rc != 0) return rc;
    rc = test_begin_seeks_first_step();
    if (rc != 0) return rc;
    rc = test_begin_refuses_paused_and_live();
    if (rc != 0) return rc;
    puts("test_holdpreview: ok");
    return 0;
}
