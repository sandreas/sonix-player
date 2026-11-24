#include "src/system/input/holdpreview.h"

#include <stdio.h>

static holdpreview_ops_t ops;
static bool active;
static double preview_target;
static double preview_total;
static char preview_file[512];

void holdpreview_init(const holdpreview_ops_t *new_ops) {
	if (new_ops) {
		ops = *new_ops;
	}
	active = false;
}

bool holdpreview_active(void) { return active; }

bool holdpreview_begin(double step, bool forward, bool live, double total, double current, const char *file) {
	if (active || !ops.allowed || !ops.status || !ops.seek || !ops.note || !file) {
		return false;
	}
	seek_status_t status = ops.status();
	if (status != SEEK_STATUS_PLAYING || !ops.allowed() || !seekpolicy_can_start(status, live, total)) {
		return false;
	}

	preview_target = holdpreview_target(current, step, total, forward);
	preview_total = total;
	snprintf(preview_file, sizeof(preview_file), "%s", file);
	active = true;
	ops.seek(preview_target);
	return true;
}

double holdpreview_target(double current, double step, double total, bool forward) {
	if (total <= 0.0) {
		return 0.0;
	}

	double target = forward ? current + step : current - step;
	if (target < 0.0) {
		target = 0.0;
	}
	if (target > total - 1.0) {
		target = total - 1.0;
	}
	return target;
}
