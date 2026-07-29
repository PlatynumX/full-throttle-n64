# Evidence / design notes — r2m

## Hardware observation

The r2l ROM built and booted on real Nintendo 64 hardware with an Expansion
Pak and SummerCart. Full Throttle loaded from `sd:/fullthrottle/` and began
playing its opening movie. Hardware testing then reported:

- SMUSH movie playback stutters.
- The analog stick does not appear to act as the mouse.

Those observations are the reason for the r2m runtime pass. r2m does not claim
either issue is solved until another hardware test confirms it.

## Historical ScummVM N64 analog behavior

Pinned reference:
https://raw.githubusercontent.com/scummvm/scummvm/v1.6.0/backends/platform/n64/osys_n64_events.cpp

The official N64 backend:

- defines `PAD_DEADZONE` as 1 and `PAD_CHECK_TIME` as 40 ms;
- clamps pad analog X/Y to +/-60;
- accumulates movement with `tan(axis * (M_PI / 140))`;
- keeps temporary floating-point mouse coordinates;
- emits the accumulated position as `EVENT_MOUSEMOVE` on the bounded
  `PAD_CHECK_TIME` cadence.

Its VI callback calls `readControllerAnalogInput()`:

https://raw.githubusercontent.com/scummvm/scummvm/v1.6.0/backends/platform/n64/osys_n64_utilities.cpp

## Pinned libdragon input contract

Pinned libdragon commit:
`35f85a0797324a5ed0c723203e33ab3c1da94fdd`

Header:
https://raw.githubusercontent.com/DragonMinded/libdragon/35f85a0797324a5ed0c723203e33ab3c1da94fdd/include/joypad.h

The Joypad subsystem starts reading controllers during VI interrupt.
`joypad_poll()` synchronizes the asynchronously-read state and is intended to
be called once per frame. `joypad_inputs_t` exposes signed `stick_x` and
`stick_y`, with healthy OEM N64 controllers typically reaching roughly
+/-85.

r2m therefore does not invent a new controller model: it combines libdragon's
VI-backed state with the timing/curve behavior already used by ScummVM's
historical N64 port.

## Historical ScummVM N64 video behavior

Pinned reference:
https://raw.githubusercontent.com/scummvm/scummvm/v1.6.0/backends/platform/n64/osys_n64_base.cpp

The historical backend allocates both an 8-bit palettized offscreen buffer and
a 16-bit high-color offscreen buffer. `copyRectToScreen()` updates converted
pixels as the palettized pixels change. A palette change marks the converted
buffer for rebuild. `updateScreen()` skips clean frames and copies the
preconverted high-color image to the framebuffer in bulk.

r2l instead performed the palette lookup for every displayed game pixel inside
every dirty `updateScreen()`. r2m moves back to the historical two-buffer
shape, while using libdragon surfaces and display buffers.

## Later ScummVM evidence

ScummVM 2.7.0 release notes say the project later fixed minor SMUSH timing
issues, mostly affecting Full Throttle, and added a low-latency audio mode for
Full Throttle/The Dig/COMI:

https://docs.scummvm.org/en/v2.7.0/help/release.html

Those later engine changes are noted as a possible next investigation if the
backend presentation optimization is insufficient. They are deliberately NOT
backported in r2m because their exact source changes have not yet been isolated
and validated against the pinned 1.6.0 codebase.

## No game/demo packaging

r2m does not fetch, stage, archive, or upload Full Throttle data. Hardware uses
the user's existing `sd:/fullthrottle/` directory. This removes the now
unnecessary large data transfer from CI without changing the runtime data path.
