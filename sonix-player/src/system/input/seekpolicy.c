#include "src/system/input/seekpolicy.h"

#include <linux/input.h>
#include <string.h>

int seekpolicy_clamp_step(int seconds) {
	if (seconds == 30 || seconds == 60) return seconds;
	return 10;
}

seek_skip_mode_t seekpolicy_mode_from_name(const char *name) {
	return name && strcmp(name, "seek") == 0 ? SEEK_SKIP_SEEK : SEEK_SKIP_TRACK;
}

const char *seekpolicy_mode_name(seek_skip_mode_t mode) {
	return mode == SEEK_SKIP_SEEK ? "seek" : "track";
}

bool seekpolicy_skip_mode_applies(bool receiver_active, bool dlna_owns_playback) {
	return !receiver_active && !dlna_owns_playback;
}

bool seekpolicy_headset_forward(int code) { return code == KEY_REWIND; }

bool seekpolicy_can_start(seek_status_t status, bool live, double total) {
	return status != SEEK_STATUS_STOPPED && !live && total > 0.0;
}

bool seekpolicy_can_commit(seek_status_t status) { return status != SEEK_STATUS_STOPPED; }
