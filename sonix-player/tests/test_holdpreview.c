#include "src/system/input/holdpreview.h"

#include <stdio.h>

#define EXPECT(cond) do { if (!(cond)) { \
    fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); return 1; } } while (0)

static int test_target_clamps(void) {
    EXPECT(holdpreview_target(30.0, 10.0, 600.0, false) == 20.0);
    EXPECT(holdpreview_target(5.0, 10.0, 600.0, false) == 0.0);
    EXPECT(holdpreview_target(0.0, 10.0, 600.0, false) == 0.0);
    EXPECT(holdpreview_target(595.0, 10.0, 600.0, true) == 599.0);
    return 0;
}

int main(void) {
    int rc = test_target_clamps();
    if (rc != 0) {
        return rc;
    }
    puts("test_holdpreview: ok");
    return 0;
}
