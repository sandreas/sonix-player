# Issue 147 — device checklist

Run these on a real R1 and R3 Pro II, with and without the wired headset. Record
the `sonix_player.log` lines around each gesture. Tick nothing that was not run.

## Buttons, Track mode (default)

- [ ] Short next: next track / next episode; no seek.
- [ ] Hold next: seeks forward; release produces one `seeking to` line.
- [ ] Short previous: previous track (or restart under three seconds).
- [ ] Hold previous: seeks back; one seek on release.
- [ ] Paused before a hold: still paused after.
- [ ] Stopped before a hold: nothing starts.
- [ ] Live radio: hold does nothing; release steps station.

## Buttons, Seek mode

- [ ] Tap next: one seek step forward; no track change.
- [ ] Hold next: repeated steps; one seek on release.
- [ ] Tap play: play/pause.
- [ ] Hold play on R1: rewinds; no play/pause toggle.
- [ ] Seek step 10/30/60 changes the step size.
- [ ] Bluetooth receiver mode: next/previous still reach the phone; no local scrub.
- [ ] DLNA active: next/previous ask the phone; no local scrub.

## Wired headset

- [ ] One click: play/pause once.
- [ ] Two clicks: next chapter in a book, next track in music.
- [ ] Three clicks: previous chapter/track with the three-second rule.
- [ ] Plain hold (driver FF): rewinds; no play/pause; one commit on release.
- [ ] Click then hold (driver REW): fast-forwards; no play/pause; one commit.
- [ ] Hold longer than 10 s: keeps seeking, one commit on release, no second commit.
- [ ] Two single clicks 700 ms apart: both play/pause (`tests/input/headset-two-gestures.txt`).
- [ ] Unplug mid-hold: the open scrub commits and the UI does not freeze.
- [ ] Paused/stopped/live: no state change, no start.

## Regression

- [ ] Volume repeat, double-click, power long-press, key lock.
- [ ] USB DAC, Wi-Fi transfer and metronome: no seek.
- [ ] All 24 language files load and show the new strings.
