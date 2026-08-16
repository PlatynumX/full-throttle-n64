#!/usr/bin/env python3
# Audit the generated v18 resource.cpp static large-sound arena.

from pathlib import Path
import sys


def fail(message: str) -> None:
    print(f"[v18-resource-audit] ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def main() -> int:
    if len(sys.argv) != 2:
        fail("usage: verify_v18_resource.py PATH/TO/resource.cpp")

    path = Path(sys.argv[1])
    if not path.is_file():
        fail(f"missing generated source: {path}")
    text = path.read_text()

    exact_counts = {
        "// FT64 r2v structural: v18 sound 633 transition reclaim": 1,
        "// FT64 r2v structural: v18 reusable large sound arena": 1,
        "// FT64 r2v structural: v18 large sound arena allocation": 1,
        "static byte ft64LargeSoundArenaStorage[0x1A4000] __attribute__((aligned(16)));": 1,
        "static byte *const ft64LargeSoundArena = ft64LargeSoundArenaStorage;": 1,
        "static const uint32 ft64LargeSoundArenaCapacity = sizeof(ft64LargeSoundArenaStorage);": 1,
        "static bool ft64LargeSoundArenaEverUsed = false;": 1,
        "if (!ft64IsLargeSoundArenaAddress(_address))": 2,
        "const ResId ft64PreviousSoundId = 622;": 1,
        "nukeResource(rtSound, ft64PreviousSoundId);": 1,
        '::ft64_diag_resource_event("large-sound-arena-static"': 1,
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
        "static byte *ft64LargeSoundArena = NULL;",
        "static uint32 ft64LargeSoundArenaCapacity = 0;",
        "ft64LargeSoundArena = new byte",
        "delete[] ft64LargeSoundArena;",
        "ft64ArenaReserve",
        '"large-sound-arena-create"',
        '"large-sound-arena-create-failed"',
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
        fail("forbidden generated tokens remain:\n  - " + "\n  - ".join(found))

    definition = text.index("// FT64 r2v structural: v18 reusable large sound arena")
    first_guard = text.index("if (!ft64IsLargeSoundArenaAddress(_address))")
    allocation = text.index("// FT64 r2v structural: v18 large sound arena allocation")
    assignment = text.index("_types[type][idx]._address = ptr;")
    storage = text.index("static byte ft64LargeSoundArenaStorage[0x1A4000]")
    if not definition <= storage < first_guard:
        fail("static arena storage is emitted after its first delete guard")
    if not allocation < assignment:
        fail("arena selection is emitted after resource address assignment")

    print(f"[v18-resource-audit] OK: {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
