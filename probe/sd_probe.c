#include <libdragon.h>
#include <dirent.h>
#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>

static void draw_lines(const char *lines[], int count) {
    surface_t *disp = display_get();
    graphics_fill_screen(disp, 0);
    for (int i = 0; i < count; i++) {
        graphics_draw_text(disp, 12, 18 + i * 12, lines[i]);
    }
    display_show(disp);
}

int main(void) {
    display_init(RESOLUTION_320x240, DEPTH_16_BPP, 2, GAMMA_NONE, FILTERS_RESAMPLE);
    joypad_init();
    timer_init();
    audio_init(22050, 3);

    debug_init(DEBUG_FEATURE_LOG_USB | DEBUG_FEATURE_LOG_EMU);
    bool sd_ok = debug_init_sdfs("sd:/", -1);

    const char *lines[16];
    char line_mem[64], line_sd[64], line_dir[64], line_rw[64], line_audio[64], line_pad[64];

    snprintf(line_mem, sizeof(line_mem), "Expansion Pak: %s (%lu MiB)",
             is_memory_expanded() ? "YES" : "NO",
             (unsigned long)(get_memory_size() / (1024 * 1024)));

    snprintf(line_sd, sizeof(line_sd), "SD mount: %s", sd_ok ? "OK" : "FAILED");

    DIR *dir = opendir("sd:/fullthrottle");
    bool dir_ok = dir != NULL;
    if (dir) closedir(dir);
    snprintf(line_dir, sizeof(line_dir), "sd:/fullthrottle: %s", dir_ok ? "OK" : "MISSING");

    bool rw_ok = false;
    if (sd_ok) {
        mkdir("sd:/fullthrottle", 0777);
        FILE *f = fopen("sd:/fullthrottle/ft64-r2-probe.txt", "wb");
        if (f) {
            static const char payload[] = "Full Throttle N64 r2 SD probe OK\n";
            size_t wrote = fwrite(payload, 1, sizeof(payload) - 1, f);
            fclose(f);

            f = fopen("sd:/fullthrottle/ft64-r2-probe.txt", "rb");
            if (f) {
                char check[sizeof(payload)] = {0};
                size_t got = fread(check, 1, sizeof(payload) - 1, f);
                fclose(f);
                rw_ok = wrote == sizeof(payload) - 1 &&
                        got == sizeof(payload) - 1 &&
                        memcmp(check, payload, sizeof(payload) - 1) == 0;
            }
        }
    }
    snprintf(line_rw, sizeof(line_rw), "SD write/read: %s", rw_ok ? "OK" : "FAILED");

    snprintf(line_audio, sizeof(line_audio), "Audio: %d Hz / %d samples",
             audio_get_frequency(), audio_get_buffer_length());

    joypad_poll();
    snprintf(line_pad, sizeof(line_pad), "Controller 1: %s",
             joypad_is_connected(JOYPAD_PORT_1) ? "CONNECTED" : "NOT FOUND");

    lines[0] = "FULL THROTTLE N64 - r2";
    lines[1] = "libdragon / SummerCart probe";
    lines[2] = "";
    lines[3] = line_mem;
    lines[4] = line_sd;
    lines[5] = line_dir;
    lines[6] = line_rw;
    lines[7] = line_audio;
    lines[8] = line_pad;
    lines[9] = "";
    lines[10] = "A: re-run SD test";
    lines[11] = "Start: halt";
    lines[12] = "";
    lines[13] = "Expected demo path:";
    lines[14] = "sd:/fullthrottle/";
    lines[15] = "";
    draw_lines(lines, 16);

    debugf("FT64 r2 probe: expanded=%d mem=%lu sd=%d dir=%d rw=%d audio=%dHz\n",
           is_memory_expanded(), (unsigned long)get_memory_size(),
           sd_ok, dir_ok, rw_ok, audio_get_frequency());

    while (1) {
        joypad_poll();
        joypad_buttons_t pressed = joypad_get_buttons_pressed(JOYPAD_PORT_1);

        if (pressed.a) {
            FILE *f = fopen("sd:/fullthrottle/ft64-r2-probe.txt", "ab");
            if (f) {
                fputs("A button re-test OK\n", f);
                fclose(f);
                debugf("FT64 r2: A-button SD append OK\n");
            } else {
                debugf("FT64 r2: A-button SD append FAILED errno=%d\n", errno);
            }
        }

        if (pressed.start)
            break;

        while (audio_can_write())
            audio_write_silence();
    }

    audio_close();
    joypad_close();
    debug_close_sdfs();
    display_close();
    return 0;
}
