#!/usr/bin/env python3
"""Audit the generated v17 resource.cpp after FT-only specialization."""

from pathlib import Path
import sys


def fail(message: str) -> None:
    print(f"[v17-resource-audit] ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def main() -> int:
    if len(sys.argv) != 2:
        fail("usage: verify_v17_resource.py PATH/TO/resource.cpp")

    path = Path(sys.argv[1])
    if not path.is_file():
        fail(f"missing generated source: {path}")
    text = path.read_text()

    exact_counts = {
        "// FT64 r2v structural: v17 sound 633 transition reclaim": 1,
        "// FT64 r2v structural: v17 reusable large sound arena": 1,
        "// FT64 r2v structural: v17 large sound arena allocation": 1,
        "static byte *ft64LargeSoundArena = NULL;": 1,
        "static uint32 ft64LargeSoundArenaCapacity = 0;": 1,
        "static bool ft64LargeSoundArenaEverUsed = false;": 1,
        "if (!ft64IsLargeSoundArenaAddress(_address))": 2,
        "delete[] ft64LargeSoundArena;": 1,
        "const ResId ft64PreviousSoundId = 622;": 1,
        "nukeResource(rtSound, ft64PreviousSoundId);": 1,
        "uint32 ft64ArenaReserve = 0x1A4000;": 1,
        "ft64LargeSoundArena = new byte[ft64ArenaReserve];": 1,
        "ptr = ft64LargeSoundArena;": 1,
    }
    for token, expected in exact_counts.items():
        actual = text.count(token)
        if actual != expected:
            fail(f"token count for {token!r} is {actual}, expected {expected}")

    required = (
        '"sound-633-stop"',
        '"sound-622-still-in-use"',
        '"sound-622-inactive"',
        '"sound-622-unlock"',
        '"sound-622-evict"',
        "!ft64PreviousInUse && !ft64PreviousSound.isOffHeap()",
        "const bool ft64ArenaEligible = type == rtSound && size >= 512 * 1024;",
        "const bool ft64ArenaCanReuse = ft64ArenaEligible && ft64LargeSoundArena",
        "if (!ft64ArenaCanReuse)",
        '"large-sound-arena-create"',
        '"large-sound-arena-create-failed"',
        '"large-sound-arena-use"',
        '"large-sound-arena-reuse"',
        '"large-sound-arena-reclaim"',
        '"large-sound-arena-busy"',
        '"large-sound-arena-too-small"',
        '"large-sound-heap-fallback"',
        '"large-sound-heap-fallback-failed"',
        "_allocatedSize += size;",
        "_allocatedSize -= _types[type][idx]._size;",
    )
    missing = [token for token in required if token not in text]
    if missing:
        fail("missing required generated tokens:\n  - " + "\n  - ".join(missing))

    forbidden = (
        "FT64 r2v structural: sound 633 transition recovery",
        "FT64 r2v structural: large sound allocation recovery",
        '"large-sound-purge"',
        '"large-sound-retry"',
        "ft64LargeSoundArenaAccounted",
        "_allocatedSize += ft64LargeSoundArenaCapacity",
        "ptr == NULL && type == rtSound",
    )
    found = [token for token in forbidden if token in text]
    if found:
        fail("obsolete generated tokens remain:\n  - " + "\n  - ".join(found))

    definition = text.index("// FT64 r2v structural: v17 reusable large sound arena")
    first_guard = text.index("if (!ft64IsLargeSoundArenaAddress(_address))")
    allocation = text.index("// FT64 r2v structural: v17 large sound arena allocation")
    assignment = text.index("_types[type][idx]._address = ptr;")
    if not definition < first_guard:
        fail("arena helpers are emitted after their first delete guard")
    if not allocation < assignment:
        fail("arena selection is emitted after resource address assignment")

    print(f"[v17-resource-audit] OK: {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
