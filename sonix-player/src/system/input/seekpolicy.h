#ifndef SEEKPOLICY_H
#define SEEKPOLICY_H

#include <stdbool.h>

// The decisions behind the seek gestures, with no LVGL and no device state, so
// that they can be tested on a PC (tests/test_seekpolicy.c). The callers -- the
// keymap, the device state and the input loop -- keep the timers, the audio
// position and the display; this module only answers the questions they ask.

typedef enum { SEEK_STATUS_STOPPED = 0, SEEK_STATUS_PLAYING, SEEK_STATUS_PAUSED } seek_status_t;
typedef enum { SEEK_SKIP_TRACK = 0, SEEK_SKIP_SEEK } seek_skip_mode_t;

// A step of 10, 30 or 60 seconds; anything else falls back to 10.
int seekpolicy_clamp_step(int seconds);

// The skip mode a settings name stands for: "seek" is seek, and every other
// name (including a NULL or a value from an older settings file) is track.
seek_skip_mode_t seekpolicy_mode_from_name(const char *name);
const char *seekpolicy_mode_name(seek_skip_mode_t mode);

// Skip gestures belong to the player alone: a receiver session or a DLNA cast
// is playing the music, so the skip keys must not also jump the local player.
bool seekpolicy_skip_mode_applies(bool receiver_active, bool dlna_owns_playback);

// The direction is crossed: the shipped earpods driver counts presses, so one
// press is FF and two presses are REW, while the player convention is that a
// plain hold rewinds. Physical REWIND therefore means forward to the player.
bool seekpolicy_headset_forward(int code);

// A seek needs a track loaded (not stopped), a known length (total > 0) and is
// pointless on a live stream, which has no timeline to move along.
bool seekpolicy_can_start(seek_status_t status, bool live, double total);

// Only a commit needs somewhere to seek to: a pause is still on the track.
bool seekpolicy_can_commit(seek_status_t status);

#endif /* SEEKPOLICY_H */
