#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path
import sys
from typing import Iterable, List, Sequence, Tuple


class TransformError(RuntimeError):
    pass


def clean(line: str) -> str:
    return line.strip()


def read_lines(path: Path) -> tuple[list[str], bool]:
    text = path.read_text()
    return text.splitlines(), text.endswith("\n")


def write_lines(path: Path, lines: Sequence[str], final_newline: bool) -> None:
    text = "\n".join(lines)
    if final_newline:
        text += "\n"
    path.write_text(text)


def find_unique_line(
    lines: Sequence[str],
    target: str,
    label: str,
    start: int = 0,
    end: int | None = None,
) -> int:
    limit = len(lines) if end is None else end
    matches = [
        idx for idx in range(start, limit)
        if clean(lines[idx]) == target
    ]
    if len(matches) != 1:
        raise TransformError(
            f"{label}: expected one stripped-line match for {target!r}, "
            f"found {len(matches)} at {[m + 1 for m in matches]}"
        )
    return matches[0]


def find_unique_sequence(
    lines: Sequence[str],
    targets: Sequence[str],
    label: str,
    start: int = 0,
    end: int | None = None,
) -> tuple[int, int]:
    limit = len(lines) if end is None else end
    norm = [clean(line) for line in lines]
    matches: list[int] = []
    width = len(targets)
    for idx in range(start, limit - width + 1):
        if norm[idx:idx + width] == list(targets):
            matches.append(idx)
    if len(matches) != 1:
        raise TransformError(
            f"{label}: expected one stripped sequence {list(targets)!r}, "
            f"found {len(matches)} at {[m + 1 for m in matches]}"
        )
    return matches[0], matches[0] + width - 1


def find_preprocessor_end(lines: Sequence[str], start: int, label: str) -> int:
    if not clean(lines[start]).startswith(("#if ", "#if(", "#ifdef ", "#ifndef ")):
        raise TransformError(f"{label}: line {start + 1} is not a preprocessor opener")
    depth = 0
    for idx in range(start, len(lines)):
        token = clean(lines[idx])
        if token.startswith(("#if ", "#if(", "#ifdef ", "#ifndef ")):
            depth += 1
        elif token == "#endif" or token.startswith("#endif "):
            depth -= 1
            if depth == 0:
                return idx
    raise TransformError(f"{label}: unterminated preprocessor block at line {start + 1}")


def _brace_delta_for_line(line: str, state: dict[str, object]) -> int:
    delta = 0
    i = 0
    in_block = bool(state.get("block"))
    quote = state.get("quote")
    escape = bool(state.get("escape"))
    while i < len(line):
        ch = line[i]
        nxt = line[i + 1] if i + 1 < len(line) else ""

        if in_block:
            if ch == "*" and nxt == "/":
                in_block = False
                i += 2
                continue
            i += 1
            continue

        if quote:
            if escape:
                escape = False
            elif ch == "\\":
                escape = True
            elif ch == quote:
                quote = None
            i += 1
            continue

        if ch == "/" and nxt == "/":
            break
        if ch == "/" and nxt == "*":
            in_block = True
            i += 2
            continue
        if ch in ('"', "'"):
            quote = ch
            escape = False
            i += 1
            continue
        if ch == "{":
            delta += 1
        elif ch == "}":
            delta -= 1
        i += 1

    state["block"] = in_block
    state["quote"] = quote
    state["escape"] = escape
    return delta


def find_braced_region(lines: Sequence[str], start: int, label: str) -> tuple[int, int]:
    state: dict[str, object] = {"block": False, "quote": None, "escape": False}
    depth = 0
    found = False
    open_line = -1
    for idx in range(start, len(lines)):
        delta = _brace_delta_for_line(lines[idx], state)
        if not found and delta > 0:
            found = True
            open_line = idx
        if found:
            depth += delta
            if depth == 0:
                return open_line, idx
    raise TransformError(f"{label}: could not find a balanced braced region from line {start + 1}")


def guard_region(
    lines: list[str],
    start: int,
    end: int,
    label: str,
) -> None:
    original = lines[start:end + 1]
    lines[start:end + 1] = [
        "#ifndef N64_FT_ONLY",
        f"// FT64 r2v structural: {label}",
        *original,
        "#endif",
    ]


def conditional_region(
    lines: list[str],
    start: int,
    end: int,
    fixed_lines: Sequence[str],
    label: str,
) -> None:
    original = lines[start:end + 1]
    lines[start:end + 1] = [
        "#ifdef N64_FT_ONLY",
        f"// FT64 r2v structural: {label}",
        *fixed_lines,
        "#else",
        *original,
        "#endif",
    ]


def guard_unique_line(lines: list[str], target: str, label: str) -> None:
    idx = find_unique_line(lines, target, label)
    guard_region(lines, idx, idx, label)


def guard_unique_sequence(
    lines: list[str], targets: Sequence[str], label: str
) -> None:
    start, end = find_unique_sequence(lines, targets, label)
    guard_region(lines, start, end, label)


def guard_whole_function(lines: list[str], signature: str, label: str) -> None:
    sig = find_unique_line(lines, signature, label)
    _, close = find_braced_region(lines, sig, label)
    original = lines[sig:close + 1]
    lines[sig:close + 1] = [
        "#ifndef N64_FT_ONLY",
        f"// FT64 r2v structural: {label}",
        *original,
        "#endif",
    ]


def conditional_function_body(
    lines: list[str],
    signature: str,
    fixed_lines: Sequence[str],
    label: str,
) -> None:
    sig = find_unique_line(lines, signature, label)
    open_line, close_line = find_braced_region(lines, sig, label)
    if close_line <= open_line:
        raise TransformError(f"{label}: empty or malformed function")
    conditional_region(lines, open_line + 1, close_line - 1, fixed_lines, label)


def transform_main(lines: list[str]) -> list[str]:
    lines = list(lines)

    guard_unique_line(
        lines, '#include "common/EventRecorder.h"', "guard EventRecorder include"
    )
    guard_unique_sequence(
        lines,
        [
            '#include "audio/mididrv.h"',
            '#include "audio/musicplugin.h"  /* for music manager */',
        ],
        "guard generic music includes",
    )
    guard_unique_line(
        lines, '#include "graphics/yuv_to_rgb.h"', "guard YUV manager include"
    )

    keymapper = find_unique_line(
        lines, '#include "backends/keymapper/keymapper.h"', "find keymapper include"
    )
    launcher_if_matches = [
        idx for idx in range(keymapper + 1, len(lines))
        if clean(lines[idx]) == "#if defined(_WIN32_WCE)"
    ]
    if not launcher_if_matches:
        raise TransformError("guard launcher includes: opener not found after keymapper")
    launcher_if = launcher_if_matches[0]
    launcher_end = find_preprocessor_end(
        lines, launcher_if, "guard launcher includes"
    )
    guard_region(lines, launcher_if, launcher_end, "guard launcher includes")

    guard_whole_function(
        lines, "static bool launcherDialog() {", "guard launcher function"
    )

    music_if = find_unique_line(
        lines,
        'if (settings.contains("music-driver")) {',
        "guard music-driver validation",
    )
    _, music_end = find_braced_region(
        lines, music_if, "guard music-driver validation"
    )
    guard_region(
        lines, music_if, music_end, "guard music-driver validation"
    )

    guard_unique_sequence(
        lines,
        ["system.getAudioCDManager();", "MusicManager::instance();"],
        "guard global music managers",
    )
    guard_unique_line(
        lines, "g_eventRec.init();", "guard EventRecorder init"
    )
    guard_unique_sequence(
        lines,
        [
            "if (0 == ConfMan.getActiveDomain())",
            "launcherDialog();",
        ],
        "guard initial launcher",
    )
    guard_unique_line(
        lines, "g_eventRec.deinit();", "guard EventRecorder deinit"
    )

    tail_start, tail_end = find_unique_sequence(
        lines,
        [
            "// reset the graphics to default",
            "setupGraphics(system);",
            "launcherDialog();",
        ],
        "replace return-to-launcher tail",
    )
    conditional_region(
        lines,
        tail_start,
        tail_end,
        ["\t\tbreak;"],
        "replace return-to-launcher tail",
    )

    guard_unique_line(
        lines,
        "Common::EventRecorder::destroy();",
        "guard EventRecorder destroy",
    )
    guard_unique_line(
        lines, "MusicManager::destroy();", "guard MusicManager destroy"
    )
    guard_unique_line(
        lines,
        "Graphics::YUVToRGBManager::destroy();",
        "guard YUV manager destroy",
    )
    return lines


def transform_detection(lines: list[str]) -> list[str]:
    lines = list(lines)
    comment = find_unique_line(
        lines,
        "// instantiate the appropriate game engine. Hooray!",
        "fixed v7 dispatch context",
    )
    switch_matches = [
        idx for idx in range(comment + 1, len(lines))
        if clean(lines[idx]) == "switch (res.game.version) {"
    ]
    if len(switch_matches) != 1:
        raise TransformError(
            "fixed v7 dispatch: expected one version switch after context, "
            f"found {len(switch_matches)}"
        )
    switch_start = switch_matches[0]
    _, switch_end = find_braced_region(
        lines, switch_start, "fixed v7 dispatch"
    )
    conditional_region(
        lines,
        switch_start,
        switch_end,
        [
            "\tif (res.game.id != GID_FT || res.game.version != 7 || res.game.heversion != 0)",
            "\t\treturn Common::kUnsupportedGameidError;",
            "\t*engine = new ScummEngine_v7(syst, res);",
        ],
        "fixed Full Throttle v7 engine dispatch",
    )
    return lines


def transform_scumm(lines: list[str]) -> list[str]:
    lines = list(lines)

    constructor = find_unique_line(
        lines,
        "ScummEngine::ScummEngine(OSystem *syst, const DetectorResult &dr)",
        "fixed GDI constructor",
    )
    open_line, _ = find_braced_region(lines, constructor, "fixed GDI constructor")
    resource_line = find_unique_line(
        lines,
        "_res = new ResourceManager(this);",
        "fixed GDI constructor resource boundary",
        start=open_line + 1,
    )
    if resource_line <= open_line + 1:
        raise TransformError("fixed GDI constructor: invalid generic GDI region")
    conditional_region(
        lines,
        open_line + 1,
        resource_line - 1,
        ["\t_gdi = new Gdi(this);"],
        "fixed GDI constructor",
    )

    guard_unique_line(lines, "delete _debugger;", "guard debugger delete")
    guard_unique_line(
        lines,
        "_debugger = new ScummDebugger(this);",
        "guard debugger creation",
    )

    setup_scumm = find_unique_line(
        lines, "void ScummEngine::setupScumm() {", "fixed setupScumm"
    )
    _, setup_scumm_end = find_braced_region(
        lines, setup_scumm, "fixed setupScumm"
    )
    cd_if_matches = [
        idx for idx in range(setup_scumm + 1, setup_scumm_end)
        if clean(lines[idx]) == "if (_game.features & GF_AUDIOTRACKS) {"
    ]
    if len(cd_if_matches) != 1:
        raise TransformError(
            "guard CD audio setup: expected one GF_AUDIOTRACKS block in setupScumm, "
            f"found {len(cd_if_matches)}"
        )
    cd_start = cd_if_matches[0]
    _, cd_end = find_braced_region(lines, cd_start, "guard CD audio setup")
    guard_region(lines, cd_start, cd_end, "guard CD audio setup")

    # Re-find setupScumm after the insertion.
    setup_scumm = find_unique_line(
        lines, "void ScummEngine::setupScumm() {", "fixed sound manager"
    )
    _, setup_scumm_end = find_braced_region(
        lines, setup_scumm, "fixed sound manager"
    )
    sound_comment = find_unique_line(
        lines,
        "// Create the sound manager",
        "fixed sound manager",
        start=setup_scumm + 1,
        end=setup_scumm_end,
    )
    music_comment = find_unique_line(
        lines,
        "// Setup the music engine",
        "fixed sound manager boundary",
        start=sound_comment + 1,
        end=setup_scumm_end,
    )
    sound_start = sound_comment + 1
    while sound_start < music_comment and clean(lines[sound_start]) == "":
        sound_start += 1
    sound_end = music_comment - 1
    while sound_end >= sound_start and clean(lines[sound_end]) == "":
        sound_end -= 1
    conditional_region(
        lines,
        sound_start,
        sound_end,
        ["\t_sound = new Sound(this, _mixer);"],
        "fixed sound manager",
    )

    conditional_function_body(
        lines,
        "void ScummEngine::setupCharsetRenderer() {",
        ["\t_charset = new CharsetRendererClassic(this);"],
        "fixed charset renderer",
    )
    conditional_function_body(
        lines,
        "void ScummEngine::setupCostumeRenderer() {",
        [
            "\t_costumeRenderer = new AkosRenderer(this);",
            "\t_costumeLoader = new AkosCostumeLoader(this);",
        ],
        "fixed AKOS costume renderer",
    )

    actor_loop = find_unique_line(
        lines,
        "for (i = 0; i < _numActors; ++i) {",
        "fixed actor allocation",
    )
    _, actor_loop_end = find_braced_region(
        lines, actor_loop, "fixed actor allocation"
    )
    actor_start = find_unique_line(
        lines,
        "if (_game.version == 0)",
        "fixed actor allocation first branch",
        start=actor_loop + 1,
        end=actor_loop_end,
    )
    init_actor = find_unique_line(
        lines,
        "_actors[i]->initActor(-1);",
        "fixed actor allocation init boundary",
        start=actor_start + 1,
        end=actor_loop_end,
    )
    conditional_region(
        lines,
        actor_start,
        init_actor - 1,
        ["\t\t_actors[i] = new Actor(this, i);"],
        "fixed actor allocation",
    )

    conditional_function_body(
        lines,
        "void ScummEngine::setupMusic(int midi) {",
        [
            "\t(void)midi;",
            "\t_native_mt32 = false;",
            "\t_enable_gs = false;",
            "\t_sound->_musicType = MDT_NONE;",
        ],
        "disable generic MIDI-era music setup",
    )

    heap_threshold = find_unique_line(
        lines,
        "_res->setHeapThreshold(400000, maxHeapThreshold);",
        "N64 resource cache threshold",
    )
    conditional_region(
        lines,
        heap_threshold,
        heap_threshold,
        ["\t_res->setHeapThreshold(400000, 2 * 1024 * 1024);"],
        "N64 resource cache threshold",
    )

    guard_unique_line(
        lines, "_debugger->onFrame();", "guard debugger frame hook"
    )

    towns_start = find_unique_line(
        lines, "if (_townsPlayer) {", "guard Towns volume hook"
    )
    _, towns_end = find_braced_region(
        lines, towns_start, "guard Towns volume hook"
    )
    guard_region(lines, towns_start, towns_end, "guard Towns volume hook")

    return lines


EXPECTED_MARKERS = {
    "base/main.cpp": [
        "guard EventRecorder include",
        "guard generic music includes",
        "guard YUV manager include",
        "guard launcher includes",
        "guard launcher function",
        "guard music-driver validation",
        "guard global music managers",
        "guard EventRecorder init",
        "guard initial launcher",
        "guard EventRecorder deinit",
        "replace return-to-launcher tail",
        "guard EventRecorder destroy",
        "guard MusicManager destroy",
        "guard YUV manager destroy",
    ],
    "engines/scumm/detection.cpp": [
        "fixed Full Throttle v7 engine dispatch",
    ],
    "engines/scumm/scumm.cpp": [
        "fixed GDI constructor",
        "guard debugger delete",
        "guard debugger creation",
        "guard CD audio setup",
        "fixed sound manager",
        "fixed charset renderer",
        "fixed AKOS costume renderer",
        "fixed actor allocation",
        "disable generic MIDI-era music setup",
        "N64 resource cache threshold",
        "guard debugger frame hook",
        "guard Towns volume hook",
    ],
}


def verify_outputs(outputs: dict[str, list[str]]) -> None:
    errors: list[str] = []
    for rel, labels in EXPECTED_MARKERS.items():
        text = "\n".join(outputs[rel])
        for label in labels:
            marker = f"// FT64 r2v structural: {label}"
            count = text.count(marker)
            if count != 1:
                errors.append(f"{rel}: marker {label!r} count is {count}, expected 1")

    main = "\n".join(outputs["base/main.cpp"])
    detection = "\n".join(outputs["engines/scumm/detection.cpp"])
    scumm = "\n".join(outputs["engines/scumm/scumm.cpp"])

    required = [
        (main, "#ifndef N64_FT_ONLY", "main guard"),
        (main, "GUI::LauncherDialog dlg;", "preserved generic launcher"),
        (
            detection,
            "res.game.id != GID_FT || res.game.version != 7 || res.game.heversion != 0",
            "FT v7 gate",
        ),
        (detection, "*engine = new ScummEngine_v7(syst, res);", "v7 constructor"),
        (scumm, "_gdi = new Gdi(this);", "fixed GDI"),
        (scumm, "_sound = new Sound(this, _mixer);", "fixed Sound"),
        (scumm, "_charset = new CharsetRendererClassic(this);", "fixed charset"),
        (scumm, "_costumeRenderer = new AkosRenderer(this);", "fixed AKOS"),
        (scumm, "_actors[i] = new Actor(this, i);", "fixed actor"),
        (scumm, "_sound->_musicType = MDT_NONE;", "fixed generic music-off"),
        (
            scumm,
            "_res->setHeapThreshold(400000, 2 * 1024 * 1024);",
            "N64 resource cache threshold",
        ),
    ]
    for text, needle, label in required:
        if needle not in text:
            errors.append(f"missing verified result: {label}: {needle}")

    if errors:
        raise TransformError("\n".join(errors))


def build_outputs(root: Path) -> tuple[dict[str, list[str]], dict[str, bool]]:
    paths = {
        "base/main.cpp": root / "base/main.cpp",
        "engines/scumm/detection.cpp": root / "engines/scumm/detection.cpp",
        "engines/scumm/scumm.cpp": root / "engines/scumm/scumm.cpp",
    }
    missing = [str(path) for path in paths.values() if not path.is_file()]
    if missing:
        raise TransformError("missing pinned source files:\n" + "\n".join(missing))

    raw: dict[str, list[str]] = {}
    final_newlines: dict[str, bool] = {}
    for rel, path in paths.items():
        raw[rel], final_newlines[rel] = read_lines(path)

    outputs = {
        "base/main.cpp": transform_main(raw["base/main.cpp"]),
        "engines/scumm/detection.cpp": transform_detection(
            raw["engines/scumm/detection.cpp"]
        ),
        "engines/scumm/scumm.cpp": transform_scumm(
            raw["engines/scumm/scumm.cpp"]
        ),
    }
    verify_outputs(outputs)
    return outputs, final_newlines


def verify_applied(root: Path) -> None:
    outputs: dict[str, list[str]] = {}
    for rel in EXPECTED_MARKERS:
        path = root / rel
        if not path.is_file():
            raise TransformError(f"missing specialized source: {path}")
        outputs[rel] = path.read_text().splitlines()
    verify_outputs(outputs)


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Structurally specialize pinned ScummVM 1.6.0 for the "
            "Full Throttle-only N64 target."
        )
    )
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--apply", action="store_true")
    mode.add_argument("--verify", action="store_true")
    parser.add_argument("scummvm_root", type=Path)
    args = parser.parse_args()

    try:
        if args.verify:
            verify_applied(args.scummvm_root)
            print("[ft-only] verified structural specialization")
            return 0

        outputs, final_newlines = build_outputs(args.scummvm_root)
        if args.check:
            print("[ft-only] structural check passed for all three pinned files")
            return 0

        for rel, lines in outputs.items():
            write_lines(
                args.scummvm_root / rel,
                lines,
                final_newlines[rel],
            )
        verify_applied(args.scummvm_root)
        print("[ft-only] applied and verified structural specialization")
        return 0
    except TransformError as exc:
        print(f"[ft-only] ERROR:\n{exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
