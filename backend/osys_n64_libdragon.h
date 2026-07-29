#ifndef BACKENDS_PLATFORM_N64LIBDRAGON_OSYS_N64_LIBDRAGON_H
#define BACKENDS_PLATFORM_N64LIBDRAGON_OSYS_N64_LIBDRAGON_H

#include "backends/base-backend.h"
#include "common/str.h"
#include "graphics/palette.h"
#include "graphics/pixelformat.h"
#include "graphics/colormasks.h"
#include "graphics/surface.h"
#include "audio/mixer_intern.h"

#include <libdragon.h>

class OSystem_N64Libdragon : public EventsBaseBackend, public PaletteManager {
public:
    OSystem_N64Libdragon();
    virtual ~OSystem_N64Libdragon();

    virtual void initBackend();

    virtual bool hasFeature(Feature f);
    virtual void setFeatureState(Feature f, bool enable);
    virtual bool getFeatureState(Feature f);

    virtual const GraphicsMode *getSupportedGraphicsModes() const;
    virtual int getDefaultGraphicsMode() const;
    virtual bool setGraphicsMode(const char *name);
    virtual bool setGraphicsMode(int mode);
    virtual int getGraphicsMode() const;

    virtual void initSize(uint width, uint height, const Graphics::PixelFormat *format);
    virtual int16 getHeight();
    virtual int16 getWidth();

    virtual PaletteManager *getPaletteManager() { return this; }
    virtual void setPalette(const byte *colors, uint start, uint num);
    virtual void grabPalette(byte *colors, uint start, uint num);

    virtual void copyRectToScreen(const void *buf, int pitch, int x, int y, int w, int h);
    virtual void updateScreen();
    virtual Graphics::Surface *lockScreen();
    virtual void unlockScreen();
    virtual void setShakePos(int shakeOffset);

    virtual void showOverlay();
    virtual void hideOverlay();
    virtual void clearOverlay();
    virtual void grabOverlay(void *buf, int pitch);
    virtual void copyRectToOverlay(const void *buf, int pitch, int x, int y, int w, int h);
    virtual int16 getOverlayHeight();
    virtual int16 getOverlayWidth();
    virtual Graphics::PixelFormat getOverlayFormat() const {
        return Graphics::createPixelFormat<555>();
    }

    virtual bool showMouse(bool visible);
    virtual void warpMouse(int x, int y);
    virtual void setMouseCursor(const void *buf, uint w, uint h,
                                int hotspotX, int hotspotY, uint32 keycolor,
                                bool dontScale, const Graphics::PixelFormat *format);
    virtual void setCursorPalette(const byte *colors, uint start, uint num);

    virtual bool pollEvent(Common::Event &event);
    virtual uint32 getMillis();
    virtual void delayMillis(uint msecs);

    virtual MutexRef createMutex(void);
    virtual void lockMutex(MutexRef mutex);
    virtual void unlockMutex(MutexRef mutex);
    virtual void deleteMutex(MutexRef mutex);

    virtual void quit();
    virtual Common::String getDefaultConfigFileName();

    virtual Audio::Mixer *getMixer();
    virtual void getTimeAndDate(TimeDate &t) const;
    virtual void logMessage(LogMessageType::Type type, const char *message);

private:
    enum {
        kScreenW = 320,
        kScreenH = 240,
        kAudioHz = 22050
    };

    Audio::MixerImpl *_mixer;
    Graphics::Surface _game;
    uint16 *_game16;
    uint16 *_overlay;
    uint16 _palette[256];
    byte _exactPalette[256 * 3];
    uint16 _cursorPalette[256];
    byte *_cursor;
    uint _cursorW, _cursorH;
    uint32 _cursorKey;
    int _cursorHotX, _cursorHotY;
    bool _cursorUsesGamePalette;

    int _gameW, _gameH;
    int _mouseX, _mouseY;
    float _mouseAccumX, _mouseAccumY;
    int _shake;
    bool _overlayVisible;
    bool _mouseVisible;
    int _graphicsMode;

    uint32 _timerNext;
    uint32 _joypadLastPoll;
    uint32 _mouseLastEvent;
    joypad_inputs_t _joypadInput;
    joypad_buttons_t _lastButtons;
    bool _joypadStateValid;
    bool _game16Dirty;
    bool _screenDirty;

    void serviceAudio();
    void serviceTimer();
    void sampleAnalogMouse(const joypad_inputs_t &in);
    void rebuildGame16();
    int mouseMaxX() const;
    int mouseMaxY() const;
    void clampMouse();
    uint16 overlayPixel(uint16 src) const;
    void drawCursor(surface_t *dst, int xoff, int yoff);
};

#endif
