#define FORBIDDEN_SYMBOL_ALLOW_ALL

#include "backends/platform/n64libdragon/osys_n64_libdragon.h"

#include "backends/platform/n64libdragon/n64libdragon-fs.h"
#include "backends/saves/default/default-saves.h"
#include "backends/timer/default/default-timer.h"
#include "common/config-manager.h"
#include "common/events.h"

#include <algorithm>
#include <cstdlib>
#include <cstring>

static const OSystem::GraphicsMode s_modes[] = {
    { "320x240", "320x240", 0 },
    { 0, 0, 0 }
};

static inline uint16 rgba5551(byte r, byte g, byte b) {
    return (uint16)(((r >> 3) << 11) | ((g >> 3) << 6) | ((b >> 3) << 1) | 1);
}

OSystem_N64Libdragon::OSystem_N64Libdragon()
    : _mixer(0), _overlay(0), _cursor(0), _cursorW(0), _cursorH(0),
      _cursorKey(0), _cursorHotX(0), _cursorHotY(0),
      _cursorUsesGamePalette(true), _gameW(320), _gameH(200),
      _mouseX(160), _mouseY(100), _shake(0), _overlayVisible(false),
      _mouseVisible(false), _graphicsMode(0), _timerNext(0) {

    debug_init(DEBUG_FEATURE_LOG_USB | DEBUG_FEATURE_LOG_EMU);
    bool sd = debug_init_sdfs("sd:/", -1);
    debugf("FT64 r2k: libdragon backend starting; sdfs=%d\n", sd ? 1 : 0);

    display_init(RESOLUTION_320x240, DEPTH_16_BPP, 3, GAMMA_NONE, FILTERS_RESAMPLE);
    joypad_init();
    timer_init();
    audio_init(kAudioHz, 3);

    _game.create(_gameW, _gameH, Graphics::PixelFormat::createFormatCLUT8());
    _overlay = (uint16 *)calloc(kScreenW * kScreenH, sizeof(uint16));
    memset(_palette, 0, sizeof(_palette));
    memset(_exactPalette, 0, sizeof(_exactPalette));
    memset(_cursorPalette, 0, sizeof(_cursorPalette));

    _fsFactory = new N64LibdragonFilesystemFactory();
}

OSystem_N64Libdragon::~OSystem_N64Libdragon() {
    delete _mixer;
    _mixer = 0;
    if (_cursor) free(_cursor);
    _cursor = 0;
    if (_overlay) free(_overlay);
    _overlay = 0;
    _game.free();

    audio_close();
    joypad_close();
    timer_close();
    debug_close_sdfs();
    display_close();
}

void OSystem_N64Libdragon::initBackend() {
    ConfMan.setInt("autosave_period", 0);
    ConfMan.setBool("FM_high_quality", false);
    ConfMan.setBool("FM_medium_quality", true);

    _savefileManager = new DefaultSaveFileManager("sd:/fullthrottle/saves");
    _timerManager = new DefaultTimerManager();

    _mixer = new Audio::MixerImpl(this, audio_get_frequency());
    _mixer->setReady(true);

    EventsBaseBackend::initBackend();

    debugf("FT64 r2k: backend init complete; audio=%d Hz buffer=%d\n",
           audio_get_frequency(), audio_get_buffer_length());
}

bool OSystem_N64Libdragon::hasFeature(Feature f) {
    return f == kFeatureCursorPalette;
}

void OSystem_N64Libdragon::setFeatureState(Feature f, bool enable) {
    if (f == kFeatureCursorPalette)
        _cursorUsesGamePalette = !enable;
}

bool OSystem_N64Libdragon::getFeatureState(Feature f) {
    if (f == kFeatureCursorPalette)
        return !_cursorUsesGamePalette;
    return false;
}

const OSystem::GraphicsMode *OSystem_N64Libdragon::getSupportedGraphicsModes() const {
    return s_modes;
}

int OSystem_N64Libdragon::getDefaultGraphicsMode() const { return 0; }

bool OSystem_N64Libdragon::setGraphicsMode(const char *name) {
    (void)name;
    _graphicsMode = 0;
    return true;
}

bool OSystem_N64Libdragon::setGraphicsMode(int mode) {
    _graphicsMode = mode;
    return true;
}

int OSystem_N64Libdragon::getGraphicsMode() const { return _graphicsMode; }

void OSystem_N64Libdragon::initSize(uint width, uint height, const Graphics::PixelFormat *format) {
    (void)format;
    width = std::min<uint>(width, kScreenW);
    height = std::min<uint>(height, kScreenH);

    _game.free();
    _gameW = (int)width;
    _gameH = (int)height;
    _game.create(_gameW, _gameH, Graphics::PixelFormat::createFormatCLUT8());
    memset(_game.pixels, 0, _game.pitch * _game.h);

    _mouseX = _gameW / 2;
    _mouseY = _gameH / 2;
}

int16 OSystem_N64Libdragon::getHeight() { return (int16)_gameH; }
int16 OSystem_N64Libdragon::getWidth() { return (int16)_gameW; }

void OSystem_N64Libdragon::setPalette(const byte *colors, uint start, uint num) {
    if (start >= 256) return;
    num = std::min<uint>(num, 256 - start);
    memcpy(_exactPalette + start * 3, colors, num * 3);
    for (uint i = 0; i < num; ++i) {
        const byte *c = colors + i * 3;
        _palette[start + i] = rgba5551(c[0], c[1], c[2]);
    }
}

void OSystem_N64Libdragon::grabPalette(byte *colors, uint start, uint num) {
    if (start >= 256) return;
    num = std::min<uint>(num, 256 - start);
    memcpy(colors, _exactPalette + start * 3, num * 3);
}

void OSystem_N64Libdragon::copyRectToScreen(const void *buf, int pitch,
                                             int x, int y, int w, int h) {
    const byte *src = (const byte *)buf;
    if (x < 0) { src -= x; w += x; x = 0; }
    if (y < 0) { src -= y * pitch; h += y; y = 0; }
    if (x + w > _gameW) w = _gameW - x;
    if (y + h > _gameH) h = _gameH - y;
    if (w <= 0 || h <= 0) return;

    for (int row = 0; row < h; ++row) {
        memcpy((byte *)_game.getBasePtr(x, y + row), src + row * pitch, w);
    }
}

uint16 OSystem_N64Libdragon::palettePixel(byte idx) const {
    return _palette[idx];
}

uint16 OSystem_N64Libdragon::overlayPixel(uint16 src) const {
    /* On __N64__, ScummVM's 555 overlay is already RRRRRGGGGGBBBBB0.
       libdragon RGBA5551 uses the same color-bit placement; set alpha opaque. */
    return (uint16)(src | 1);
}

void OSystem_N64Libdragon::drawCursor(surface_t *dst, int xoff, int yoff) {
    if (!_mouseVisible || !_cursor || !_cursorW || !_cursorH) return;

    const uint16 *cpal = _cursorUsesGamePalette ? _palette : _cursorPalette;
    for (uint cy = 0; cy < _cursorH; ++cy) {
        int dy = yoff + _mouseY - _cursorHotY + (int)cy;
        if (dy < 0 || dy >= kScreenH) continue;
        uint16 *drow = (uint16 *)((byte *)dst->buffer + dy * dst->stride);

        for (uint cx = 0; cx < _cursorW; ++cx) {
            int dx = xoff + _mouseX - _cursorHotX + (int)cx;
            if (dx < 0 || dx >= kScreenW) continue;

            byte p = _cursor[cy * _cursorW + cx];
            if (p != (byte)_cursorKey)
                drow[dx] = cpal[p];
        }
    }
}

void OSystem_N64Libdragon::serviceAudio() {
    if (!_mixer) return;

    while (audio_can_write()) {
        short *out = audio_write_begin();
        const int frames = audio_get_buffer_length();
        _mixer->mixCallback((byte *)out, frames * 2 * (int)sizeof(short));
        audio_write_end();
    }
}

void OSystem_N64Libdragon::serviceTimer() {
    if (!_timerManager) return;

    /* ScummVM 1.6.0's DefaultTimerManager must be pumped by the backend.
     * The historical N64 backend used a 10 ms periodic callback, so retain
     * that resolution without depending on an interrupt-context callback. */
    const uint32 interval = 10;
    uint32 now = getMillis();
    if (!_timerNext)
        _timerNext = now + interval;

    int catchUp = 0;
    while ((int32)(now - _timerNext) >= 0 && catchUp++ < 4) {
        static_cast<DefaultTimerManager *>(_timerManager)->handler();
        _timerNext += interval;
    }

    if (catchUp >= 4)
        _timerNext = now + interval;
}

void OSystem_N64Libdragon::updateScreen() {
    serviceAudio();
    serviceTimer();

    surface_t *dst = display_get();
    for (int y = 0; y < kScreenH; ++y) {
        uint16 *drow = (uint16 *)((byte *)dst->buffer + y * dst->stride);
        memset(drow, 0, kScreenW * sizeof(uint16));
    }

    if (_overlayVisible) {
        for (int y = 0; y < kScreenH; ++y) {
            uint16 *drow = (uint16 *)((byte *)dst->buffer + y * dst->stride);
            const uint16 *srow = _overlay + y * kScreenW;
            for (int x = 0; x < kScreenW; ++x)
                drow[x] = overlayPixel(srow[x]);
        }
        drawCursor(dst, 0, 0);
    } else {
        int xoff = (kScreenW - _gameW) / 2;
        int yoff = (kScreenH - _gameH) / 2;
        const int srcStartY = std::min<int>(std::max<int>(_shake, 0), _gameH);

        for (int y = srcStartY; y < _gameH; ++y) {
            int dy = yoff + y - srcStartY;
            if (dy < 0 || dy >= kScreenH) continue;
            uint16 *drow = (uint16 *)((byte *)dst->buffer + dy * dst->stride);
            const byte *srow = (const byte *)_game.getBasePtr(0, y);
            for (int x = 0; x < _gameW; ++x)
                drow[xoff + x] = palettePixel(srow[x]);
        }
        drawCursor(dst, xoff, yoff - srcStartY);
    }

    display_show(dst);
}

Graphics::Surface *OSystem_N64Libdragon::lockScreen() { return &_game; }
void OSystem_N64Libdragon::unlockScreen() {}
void OSystem_N64Libdragon::setShakePos(int shakeOffset) { _shake = shakeOffset; }

void OSystem_N64Libdragon::showOverlay() { _overlayVisible = true; }
void OSystem_N64Libdragon::hideOverlay() { _overlayVisible = false; }

void OSystem_N64Libdragon::clearOverlay() {
    memset(_overlay, 0, kScreenW * kScreenH * sizeof(uint16));
}

void OSystem_N64Libdragon::grabOverlay(void *buf, int pitch) {
    byte *dst = (byte *)buf;
    for (int y = 0; y < kScreenH; ++y)
        memcpy(dst + y * pitch, _overlay + y * kScreenW, kScreenW * sizeof(uint16));
}

void OSystem_N64Libdragon::copyRectToOverlay(const void *buf, int pitch,
                                              int x, int y, int w, int h) {
    const byte *src = (const byte *)buf;
    if (x < 0) { src -= x * 2; w += x; x = 0; }
    if (y < 0) { src -= y * pitch; h += y; y = 0; }
    if (x + w > kScreenW) w = kScreenW - x;
    if (y + h > kScreenH) h = kScreenH - y;
    if (w <= 0 || h <= 0) return;

    for (int row = 0; row < h; ++row)
        memcpy(_overlay + (y + row) * kScreenW + x,
               src + row * pitch, w * sizeof(uint16));
}

int16 OSystem_N64Libdragon::getOverlayHeight() { return kScreenH; }
int16 OSystem_N64Libdragon::getOverlayWidth() { return kScreenW; }

bool OSystem_N64Libdragon::showMouse(bool visible) {
    bool old = _mouseVisible;
    _mouseVisible = visible;
    return old;
}

void OSystem_N64Libdragon::clampMouse() {
    _mouseX = std::max<int>(0, std::min<int>(_mouseX, _gameW - 1));
    _mouseY = std::max<int>(0, std::min<int>(_mouseY, _gameH - 1));
}

void OSystem_N64Libdragon::warpMouse(int x, int y) {
    _mouseX = x;
    _mouseY = y;
    clampMouse();
}

void OSystem_N64Libdragon::setMouseCursor(const void *buf, uint w, uint h,
                                           int hotspotX, int hotspotY,
                                           uint32 keycolor, bool dontScale,
                                           const Graphics::PixelFormat *format) {
    (void)dontScale;
    (void)format;

    free(_cursor);
    _cursor = 0;
    _cursorW = w;
    _cursorH = h;
    _cursorHotX = hotspotX;
    _cursorHotY = hotspotY;
    _cursorKey = keycolor;

    if (w && h) {
        _cursor = (byte *)malloc(w * h);
        if (_cursor)
            memcpy(_cursor, buf, w * h);
    }
}

void OSystem_N64Libdragon::setCursorPalette(const byte *colors, uint start, uint num) {
    if (start >= 256) return;
    num = std::min<uint>(num, 256 - start);
    for (uint i = 0; i < num; ++i) {
        const byte *c = colors + i * 3;
        _cursorPalette[start + i] = rgba5551(c[0], c[1], c[2]);
    }
    _cursorUsesGamePalette = false;
}

static void keyEvent(Common::Event &event, Common::EventType type,
                     Common::KeyCode keycode, uint16 ascii) {
    event.type = type;
    event.kbd.keycode = keycode;
    event.kbd.ascii = ascii;
    event.kbd.flags = 0;
}

bool OSystem_N64Libdragon::pollEvent(Common::Event &event) {
    serviceAudio();
    serviceTimer();

    joypad_poll();
    joypad_inputs_t in = joypad_get_inputs(JOYPAD_PORT_1);
    joypad_buttons_t down = joypad_get_buttons_pressed(JOYPAD_PORT_1);
    joypad_buttons_t up = joypad_get_buttons_released(JOYPAD_PORT_1);

    static int lastX = -1, lastY = -1;
    const int dead = 12;
    if (in.stick_x > dead || in.stick_x < -dead)
        _mouseX += in.stick_x / 16;
    if (in.stick_y > dead || in.stick_y < -dead)
        _mouseY -= in.stick_y / 16;
    clampMouse();

    if (_mouseX != lastX || _mouseY != lastY) {
        lastX = _mouseX;
        lastY = _mouseY;
        event.type = Common::EVENT_MOUSEMOVE;
        event.mouse.x = _mouseX;
        event.mouse.y = _mouseY;
        return true;
    }

    if (down.z || up.z) {
        event.type = down.z ? Common::EVENT_LBUTTONDOWN : Common::EVENT_LBUTTONUP;
        event.mouse.x = _mouseX; event.mouse.y = _mouseY;
        return true;
    }
    if (down.b || up.b) {
        event.type = down.b ? Common::EVENT_RBUTTONDOWN : Common::EVENT_RBUTTONUP;
        event.mouse.x = _mouseX; event.mouse.y = _mouseY;
        return true;
    }
    if (down.start) {
        keyEvent(event, Common::EVENT_KEYDOWN, Common::KEYCODE_F5, Common::ASCII_F5);
        return true;
    }
    if (up.start) {
        keyEvent(event, Common::EVENT_KEYUP, Common::KEYCODE_F5, Common::ASCII_F5);
        return true;
    }
    if (down.l) {
        keyEvent(event, Common::EVENT_KEYDOWN, Common::KEYCODE_ESCAPE, Common::ASCII_ESCAPE);
        return true;
    }
    if (up.l) {
        keyEvent(event, Common::EVENT_KEYUP, Common::KEYCODE_ESCAPE, Common::ASCII_ESCAPE);
        return true;
    }
    if (down.a) {
        keyEvent(event, Common::EVENT_KEYDOWN, Common::KEYCODE_PERIOD, '.');
        return true;
    }
    if (up.a) {
        keyEvent(event, Common::EVENT_KEYUP, Common::KEYCODE_PERIOD, '.');
        return true;
    }

    return false;
}

uint32 OSystem_N64Libdragon::getMillis() {
    return (uint32)get_ticks_ms();
}

void OSystem_N64Libdragon::delayMillis(uint msecs) {
    uint32 end = getMillis() + msecs;
    while ((int32)(getMillis() - end) < 0) {
        serviceAudio();
        serviceTimer();
    }
}

OSystem::MutexRef OSystem_N64Libdragon::createMutex(void) { return 0; }
void OSystem_N64Libdragon::lockMutex(MutexRef mutex) { (void)mutex; }
void OSystem_N64Libdragon::unlockMutex(MutexRef mutex) { (void)mutex; }
void OSystem_N64Libdragon::deleteMutex(MutexRef mutex) { (void)mutex; }

void OSystem_N64Libdragon::quit() {
    debugf("FT64 r2k: quit requested\n");
}

Common::String OSystem_N64Libdragon::getDefaultConfigFileName() {
    return Common::String("sd:/fullthrottle/scummvm.ini");
}

Audio::Mixer *OSystem_N64Libdragon::getMixer() { return _mixer; }

void OSystem_N64Libdragon::getTimeAndDate(TimeDate &t) const {
    /* A stock N64 has no real-time clock. Give ScummVM a stable calendar
     * while advancing time-of-day from system uptime. Full Throttle does
     * not depend on wall-clock time. */
    const uint32 seconds = (uint32)(get_ticks_ms() / 1000ULL);
    memset(&t, 0, sizeof(t));
    t.tm_sec = seconds % 60;
    t.tm_min = (seconds / 60) % 60;
    t.tm_hour = (seconds / 3600) % 24;
    t.tm_mday = 1;
    t.tm_mon = 0;
    t.tm_year = 100; /* 2000 */
    t.tm_wday = 6;
}

void OSystem_N64Libdragon::logMessage(LogMessageType::Type type, const char *message) {
    (void)type;
    debugf("%s", message ? message : "");
}
