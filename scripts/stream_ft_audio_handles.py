#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path
import sys

MARK = "FT64 r2aa: no persistent sound archive handles"


class PatchError(RuntimeError):
    pass


def find_unique(lines, target, label, start=0, end=None):
    stop = len(lines) if end is None else end
    hits = [i for i in range(start, stop) if lines[i].strip() == target]
    if len(hits) != 1:
        raise PatchError(
            f"{label}: expected one stripped-line match for {target!r}, "
            f"found {len(hits)} at {[i + 1 for i in hits]}"
        )
    return hits[0]


def find_braced_end(lines, start, label):
    depth = 0
    seen = False
    for i in range(start, len(lines)):
        line = lines[i]
        depth += line.count("{")
        if "{" in line:
            seen = True
        depth -= line.count("}")
        if seen and depth == 0:
            return i + 1
    raise PatchError(f"{label}: could not find balanced closing brace")


def paths(root):
    return (
        root / "engines/scumm/imuse_digi/dimuse_sndmgr.h",
        root / "engines/scumm/imuse_digi/dimuse_sndmgr.cpp",
    )


def check(root):
    hdr, cpp = paths(root)
    if not hdr.is_file() or not cpp.is_file():
        raise PatchError("missing generated iMUSE sound-manager source")

    h = hdr.read_text()
    c = cpp.read_text()

    if MARK in h or MARK in c:
        raise PatchError("r2aa handle patch already present")

    required_h = (
        "ScummFile *streamFile;",
        "uint32 streamCacheValid;",
        "bool streamReadLogged;",
    )
    for token in required_h:
        if h.count(token) != 1:
            raise PatchError(f"header token {token!r}: found {h.count(token)}")

    required_c = (
        "static const uint32 kFT64StreamCacheSize = 32768;",
        "bool ImuseDigiSndMgr::readFTStreamCached",
        "sound->streamFile = ft64Stream;",
        "} else if (soundDesc->streamFile) {",
        '::ft64_diag_resource_event("stream-open"',
    )
    for token in required_c:
        if c.count(token) != 1:
            raise PatchError(f"cpp token {token!r}: found {c.count(token)}")

    if "streamCacheCapacity" in h or "streamCacheCapacity" in c:
        raise PatchError("streamCacheCapacity already present")

    print("[ft-handles-r2aa] check OK")


def apply(root):
    check(root)
    hdr, cpp = paths(root)

    h = hdr.read_text()
    old = "\t\tScummFile *streamFile;\n"
    new = (
        "\t\tScummFile *streamFile;\n"
        f"\t\t// {MARK}: archive identity survives after temporary handle closes\n"
        "\t\tchar streamName[64];\n"
        "\t\tbyte streamEnc;\n"
        "\t\tuint32 streamCacheCapacity;\n"
    )
    if h.count(old) != 1:
        raise PatchError(f"streamFile field anchor count={h.count(old)}")
    h = h.replace(old, new, 1)
    hdr.write_text(h)

    c = cpp.read_text()
    lines = c.splitlines()

    sig = find_unique(
        lines,
        "bool ImuseDigiSndMgr::readFTStreamCached(SoundDesc *sound, uint32 relative, byte *dst, uint32 size) {",
        "readFTStreamCached signature",
    )
    end = find_braced_end(lines, sig, "readFTStreamCached")

    reader = r'''bool ImuseDigiSndMgr::readFTStreamCached(SoundDesc *sound, uint32 relative, byte *dst, uint32 size) {
	if (!sound || !sound->streamCache || !sound->streamName[0] || !sound->streamCacheCapacity)
		return false;
	if (relative > sound->streamSize || size > sound->streamSize - relative)
		return false;

	uint32 left = size;
	while (left > 0) {
		const uint32 cacheEnd = sound->streamCacheStart + sound->streamCacheValid;
		const bool inCache = sound->streamCacheValid > 0 &&
			relative >= sound->streamCacheStart && relative < cacheEnd;

		if (!inCache) {
			sound->streamCacheStart = relative;
			uint32 want = sound->streamSize - relative;
			if (want > sound->streamCacheCapacity)
				want = sound->streamCacheCapacity;

			ScummFile file;
			if (!_vm->openFile(file, Common::String(sound->streamName), true)) {
				::ft64_diag_resource_event("stream-reopen-failed", "sound-stream", (int)rtSound, sound->soundId, sound->streamSize, want, sound->streamCacheCapacity, 0, 0, 0, -1);
				return false;
			}
			file.setEnc(sound->streamEnc);

			const uint32 absolute = sound->streamBase + relative;
			if (absolute < sound->streamBase || !file.seek(absolute, SEEK_SET))
				return false;

			const uint32 got = file.read(sound->streamCache, want);
			if (got != want)
				return false;

			sound->streamCacheValid = got;
			if (!sound->streamReadLogged) {
				sound->streamReadLogged = true;
				::ft64_diag_resource_event("stream-reopen", "sound-stream", (int)rtSound, sound->soundId, sound->streamSize, size, sound->streamCacheCapacity, 0, 0, got, -1);
			}
		}

		const uint32 offsetInCache = relative - sound->streamCacheStart;
		uint32 available = sound->streamCacheValid - offsetInCache;
		if (available > left)
			available = left;
		memcpy(dst, sound->streamCache + offsetInCache, available);
		dst += available;
		relative += available;
		left -= available;
	}
	return true;
}'''.splitlines()

    lines[sig:end] = reader

    start = find_unique(
        lines,
        "sound->streamFile = ft64Stream;",
        "openSound streamFile assignment",
    )
    # The containing openSound() has multiple legitimate `return sound;`
    # statements for different resource paths.  The streamed FT branch is
    # the FIRST return after the unique `sound->streamFile = ft64Stream;`
    # assignment, so select that nearest return and validate the bounded
    # region below before replacing anything.
    ret_candidates = [
        i for i in range(start + 1, min(start + 160, len(lines)))
        if lines[i].strip() == "return sound;"
    ]
    if not ret_candidates:
        raise PatchError("streamed openSound return: no return sound; found after stream assignment")
    ret = ret_candidates[0]

    indent = lines[start][: len(lines[start]) - len(lines[start].lstrip())]
    t = indent

    setup = [
        t + "sound->streamFile = ft64Stream;",
        t + "strncpy(sound->streamName, ft64Stream->getName(), sizeof(sound->streamName) - 1);",
        t + "sound->streamName[sizeof(sound->streamName) - 1] = 0;",
        t + "sound->streamEnc = (_vm->_game.features & GF_USE_KEY) ? 0x69 : 0;",
        t + "sound->streamBase = ft64Base;",
        t + "sound->streamSize = ft64Size;",
        t + "sound->streamTag = ft64Tag;",
        t + "sound->streamCacheCapacity = ft64Size;",
        t + "if (sound->streamCacheCapacity > kFT64StreamCacheSize)",
        t + "\tsound->streamCacheCapacity = kFT64StreamCacheSize;",
        t + "sound->streamCache = new byte[sound->streamCacheCapacity];",
        t + "assert(sound->streamCache);",
        t + "sound->streamCacheStart = 0;",
        t + "sound->streamCacheValid = 0;",
        t + "sound->streamReadLogged = false;",
        t + "prepareSoundFromFTStream(sound);",
        t + "",
        t + "// Prefill from the audio-data boundary while this temporary archive",
        t + "// handle is already open. Small sounds become fully cache-resident.",
        t + "uint32 prefillStart = 0;",
        t + "if (sound->offsetData > 0 && (uint32)sound->offsetData < sound->streamSize)",
        t + "\tprefillStart = (uint32)sound->offsetData;",
        t + "uint32 prefillWant = sound->streamSize - prefillStart;",
        t + "if (prefillWant > sound->streamCacheCapacity)",
        t + "\tprefillWant = sound->streamCacheCapacity;",
        t + "if (prefillWant) {",
        t + "\tconst uint32 absolute = sound->streamBase + prefillStart;",
        t + "\tif (absolute < sound->streamBase || !ft64Stream->seek(absolute, SEEK_SET))",
        t + '\t\terror("FT64 stream: prefill seek failed for sound %d", sound->soundId);',
        t + "\tconst uint32 got = ft64Stream->read(sound->streamCache, prefillWant);",
        t + "\tif (got != prefillWant)",
        t + '\t\terror("FT64 stream: prefill read failed for sound %d", sound->soundId);',
        t + "\tsound->streamCacheStart = prefillStart;",
        t + "\tsound->streamCacheValid = got;",
        t + '\t::ft64_diag_resource_event("stream-prefill", "sound-stream", (int)rtSound, soundId, ft64Size, got, sound->streamCacheCapacity, 0, 0, prefillStart, -1);',
        t + "}",
        t + "",
        t + "// Close the temporary archive handle before returning this sound.",
        t + "delete ft64Stream;",
        t + "sound->streamFile = NULL;",
        t + '::ft64_diag_resource_event("stream-open", "sound-stream", (int)rtSound, soundId, ft64Size, sound->streamCacheCapacity, 0, 0, 0, ft64Tag, -1);',
        t + "return sound;",
    ]

    old_region = "\n".join(lines[start : ret + 1])
    for token in (
        "sound->streamBase = ft64Base;",
        "sound->streamCache = new byte[kFT64StreamCacheSize];",
        "prepareSoundFromFTStream(sound);",
        '"stream-open"',
    ):
        if token not in old_region:
            raise PatchError(f"openSound region missing expected token {token!r}")

    lines[start : ret + 1] = setup

    close_sig = find_unique(
        lines,
        "void ImuseDigiSndMgr::closeSound(SoundDesc *soundDesc) {",
        "closeSound signature",
    )
    compressed = find_unique(
        lines,
        "delete soundDesc->compressedStream;",
        "closeSound compressed delete",
        close_sig + 1,
    )
    if_idx = find_unique(
        lines,
        "if (soundDesc->streamFile) {",
        "closeSound streamFile guard",
        close_sig + 1,
        compressed,
    )
    cache_null = find_unique(
        lines,
        "soundDesc->streamCache = NULL;",
        "closeSound cache clear",
        if_idx + 1,
        compressed,
    )

    ci = lines[if_idx][: len(lines[if_idx]) - len(lines[if_idx].lstrip())]
    cleanup = [
        ci + "if (soundDesc->streamCache && soundDesc->streamName[0])",
        ci + '\t::ft64_diag_resource_event("stream-close", "sound-stream", (int)rtSound, soundDesc->soundId, soundDesc->streamSize, soundDesc->streamCacheCapacity, 0, 0, 0, soundDesc->streamTag, -1);',
        ci + "if (soundDesc->streamFile) {",
        ci + "\tdelete soundDesc->streamFile;",
        ci + "\tsoundDesc->streamFile = NULL;",
        ci + "}",
        ci + "delete[] soundDesc->streamCache;",
        ci + "soundDesc->streamCache = NULL;",
        ci + "soundDesc->streamCacheCapacity = 0;",
        ci + "soundDesc->streamName[0] = 0;",
    ]
    lines[if_idx : cache_null + 1] = cleanup

    branch = find_unique(
        lines,
        "} else if (soundDesc->streamFile) {",
        "stream playback branch",
    )
    leading = lines[branch][: len(lines[branch]) - len(lines[branch].lstrip())]
    lines[branch] = leading + "} else if (soundDesc->streamCache && soundDesc->streamName[0]) {"

    marker_anchor = find_unique(
        lines,
        "// FT64 r2v structural: v20 universal FT audio streaming: buffered payload reader",
        "generated stream marker",
    )
    lines.insert(marker_anchor + 1, "// " + MARK)

    cpp.write_text("\n".join(lines) + "\n")
    print("[ft-handles-r2aa] applied")


def verify(root):
    hdr, cpp = paths(root)
    h = hdr.read_text()
    c = cpp.read_text()
    all_text = h + "\n" + c

    required = (
        MARK,
        "char streamName[64];",
        "byte streamEnc;",
        "uint32 streamCacheCapacity;",
        "ScummFile file;",
        "Common::String(sound->streamName)",
        '"stream-prefill"',
        '"stream-reopen"',
        '"stream-reopen-failed"',
        "delete ft64Stream;",
        "sound->streamFile = NULL;",
        "} else if (soundDesc->streamCache && soundDesc->streamName[0]) {",
    )
    for token in required:
        if token not in all_text:
            raise PatchError(f"verify missing token: {token}")

    forbidden = (
        "sound->streamCache = new byte[kFT64StreamCacheSize];",
        "} else if (soundDesc->streamFile) {",
    )
    for token in forbidden:
        if token in c:
            raise PatchError(f"verify forbidden old behavior remains: {token}")

    open_pos = c.index("sound->streamFile = ft64Stream;")
    delete_pos = c.index("delete ft64Stream;", open_pos)
    null_pos = c.index("sound->streamFile = NULL;", delete_pos)
    return_pos = c.index("return sound;", null_pos)
    if not open_pos < delete_pos < null_pos < return_pos:
        raise PatchError("temporary archive handle is not closed before openSound returns")

    print("[ft-handles-r2aa] verified")


def main():
    ap = argparse.ArgumentParser()
    mode = ap.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--apply", action="store_true")
    mode.add_argument("--verify", action="store_true")
    ap.add_argument("root")
    ns = ap.parse_args()

    try:
        root = Path(ns.root)
        if ns.check:
            check(root)
        elif ns.apply:
            apply(root)
        else:
            verify(root)
    except PatchError as exc:
        print(f"[ft-handles-r2aa] ERROR: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
