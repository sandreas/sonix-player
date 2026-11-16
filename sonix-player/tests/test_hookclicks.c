#include "src/system/input/hookclicks.h"
#include <stdio.h>

#define EXPECT(cond) do { if (!(cond)) { \
    fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); return 1; } } while (0)

int main(void) {
    hook_clicks_t h = {0};
    EXPECT(!hook_clicks_should_expire(&h, 1000, false));

    hook_clicks_press(&h, 1000);
    EXPECT(!hook_clicks_should_expire(&h, 1299, false));
    EXPECT(hook_clicks_should_expire(&h, 1300, false));
    EXPECT(!hook_clicks_should_expire(&h, 1300, true)); /* still held: no click yet */

    hook_clicks_press(&h, 1300);
    EXPECT(hook_clicks_take(&h) == HOOK_GESTURE_NEXT);
    EXPECT(!hook_clicks_pending(&h));

    hook_clicks_press(&h, UINT32_MAX - 100);
    EXPECT(!hook_clicks_should_expire(&h, 50, false));
    EXPECT(hook_clicks_should_expire(&h, (uint32_t)(UINT32_MAX - 100 + HOOK_MULTI_CLICK_MS), false));
    hook_clicks_cancel(&h);

    puts("test_hookclicks: ok");
    return 0;
}
