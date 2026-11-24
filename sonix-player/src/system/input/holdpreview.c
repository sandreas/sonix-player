#include "src/system/input/holdpreview.h"

#include <pthread.h>
#include <stdio.h>
#include <string.h>

static holdpreview_ops_t ops;
static bool active;
static double preview_target;
static double preview_total;
static char preview_file[512];

// Cancel can arrive from the GUI path (a slider seek, a mode change) while the
// input thread is mid-step. One lock keeps the guard check and the seek in the
// same transaction, so an external seek cannot be overwritten afterwards.
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;

void holdpreview_init(const holdpreview_ops_t *new_ops) {
	pthread_mutex_lock(&lock);
	if (new_ops) {
		ops = *new_ops;
	}
	active = false;
	pthread_mutex_unlock(&lock);
}

bool holdpreview_active(void) {
	pthread_mutex_lock(&lock);
	bool value = active;
	pthread_mutex_unlock(&lock);
	return value;
}

double holdpreview_position(void) {
	pthread_mutex_lock(&lock);
	double value = preview_target;
	pthread_mutex_unlock(&lock);
	return value;
}

bool holdpreview_begin(double step, bool forward, bool live, double total, double current, const char *file) {
	pthread_mutex_lock(&lock);
	if (active || !ops.allowed || !ops.status || !ops.seek || !ops.note || !file) {
		pthread_mutex_unlock(&lock);
		return false;
	}
	seek_status_t status = ops.status();
	if (status != SEEK_STATUS_PLAYING || !ops.allowed() || !seekpolicy_can_start(status, live, total)) {
		pthread_mutex_unlock(&lock);
		return false;
	}

	preview_target = holdpreview_target(current, step, total, forward);
	preview_total = total;
	snprintf(preview_file, sizeof(preview_file), "%s", file);
	active = true;
	ops.seek(preview_target);
	pthread_mutex_unlock(&lock);
	return true;
}

// Called with the lock held. One note at the last position, no seek.
static void finish_preview(void) {
	if (!active) {
		return;
	}
	if (ops.note) {
		ops.note(preview_file, preview_target, preview_total);
	}
	active = false;
}

void holdpreview_end(void) {
	pthread_mutex_lock(&lock);
	finish_preview();
	pthread_mutex_unlock(&lock);
}

void holdpreview_cancel(void) {
	pthread_mutex_lock(&lock);
	finish_preview();
	pthread_mutex_unlock(&lock);
}

bool holdpreview_step(double step, bool forward, bool live, double total, double current, const char *file) {
	pthread_mutex_lock(&lock);
	if (!active) {
		pthread_mutex_unlock(&lock);
		return false;
	}

	seek_status_t status = ops.status ? ops.status() : SEEK_STATUS_STOPPED;
	if (status != SEEK_STATUS_PLAYING || !ops.allowed || !ops.allowed() ||
		!seekpolicy_can_start(status, live, total) || !file || strcmp(preview_file, file) != 0) {
		finish_preview();
		pthread_mutex_unlock(&lock);
		return false;
	}

	double target = holdpreview_target(current, step, total, forward);
	if (target == current) {
		finish_preview();
		pthread_mutex_unlock(&lock);
		return false;
	}

	preview_target = target;
	ops.seek(target);
	pthread_mutex_unlock(&lock);
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
