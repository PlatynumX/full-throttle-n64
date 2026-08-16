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
#include <math.h>

static const OSystem::GraphicsMode s_modes[] = {
    { "320x240", "320x240", 0 },
    { 0, 0, 0 }
};

static inline uint16 rgba5551(byte r, byte g, byte b) {
    return (uint16)(((r >> 3) << 11) | ((g >> 3) << 6) | ((b >> 3) << 1) | 1);
}

static uint32 s_diagLastHeartbeat = 0;
static uint32 s_diagUpdateCalls = 0;
static uint32 s_diagPollCalls = 0;
static uint32 s_diagPresentCalls = 0;
static uint32 s_diagCopyCalls = 0;
static uint32 s_diagFullBlits = 0;
static uint32 s_diagPaletteCalls = 0;

static const size_t kFt64DiagLargeAllocation = 16384;
static bool s_ft64AllocatorDiagReady = false;
static bool s_ft64AllocatorDiagBusy = false;
static uint32 s_ft64AllocatorSequence = 0;
static bool s_ft64FirstUpdateLogged = false;
static bool s_ft64FirstPollLogged = false;

void ft64_diag_heap_marker(const char *tag) {
    if (!s_ft64AllocatorDiagReady || s_ft64AllocatorDiagBusy)
        return;

    s_ft64AllocatorDiagBusy = true;
    heap_stats_t heap;
    sys_get_heap_stats(&heap);
    const uint32 physical = (uint32)get_memory_size();
    const uint32 outsideHeap =
        physical > (uint32)heap.total ? physical - (uint32)heap.total : 0;
    debugf("[FT64DIAG r2v] MEM tag=%s ms=%u expanded=%d physical=%u "
           "outside=%u heap=%d/%d free=%d\n",
           tag ? tag : "?", (unsigned)get_ticks_ms(),
           is_memory_expanded() ? 1 : 0, (unsigned)physical,
           (unsigned)outsideHeap, heap.used, heap.total,
           heap.total - heap.used);
    s_ft64AllocatorDiagBusy = false;
}

void ft64_diag_resource_event(const char *phase, const char *typeName,
                              int typeId, int resourceId,
                              uint32 resourceSize, uint32 allocationSize,
                              uint32 cacheAllocated, uint32 minThreshold,
                              uint32 maxThreshold, uint32 victimSize,
                              int victimCounter) {
    if (!s_ft64AllocatorDiagReady || s_ft64AllocatorDiagBusy)
        return;
    if (allocationSize < kFt64DiagLargeAllocation)
        return;

    s_ft64AllocatorDiagBusy = true;
    void *probe = 0;
    int contiguous = -1;
    if (phase && strcmp(phase, "post-expire") == 0) {
        probe = malloc(allocationSize ? allocationSize : 1);
        contiguous = probe ? 1 : 0;
        if (probe)
            free(probe);
    }

    heap_stats_t heap;
    sys_get_heap_stats(&heap);
    debugf("[FT64DIAG r2v] RES phase=%s type=%s typeId=%d id=%d "
           "resource=%u request=%u cache=%u min=%u max=%u victim=%u "
           "counter=%d contiguous=%d probe=%p heap=%d/%d free=%d\n",
           phase ? phase : "?", typeName ? typeName : "?", typeId,
           resourceId, (unsigned)resourceSize, (unsigned)allocationSize,
           (unsigned)cacheAllocated, (unsigned)minThreshold,
           (unsigned)maxThreshold, (unsigned)victimSize, victimCounter,
           contiguous, probe, heap.used, heap.total, heap.total - heap.used);
    s_ft64AllocatorDiagBusy = false;
}

void ft64_diag_video_opcode(const char *fileName, int scriptId, int roomId,
                            int frameRate, int mode) {
    if (!s_ft64AllocatorDiagReady || s_ft64AllocatorDiagBusy)
        return;

    s_ft64AllocatorDiagBusy = true;
    heap_stats_t heap;
    sys_get_heap_stats(&heap);
    debugf("[FT64DIAG r2v] VIDEO opcode=c9 sub=6 file=%s script=%d "
           "room=%d rate=%d mode=%d ms=%u heap=%d/%d free=%d\n",
           fileName ? fileName : "?", scriptId, roomId, frameRate, mode,
           (unsigned)get_ticks_ms(), heap.used, heap.total,
           heap.total - heap.used);
    s_ft64AllocatorDiagBusy = false;
}

static void ft64_diag_new(uint32 sequence, const char *phase, const char *kind,
                          size_t size, void *result, void *caller,
                          bool forceLog) {
    if (!s_ft64AllocatorDiagReady || s_ft64AllocatorDiagBusy)
        return;
    if (!forceLog && size < kFt64DiagLargeAllocation)
        return;

    s_ft64AllocatorDiagBusy = true;
    heap_stats_t heap;
    sys_get_heap_stats(&heap);
    debugf("[FT64DIAG r2v] NEW seq=%u phase=%s kind=%s size=%u "
           "result=%p caller=%p heap=%d/%d free=%d\n",
           (unsigned)sequence, phase ? phase : "?", kind ? kind : "?",
           (unsigned)size, result, caller, heap.used, heap.total,
           heap.total - heap.used);
    s_ft64AllocatorDiagBusy = false;
}

static void *ft64_allocate_or_abort(const char *kind, size_t size,
                                    void *caller) {
    if (size == 0)
        size = 1;

    const uint32 sequence = ++s_ft64AllocatorSequence;
    ft64_diag_new(sequence, "request", kind, size, 0, caller, false);
    void *result = malloc(size);
    if (!result) {
        ft64_diag_new(sequence, "failed", kind, size, 0, caller, true);
        abort();
    }

    ft64_diag_new(sequence, "allocated", kind, size, result, caller, false);
    return result;
}

void *operator new(size_t size) {
    return ft64_allocate_or_abort("object", size, __builtin_return_address(0));
}

void *operator new[](size_t size) {
    return ft64_allocate_or_abort("array", size, __builtin_return_address(0));
}

OSystem_N64Libdragon::OSystem_N64Libdragon()
    : _mixer(0), _game16(0), _overlay(0), _cursor(0), _cursorW(0), _cursorH(0),
      _cursorKey(0), _cursorHotX(0), _cursorHotY(0),
      _cursorUsesGamePalette(true), _gameW(320), _gameH(200),
      _mouseX(160), _mouseY(100), _mouseAccumX(160.0f), _mouseAccumY(100.0f),
      _shake(0), _overlayVisible(false), _mouseVisible(false), _graphicsMode(0),
      _timerNext(0), _joypadLastPoll(0), _mouseLastEvent(0),
      _joypadStateValid(false), _game16Dirty(true), _screenDirty(true) {

    debug_init(DEBUG_FEATURE_LOG_USB | DEBUG_FEATURE_LOG_EMU);
    s_ft64AllocatorDiagReady = true;
    bool sd = debug_init_sdfs("sd:/", -1);
    debugf("[FT64DIAG r2v] BOOT backend starting; sdfs=%d\n", sd ? 1 : 0);
    ft64_diag_heap_marker("ctor-debug-sdfs");

    display_init(RESOLUTION_320x240, DEPTH_16_BPP, 2, GAMMA_NONE, FILTERS_RESAMPLE);
    ft64_diag_heap_marker("ctor-display");

    joypad_init();
    timer_init();
    ft64_diag_heap_marker("ctor-input-timer");

    audio_init(kAudioHz, 3);
    ft64_diag_heap_marker("ctor-audio");

    _game.create(_gameW, _gameH, Graphics::PixelFormat::createFormatCLUT8());
    ft64_diag_heap_marker("ctor-game8");

    _game16 = (uint16 *)calloc(_gameW * _gameH, sizeof(uint16));
    ft64_diag_heap_marker("ctor-game16");

    _overlay = (uint16 *)calloc(kScreenW * kScreenH, sizeof(uint16));
    ft64_diag_heap_marker("ctor-overlay");
    memset(_palette, 0, sizeof(_palette));
    memset(_exactPalette, 0, sizeof(_exactPalette));
    memset(_cursorPalette, 0, sizeof(_cursorPalette));
    memset(&_joypadInput, 0, sizeof(_joypadInput));
    memset(&_lastButtons, 0, sizeof(_lastButtons));

    _fsFactory = new N64LibdragonFilesystemFactory();
    ft64_diag_heap_marker("ctor-fsfactory");
}

OSystem_N64Libdragon::~OSystem_N64Libdragon() {
    delete _mixer;
    _mixer = 0;
    if (_cursor) free(_cursor);
    _cursor = 0;
    if (_game16) free(_game16);
    _game16 = 0;
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
    ft64_diag_heap_marker("initBackend-enter");

    ConfMan.setInt("autosave_period", 0);
    ConfMan.setBool("FM_high_quality", false);
    ConfMan.setBool("FM_medium_quality", true);

    _savefileManager = new DefaultSaveFileManager("sd:/fullthrottle/saves");
    ft64_diag_heap_marker("initBackend-save");

    _timerManager = new DefaultTimerManager();
    ft64_diag_heap_marker("initBackend-timer");

    _mixer = new Audio::MixerImpl(this, audio_get_frequency());
    _mixer->setReady(true);
    ft64_diag_heap_marker("initBackend-mixer");

    EventsBaseBackend::initBackend();
    ft64_diag_heap_marker("initBackend-events");

    debugf("[FT64DIAG r2v] INIT complete audio=%dHz buffer=%d game=%dx%d\n",
           audio_get_frequency(), audio_get_buffer_length(), _gameW, _gameH);
}

bool OSystem_N64Libdragon::hasFeature(Feature f) {
    return f == kFeatureCursorPalette;
}

void OSystem_N64Libdragon::setFeatureState(Feature f, bool enable) {
    if (f == kFeatureCursorPalette) {
        _cursorUsesGamePalette = !enable;
        _screenDirty = true;
    }
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

    ft64_diag_heap_marker("initSize-before-free");
    _game.free();
    if (_game16) free(_game16);
    _game16 = 0;
    ft64_diag_heap_marker("initSize-after-free");

    _gameW = (int)width;
    _gameH = (int)height;
    debugf("[FT64DIAG r2v] VIDEO initSize %dx%d ms=%u\n",
           _gameW, _gameH, (unsigned)getMillis());

    _game.create(_gameW, _gameH, Graphics::PixelFormat::createFormatCLUT8());
    memset(_game.pixels, 0, _game.pitch * _game.h);
    ft64_diag_heap_marker("initSize-game8");

    _game16 = (uint16 *)calloc(_gameW * _gameH, sizeof(uint16));
    ft64_diag_heap_marker("initSize-game16");

    _mouseX = _gameW / 2;
    _mouseY = _gameH / 2;
    _mouseAccumX = (float)_mouseX;
    _mouseAccumY = (float)_mouseY;
    _game16Dirty = true;
    _screenDirty = true;
}

int16 OSystem_N64Libdragon::getHeight() { return (int16)_gameH; }
int16 OSystem_N64Libdragon::getWidth() { return (int16)_gameW; }

void OSystem_N64Libdragon::setPalette(const byte *colors, uint start, uint num) {
    ++s_diagPaletteCalls;
    if (start >= 256) return;
    num = std::min<uint>(num, 256 - start);
    memcpy(_exactPalette + start * 3, colors, num * 3);
    for (uint i = 0; i < num; ++i) {
        const byte *c = colors + i * 3;
        _palette[start + i] = rgba5551(c[0], c[1], c[2]);
    }

    // Match the historical N64 backend's two-buffer strategy: keep the
    // palettized ScummVM surface and a preconverted 16-bit N64 surface.
    // Palette changes invalidate the converted surface once, rather than
    // forcing a palette lookup for every pixel during display presentation.
    _game16Dirty = true;
    _screenDirty = true;
}

void OSystem_N64Libdragon::grabPalette(byte *colors, uint start, uint num) {
    if (start >= 256) return;
    num = std::min<uint>(num, 256 - start);
    memcpy(colors, _exactPalette + start * 3, num * 3);
}

void OSystem_N64Libdragon::copyRectToScreen(const void *buf, int pitch,
                                             int x, int y, int w, int h) {
    ++s_diagCopyCalls;
    const byte *src = (const byte *)buf;
    if (x < 0) { src -= x; w += x; x = 0; }
    if (y < 0) { src -= y * pitch; h += y; y = 0; }
    if (x + w > _gameW) w = _gameW - x;
    if (y + h > _gameH) h = _gameH - y;
    if (w <= 0 || h <= 0) return;
    if (x == 0 && y == 0 && w == _gameW && h == _gameH)
        ++s_diagFullBlits;

    bool changed = false;
    for (int row = 0; row < h; ++row) {
        const byte *srow = src + row * pitch;
        byte *drow = (byte *)_game.getBasePtr(x, y + row);
        uint16 *hrow = _game16 ? (_game16 + (y + row) * _gameW + x) : 0;

        for (int col = 0; col < w; ++col) {
            const byte p = srow[col];
            if (drow[col] == p)
                continue;

            drow[col] = p;
            if (!_game16Dirty && hrow)
                hrow[col] = _palette[p];
            changed = true;
        }
    }

    if (changed)
        _screenDirty = true;
}

void OSystem_N64Libdragon::rebuildGame16() {
    if (!_game16)
        return;

    for (int y = 0; y < _gameH; ++y) {
        const byte *src = (const byte *)_game.getBasePtr(0, y);
        uint16 *dst = _game16 + y * _gameW;
        for (int x = 0; x < _gameW; ++x)
            dst[x] = _palette[src[x]];
    }

    _game16Dirty = false;
}

uint16 OSystem_N64Libdragon::overlayPixel(uint16 src) const {
    /* ScummVM 1.6.0's N64 555 format places RGB in the same bits as
       libdragon RGBA5551 but has no alpha bit. Mark framebuffer pixels opaque. */
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
    ++s_diagUpdateCalls;
    if (!s_ft64FirstUpdateLogged) {
        s_ft64FirstUpdateLogged = true;
        ft64_diag_heap_marker("first-update");
    }
    serviceAudio();
    serviceTimer();

    const uint32 diagNow = getMillis();
    if (!s_diagLastHeartbeat || (uint32)(diagNow - s_diagLastHeartbeat) >= 1000) {
        heap_stats_t heap;
        sys_get_heap_stats(&heap);
        debugf("[FT64DIAG r2v] HB ms=%u game=%dx%d ovl=%d dirty=%d g16dirty=%d upd=%u poll=%u present=%u copy=%u full=%u pal=%u heap=%d/%d free=%d\n",
               (unsigned)diagNow, _gameW, _gameH, _overlayVisible ? 1 : 0,
               _screenDirty ? 1 : 0, _game16Dirty ? 1 : 0,
               (unsigned)s_diagUpdateCalls, (unsigned)s_diagPollCalls,
               (unsigned)s_diagPresentCalls, (unsigned)s_diagCopyCalls,
               (unsigned)s_diagFullBlits, (unsigned)s_diagPaletteCalls,
               heap.used, heap.total, heap.total - heap.used);
        s_diagLastHeartbeat = diagNow;
    }

    if (!_screenDirty)
        return;

    if (_game16Dirty)
        rebuildGame16();

    surface_t *dst = display_get();
    serviceAudio();

    if (_overlayVisible) {
        for (int y = 0; y < kScreenH; ++y) {
            uint16 *drow = (uint16 *)((byte *)dst->buffer + y * dst->stride);
            const uint16 *srow = _overlay + y * kScreenW;
            for (int x = 0; x < kScreenW; ++x)
                drow[x] = overlayPixel(srow[x]);
        }
        drawCursor(dst, 0, 0);
    } else {
        const int xoff = (kScreenW - _gameW) / 2;
        const int yoff = (kScreenH - _gameH) / 2;
        const int srcStartY = std::min<int>(std::max<int>(_shake, 0), _gameH);
        const int visibleH = _gameH - srcStartY;
        const int gameTop = yoff;
        const int gameBottom = yoff + visibleH;

        for (int y = 0; y < kScreenH; ++y) {
            uint16 *drow = (uint16 *)((byte *)dst->buffer + y * dst->stride);
            if (y < gameTop || y >= gameBottom) {
                memset(drow, 0, kScreenW * sizeof(uint16));
                continue;
            }

            const int sy = srcStartY + (y - gameTop);
            const uint16 *srow = _game16 + sy * _gameW;

            if (xoff > 0)
                memset(drow, 0, xoff * sizeof(uint16));
            memcpy(drow + xoff, srow, _gameW * sizeof(uint16));
            const int right = xoff + _gameW;
            if (right < kScreenW)
                memset(drow + right, 0, (kScreenW - right) * sizeof(uint16));
        }

        drawCursor(dst, xoff, yoff - srcStartY);
    }

    display_show(dst);
    ++s_diagPresentCalls;
    _screenDirty = false;
}

Graphics::Surface *OSystem_N64Libdragon::lockScreen() { return &_game; }

void OSystem_N64Libdragon::unlockScreen() {
    // Direct writers bypass copyRectToScreen(), so the converted copy must be
    // rebuilt before the next presentation.
    _game16Dirty = true;
    _screenDirty = true;
}

void OSystem_N64Libdragon::setShakePos(int shakeOffset) {
    if (_shake != shakeOffset) {
        _shake = shakeOffset;
        _screenDirty = true;
    }
}

void OSystem_N64Libdragon::showOverlay() {
    debugf("[FT64DIAG r2v] OVL show ms=%u game=%dx%d\n",
           (unsigned)getMillis(), _gameW, _gameH);
    _overlayVisible = true;
    clampMouse();
    _mouseAccumX = (float)_mouseX;
    _mouseAccumY = (float)_mouseY;
    _screenDirty = true;
}

void OSystem_N64Libdragon::hideOverlay() {
    debugf("[FT64DIAG r2v] OVL hide ms=%u game=%dx%d\n",
           (unsigned)getMillis(), _gameW, _gameH);
    _overlayVisible = false;
    clampMouse();
    _mouseAccumX = (float)_mouseX;
    _mouseAccumY = (float)_mouseY;
    _screenDirty = true;

    /* The historical ScummVM N64 backend explicitly presented the game
     * immediately when leaving overlay mode because some engines do not issue
     * another screen update at that transition. Do the same here so the last
     * overlay frame cannot remain on-screen indefinitely. */
    updateScreen();
}

void OSystem_N64Libdragon::clearOverlay() {
    /* OSystem::clearOverlay() must make the game graphics visible while the
     * overlay remains active. This backend uses fake alpha blending, so copy
     * the current game image into the overlay exactly as the historical N64
     * backend did instead of clearing the overlay to black. */
    debugf("[FT64DIAG r2v] OVL clear ms=%u game=%dx%d g16dirty=%d\n",
           (unsigned)getMillis(), _gameW, _gameH, _game16Dirty ? 1 : 0);

    if (_game16Dirty)
        rebuildGame16();

    memset(_overlay, 0, kScreenW * kScreenH * sizeof(uint16));

    if (_game16) {
        const int xoff = (kScreenW - _gameW) / 2;
        const int yoff = (kScreenH - _gameH) / 2;
        const int srcStartY = std::min<int>(std::max<int>(_shake, 0), _gameH);
        const int visibleH = _gameH - srcStartY;

        for (int y = 0; y < visibleH; ++y) {
            const uint16 *src = _game16 + (srcStartY + y) * _gameW;
            uint16 *dst = _overlay + (yoff + y) * kScreenW + xoff;
            for (int x = 0; x < _gameW; ++x)
                dst[x] = (uint16)(src[x] & 0xFFFE); // ScummVM RGB555 overlay format
        }
    }

    _screenDirty = true;
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
    _screenDirty = true;
}

int16 OSystem_N64Libdragon::getOverlayHeight() { return kScreenH; }
int16 OSystem_N64Libdragon::getOverlayWidth() { return kScreenW; }

bool OSystem_N64Libdragon::showMouse(bool visible) {
    bool old = _mouseVisible;
    if (_mouseVisible != visible) {
        _mouseVisible = visible;
        _screenDirty = true;
    }
    return old;
}

int OSystem_N64Libdragon::mouseMaxX() const {
    return _overlayVisible ? kScreenW : _gameW;
}

int OSystem_N64Libdragon::mouseMaxY() const {
    return _overlayVisible ? kScreenH : _gameH;
}

void OSystem_N64Libdragon::clampMouse() {
    _mouseX = std::max<int>(0, std::min<int>(_mouseX, mouseMaxX() - 1));
    _mouseY = std::max<int>(0, std::min<int>(_mouseY, mouseMaxY() - 1));
}

void OSystem_N64Libdragon::warpMouse(int x, int y) {
    _mouseX = x;
    _mouseY = y;
    clampMouse();
    _mouseAccumX = (float)_mouseX;
    _mouseAccumY = (float)_mouseY;
    _screenDirty = true;
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
    _screenDirty = true;
}

void OSystem_N64Libdragon::setCursorPalette(const byte *colors, uint start, uint num) {
    if (start >= 256) return;
    num = std::min<uint>(num, 256 - start);
    for (uint i = 0; i < num; ++i) {
        const byte *c = colors + i * 3;
        _cursorPalette[start + i] = rgba5551(c[0], c[1], c[2]);
    }
    _cursorUsesGamePalette = false;
    _screenDirty = true;
}

void OSystem_N64Libdragon::sampleAnalogMouse(const joypad_inputs_t &in) {
    int sx = in.stick_x;
    int sy = in.stick_y;

    // D-pad backup for cursor movement and Full Throttle bike steering.
    if (in.btn.d_left && !in.btn.d_right)
        sx = -60;
    else if (in.btn.d_right && !in.btn.d_left)
        sx = 60;
    if (in.btn.d_up && !in.btn.d_down)
        sy = 60;
    else if (in.btn.d_down && !in.btn.d_up)
        sy = -60;

    // Match the historical ScummVM N64 backend's controller curve. It clamps
    // the useful N64 stick range to +/-60, applies a one-unit deadzone, and
    // uses tangent acceleration. That backend sampled this from VI cadence.
    if (sx > 60) sx = 60;
    else if (sx < -60) sx = -60;
    if (sy > 60) sy = 60;
    else if (sy < -60) sy = -60;

    const int deadzone = 1;
    const double pi = 3.14159265358979323846;
    if (sx > deadzone || sx < -deadzone)
        _mouseAccumX += (float)tan((double)sx * (pi / 140.0));
    if (sy > deadzone || sy < -deadzone)
        _mouseAccumY -= (float)tan((double)sy * (pi / 140.0));

    const float maxX = (float)(mouseMaxX() - 1);
    const float maxY = (float)(mouseMaxY() - 1);
    if (_mouseAccumX < 0.0f) _mouseAccumX = 0.0f;
    if (_mouseAccumY < 0.0f) _mouseAccumY = 0.0f;
    if (_mouseAccumX > maxX) _mouseAccumX = maxX;
    if (_mouseAccumY > maxY) _mouseAccumY = maxY;
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

    ++s_diagPollCalls;
    if (!s_ft64FirstPollLogged) {
        s_ft64FirstPollLogged = true;
        ft64_diag_heap_marker("first-poll");
    }
    const uint32 now = getMillis();
    if (!s_diagLastHeartbeat || (uint32)(now - s_diagLastHeartbeat) >= 1000) {
        heap_stats_t heap;
        sys_get_heap_stats(&heap);
        debugf("[FT64DIAG r2v] HB src=poll ms=%u game=%dx%d ovl=%d dirty=%d g16dirty=%d upd=%u poll=%u present=%u copy=%u full=%u pal=%u heap=%d/%d free=%d\n",
               (unsigned)now, _gameW, _gameH, _overlayVisible ? 1 : 0,
               _screenDirty ? 1 : 0, _game16Dirty ? 1 : 0,
               (unsigned)s_diagUpdateCalls, (unsigned)s_diagPollCalls,
               (unsigned)s_diagPresentCalls, (unsigned)s_diagCopyCalls,
               (unsigned)s_diagFullBlits, (unsigned)s_diagPaletteCalls,
               heap.used, heap.total, heap.total - heap.used);
        s_diagLastHeartbeat = now;
    }


    // libdragon reads Joypads asynchronously from VI. Its public contract says
    // joypad_poll() should synchronize that state once per frame. ScummVM may
    // drain pollEvent() many times in one frame, so do not re-apply analog
    // motion on every drain iteration.
    const uint32 inputPollMs = 16;
    if (!_joypadStateValid || (uint32)(now - _joypadLastPoll) >= inputPollMs) {
        joypad_poll();
        _joypadInput = joypad_get_inputs(JOYPAD_PORT_1);
        _joypadLastPoll = now;
        _joypadStateValid = true;
        sampleAnalogMouse(_joypadInput);
    }

    const joypad_buttons_t buttons = _joypadInput.btn;

    // Primary action: A is the natural face-button action; Z remains an
    // alternate trigger-style primary. Treat both as one logical left mouse
    // button so one cannot generate a release while the other is held.
    const bool primary = buttons.a || buttons.z;
    const bool lastPrimary = _lastButtons.a || _lastButtons.z;
    if (primary != lastPrimary) {
        event.type = primary ? Common::EVENT_LBUTTONDOWN : Common::EVENT_LBUTTONUP;
        event.mouse.x = _mouseX;
        event.mouse.y = _mouseY;
        _lastButtons = buttons;
        return true;
    }

    // Secondary/right mouse. Full Throttle's first scripted bike fight uses
    // this input path.
    if (buttons.b != _lastButtons.b) {
        event.type = buttons.b ? Common::EVENT_RBUTTONDOWN : Common::EVENT_RBUTTONUP;
        event.mouse.x = _mouseX;
        event.mouse.y = _mouseY;
        _lastButtons = buttons;
        return true;
    }

    if (buttons.start != _lastButtons.start) {
        keyEvent(event,
                 buttons.start ? Common::EVENT_KEYDOWN : Common::EVENT_KEYUP,
                 Common::KEYCODE_F5, Common::ASCII_F5);
        _lastButtons = buttons;
        return true;
    }

    if (buttons.l != _lastButtons.l) {
        keyEvent(event,
                 buttons.l ? Common::EVENT_KEYDOWN : Common::EVENT_KEYUP,
                 Common::KEYCODE_ESCAPE, Common::ASCII_ESCAPE);
        _lastButtons = buttons;
        return true;
    }

    // SCUMM '.' skips the current spoken line.
    if (buttons.r != _lastButtons.r) {
        keyEvent(event,
                 buttons.r ? Common::EVENT_KEYDOWN : Common::EVENT_KEYUP,
                 Common::KEYCODE_PERIOD, '.');
        _lastButtons = buttons;
        return true;
    }

    _lastButtons = buttons;

    // The historical N64 port emitted pointer changes at a bounded 40 ms
    // cadence after accumulating VI-sampled analog movement.
    const uint32 mouseEventMs = 40;
    if (!_mouseLastEvent || (uint32)(now - _mouseLastEvent) >= mouseEventMs) {
        _mouseLastEvent = now;
        const int nextX = (int)_mouseAccumX;
        const int nextY = (int)_mouseAccumY;

        if (nextX != _mouseX || nextY != _mouseY) {
            _mouseX = nextX;
            _mouseY = nextY;
            clampMouse();
            _screenDirty = true;

            event.type = Common::EVENT_MOUSEMOVE;
            event.mouse.x = _mouseX;
            event.mouse.y = _mouseY;
            return true;
        }
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
    debugf("[FT64DIAG r2v] QUIT requested ms=%u\n", (unsigned)getMillis());
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
