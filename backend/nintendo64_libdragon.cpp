#define FORBIDDEN_SYMBOL_ALLOW_ALL

#include "backends/platform/n64libdragon/osys_n64_libdragon.h"
#include "base/main.h"
#include "common/scummsys.h"

int main(int argc, char *argv[]) {
    (void)argc;
    (void)argv;

    /* Full Throttle requires the N64 Expansion Pak (8 MiB total RAM). */
    assert_memory_expanded();

    g_system = new OSystem_N64Libdragon();
    assert(g_system);

    /*
     * Full Throttle-only appliance launch:
     *   -p sd:/fullthrottle ft
     *
     * This path does not require a pre-existing ScummVM config target.
     */
    const char *ftArgvConst[] = {
        "full-throttle-n64",
        "-p",
        "sd:/fullthrottle",
        "ft"
    };
    char *ftArgv[4];
    for (int i = 0; i < 4; ++i)
        ftArgv[i] = const_cast<char *>(ftArgvConst[i]);

    int res = scummvm_main(4, ftArgv);
    g_system->quit();
    return res;
}
