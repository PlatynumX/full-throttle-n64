#include <libdragon.h>
#include <dir.h>
#include <errno.h>
#include <stdio.h>
#include <string.h>

static void draw_lines(const char *lines[], int count) {
    surface_t *disp = display_get();
    graphics_fill_screen(disp, 0);
    for (int i = 0; i < count; i++)
        graphics_draw_text(disp, 12, 18 + i * 12, lines[i]);
    display_show(disp);
}

static int ascii_lower(int c) {
    if (c >= 'A' && c <= 'Z')
        return c + ('a' - 'A');
    return c;
}

static bool ascii_ieq(const char *a, const char *b) {
    while (*a && *b) {
        if (ascii_lower((unsigned char)*a) != ascii_lower((unsigned char)*b))
            return false;
        ++a;
        ++b;
    }
    return *a == '\0' && *b == '\0';
}

static bool child_directory_exists(const char *parent, const char *name) {
    dir_t entry;
    int rc = dir_findfirst(parent, &entry);
    bool found = false;
    while (rc == 0) {
        if (!found && entry.d_type == DT_DIR && ascii_ieq(entry.d_name, name))
            found = true;
        rc = dir_findnext(parent, &entry);
    }
    return found;
}

static bool run_rw_test(void) {
    static const char payload[] = "Full Throttle N64 r2v-v19 SD probe OK\n";
    FILE *f = fopen("sd:/fullthrottle/ft64-r2v-v19-probe.txt", "wb");
    if (!f)
        return false;

    size_t wrote = fwrite(payload, 1, sizeof(payload) - 1, f);
    fclose(f);

    f = fopen("sd:/fullthrottle/ft64-r2v-v19-probe.txt", "rb");
    if (!f)
        return false;

    char check[sizeof(payload)] = {0};
    size_t got = fread(check, 1, sizeof(payload) - 1, f);
    fclose(f);
    return wrote == sizeof(payload) - 1 &&
           got == sizeof(payload) - 1 &&
           memcmp(check, payload, sizeof(payload) - 1) == 0;
}

int main(void) {
    display_init(RESOLUTION_320x240, DEPTH_16_BPP, 2, GAMMA_NONE, FILTERS_RESAMPLE);
    joypad_init();
    timer_init();
    audio_init(22050, 3);

    debug_init(DEBUG_FEATURE_LOG_USB | DEBUG_FEATURE_LOG_EMU);
    bool sd_ok = debug_init_sdfs("sd:/", -1);
    const char *lines[16];
    char line_mem[64], line_sd[64], line_dir[64], line_save[64], line_rw[64], line_audio[64], line_pad[64];

    snprintf(line_mem, sizeof(line_mem), "Expansion Pak: %s (%lu MiB)",
             is_memory_expanded() ? "YES" : "NO",
             (unsigned long)(get_memory_size() / (1024 * 1024)));
    snprintf(line_sd, sizeof(line_sd), "SD mount: %s", sd_ok ? "OK" : "FAILED");
    bool dir_ok = sd_ok && child_directory_exists("sd:/", "fullthrottle");
    bool saves_ok = dir_ok && child_directory_exists("sd:/fullthrottle", "saves");
    snprintf(line_dir, sizeof(line_dir), "Game dir: %s", dir_ok ? "OK" : "MISSING");
    snprintf(line_save, sizeof(line_save), "Save dir: %s", saves_ok ? "OK" : "MISSING");

    bool rw_ok = dir_ok && run_rw_test();
    snprintf(line_rw, sizeof(line_rw), "SD write/read: %s", rw_ok ? "OK" : "FAILED");
    snprintf(line_audio, sizeof(line_audio), "Audio: %d Hz / %d samples",
             audio_get_frequency(), audio_get_buffer_length());

    joypad_poll();
    snprintf(line_pad, sizeof(line_pad), "Controller 1: %s",
             joypad_is_connected(JOYPAD_PORT_1) ? "CONNECTED" : "NOT FOUND");
    lines[0] = "FULL THROTTLE N64 - r2v-v19";
    lines[1] = "libdragon / SummerCart probe";
    lines[2] = "";
    lines[3] = line_mem;
    lines[4] = line_sd;
    lines[5] = line_dir;
    lines[6] = line_save;
    lines[7] = line_rw;
    lines[8] = line_audio;
    lines[9] = line_pad;
    lines[10] = "";
    lines[11] = "A: append SD test";
    lines[12] = "Start: halt";
    lines[13] = "Expected path:";
    lines[14] = "sd:/fullthrottle/";
    lines[15] = "";
    draw_lines(lines, 16);
    debugf("FT64 r2v-v19 probe: expanded=%d mem=%lu sd=%d game=%d saves=%d rw=%d audio=%dHz\n",
           is_memory_expanded(), (unsigned long)get_memory_size(),
           sd_ok, dir_ok, saves_ok, rw_ok, audio_get_frequency());

    while (1) {
        joypad_poll();
        joypad_buttons_t pressed = joypad_get_buttons_pressed(JOYPAD_PORT_1);
        if (pressed.a) {
            FILE *f = fopen("sd:/fullthrottle/ft64-r2v-v19-probe.txt", "ab");
            if (f) {
                fputs("A button append OK\n", f);
                fclose(f);
                debugf("FT64 r2v-v19: A-button SD append OK\n");
            } else {
                debugf("FT64 r2v-v19: A-button SD append FAILED errno=%d\n", errno);
            }
        }

        if (pressed.start)
            break;

        while (audio_can_write())
            audio_write_silence();
    }

    audio_close();
    joypad_close();
    timer_close();
    debug_close_sdfs();
    display_close();
    return 0;
}
