#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path
import sys


MARK = "FT64 r2v structural: v19 large iMUS streaming"


class PatchError(RuntimeError):
    pass


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise PatchError(f"{label}: expected one match, found {count}")
    return text.replace(old, new, 1)


def find_unique_stripped(lines, target: str, label: str, start: int = 0, end=None) -> int:
    limit = len(lines) if end is None else end
    hits = [i for i in range(start, limit) if lines[i].strip() == target]
    if len(hits) != 1:
        raise PatchError(f"{label}: expected one stripped-line match for {target!r}, "
                         f"found {len(hits)} at {[i + 1 for i in hits]}")
    return hits[0]


def replace_line_region(text: str, start: int, end: int, replacement: str) -> str:
    had_final_newline = text.endswith("\n")
    lines = text.splitlines()
    lines[start:end] = replacement.splitlines()
    out = "\n".join(lines)
    if had_final_newline:
        out += "\n"
    return out


def locate_imuse_resource_case(text: str):
    lines = text.splitlines()
    sig = find_unique_stripped(
        lines,
        "ImuseDigiSndMgr::SoundDesc *ImuseDigiSndMgr::openSound(int32 soundId, const char *soundName, int soundType, int volGroupId, int disk) {",
        "openSound signature",
    )
    case = find_unique_stripped(lines, "case IMUSE_RESOURCE:", "IMUSE_RESOURCE case", sig + 1)
    next_case = find_unique_stripped(lines, "case IMUSE_BUNDLE:", "IMUSE_RESOURCE boundary", case + 1)
    block = [line.strip() for line in lines[case:next_case]]

    for token in [
        "_vm->ensureResourceLoaded(rtSound, soundId);",
        "_vm->_res->lock(rtSound, soundId);",
        "ptr = _vm->getResourceAddress(rtSound, soundId);",
        "if (ptr == NULL) {",
        "closeSound(sound);",
        "return NULL;",
        "sound->resPtr = ptr;",
        "break;",
    ]:
        if block.count(token) != 1:
            raise PatchError(
                f"IMUSE_RESOURCE structural token {token!r}: "
                f"expected one in case, found {block.count(token)}"
            )

    assert_hits = [line for line in block if line.startswith("assert(soundName[0] == 0);")]
    if len(assert_hits) != 1:
        raise PatchError(
            f"IMUSE_RESOURCE paranoia assertion: expected one, found {len(assert_hits)}"
        )
    return case, next_case


def locate_close_sound_delete(text: str):
    lines = text.splitlines()
    start = find_unique_stripped(
        lines,
        "void ImuseDigiSndMgr::closeSound(SoundDesc *soundDesc) {",
        "closeSound signature",
    )
    end = find_unique_stripped(
        lines,
        "ImuseDigiSndMgr::SoundDesc *ImuseDigiSndMgr::cloneSound(SoundDesc *soundDesc) {",
        "closeSound boundary",
        start + 1,
    )
    delete_idx = find_unique_stripped(
        lines,
        "delete soundDesc->compressedStream;",
        "closeSound compressed stream delete",
        start + 1,
        end,
    )
    return delete_idx


def locate_resptr_branch(text: str):
    lines = text.splitlines()
    sig = find_unique_stripped(
        lines,
        "int32 ImuseDigiSndMgr::getDataFromRegion(SoundDesc *soundDesc, int region, byte **buf, int32 offset, int32 size) {",
        "getDataFromRegion signature",
    )
    branch = find_unique_stripped(
        lines,
        "} else if (soundDesc->resPtr) {",
        "resource-backed data branch",
        sig + 1,
    )
    next_branch = find_unique_stripped(
        lines,
        "} else if ((soundDesc->bundle) && (soundDesc->compressed)) {",
        "resource-backed data boundary",
        branch + 1,
    )
    block = [line.strip() for line in lines[branch:next_branch]]
    for token in [
        "*buf = (byte *)malloc(size);",
        "assert(*buf);",
        "memcpy(*buf, soundDesc->resPtr + start + offset + header_size, size);",
    ]:
        if block.count(token) != 1:
            raise PatchError(
                f"resource data structural token {token!r}: "
                f"expected one, found {block.count(token)}"
            )
    return branch, next_branch


def paths(root: Path):
    return (
        root / "engines/scumm/scumm.h",
        root / "engines/scumm/sound.cpp",
        root / "engines/scumm/imuse_digi/dimuse_sndmgr.h",
        root / "engines/scumm/imuse_digi/dimuse_sndmgr.cpp",
    )


def check_pristine(root: Path) -> None:
    scumm_h, sound_cpp, snd_h, snd_cpp = paths(root)
    for p in (scumm_h, sound_cpp, snd_h, snd_cpp):
        if not p.is_file():
            raise PatchError(f"missing pinned source file: {p}")
        if MARK in p.read_text():
            raise PatchError(f"streaming patch already present in {p}")

    s = scumm_h.read_text()
    required = [
        "class BaseScummFile;",
        "bool openFile(BaseScummFile &file, const Common::String &filename, bool resourceFile = false);",
    ]
    for token in required:
        if s.count(token) != 1:
            raise PatchError(f"scumm.h anchor count for {token!r}: {s.count(token)}")

    s = sound_cpp.read_text()
    if s.count("int ScummEngine::readSoundResource(ResId idx) {") != 1:
        raise PatchError("sound.cpp readSoundResource anchor changed")

    s = snd_h.read_text()
    for token in [
        "class ScummEngine;",
        "\t\tbyte *resPtr;",
        "\tvoid prepareSound(byte *ptr, SoundDesc *sound);",
    ]:
        if s.count(token) != 1:
            raise PatchError(f"dimuse_sndmgr.h anchor count for {token!r}: {s.count(token)}")

    s = snd_cpp.read_text()
    lines = s.splitlines()
    for token, label in [
        ('#include "scumm/resource.h"', "resource include"),
        ("ImuseDigiSndMgr::SoundDesc *ImuseDigiSndMgr::openSound(int32 soundId, const char *soundName, int soundType, int volGroupId, int disk) {", "openSound"),
    ]:
        find_unique_stripped(lines, token, label)

    locate_close_sound_delete(s)
    locate_imuse_resource_case(s)
    locate_resptr_branch(s)


def apply(root: Path) -> None:
    check_pristine(root)
    scumm_h, sound_cpp, snd_h, snd_cpp = paths(root)

    s = scumm_h.read_text()
    s = replace_once(
        s,
        "class BaseScummFile;\n",
        "class BaseScummFile;\n"
        "#ifdef N64_FT_ONLY\n"
        f"// {MARK}: independent resource stream type\n"
        "class ScummFile;\n"
        "#endif\n",
        "scumm.h forward declaration",
    )
    s = replace_once(
        s,
        "\tbool openFile(BaseScummFile &file, const Common::String &filename, bool resourceFile = false);\n",
        "\tbool openFile(BaseScummFile &file, const Common::String &filename, bool resourceFile = false);\n"
        "#ifdef N64_FT_ONLY\n"
        f"\t// {MARK}: locate/open a large FT iMUS resource without ResourceManager allocation\n"
        "\tbool openFTLargeSoundStream(ResId idx, ScummFile &file, uint32 &resourceOffset, uint32 &resourceSize);\n"
        "#endif\n",
        "scumm.h public streaming helper",
    )
    scumm_h.write_text(s)

    helper = r'''
#ifdef N64_FT_ONLY
// FT64 r2v structural: v19 large iMUS streaming: resource-file locator
bool ScummEngine::openFTLargeSoundStream(ResId idx, ScummFile &file, uint32 &resourceOffset, uint32 &resourceSize) {
	if (_game.id != GID_FT || _game.version != 7)
		return false;

	int roomNr = getResourceRoomNr(rtSound, idx);
	if (roomNr == 0)
		roomNr = _roomResource;

	const uint32 fileOffs = getResourceRoomOffset(rtSound, idx);
	if (fileOffs == RES_INVALID_OFFSET)
		return false;

	openRoom(roomNr);
	const uint32 outerOffset = fileOffs + _fileOffset;
	if (outerOffset < fileOffs)
		return false;
	if (!_fileHandle->seek(outerOffset, SEEK_SET))
		return false;

	_fileHandle->readUint32LE();
	_fileHandle->readUint32BE();
	const uint32 baseTag = _fileHandle->readUint32BE();
	const uint32 totalSize = _fileHandle->readUint32BE();

	if (_fileHandle->err() || _fileHandle->eos())
		return false;
	if (baseTag != MKTAG('i','M','U','S'))
		return false;

	const uint32 fullSize = totalSize + 8;
	if (fullSize < totalSize || fullSize < 512 * 1024)
		return false;

	resourceOffset = outerOffset + 8;
	resourceSize = fullSize;
	if (resourceOffset < outerOffset)
		return false;

	Common::String filename(generateFilename(roomNr));
	if (!openFile(file, filename, true))
		return false;

	byte encByte = 0;
	if (_game.features & GF_USE_KEY) {
		if (_game.version <= 3)
			encByte = 0xFF;
		else if ((_game.version == 4) && (roomNr == 0 || roomNr >= 900))
			encByte = 0;
		else
			encByte = 0x69;
	}
	file.setEnc(encByte);

	const int32 fileSize = file.size();
	if (fileSize < 0 || resourceOffset > (uint32)fileSize ||
			resourceSize > (uint32)fileSize - resourceOffset)
		return false;
	if (!file.seek(resourceOffset, SEEK_SET))
		return false;
	if (file.readUint32BE() != MKTAG('i','M','U','S'))
		return false;
	return file.seek(resourceOffset, SEEK_SET);
}
#endif

'''
    s = sound_cpp.read_text()
    s = replace_once(
        s,
        "int ScummEngine::readSoundResource(ResId idx) {",
        helper + "int ScummEngine::readSoundResource(ResId idx) {",
        "sound.cpp streaming helper insertion",
    )
    sound_cpp.write_text(s)

    s = snd_h.read_text()
    s = replace_once(
        s,
        "class ScummEngine;\n",
        "class ScummEngine;\n"
        "#ifdef N64_FT_ONLY\n"
        f"// {MARK}: forward declaration\n"
        "class ScummFile;\n"
        "#endif\n",
        "sndmgr.h ScummFile forward declaration",
    )
    s = replace_once(
        s,
        "\t\tbyte *resPtr;\n",
        "\t\tbyte *resPtr;\n"
        "#ifdef N64_FT_ONLY\n"
        f"\t\t// {MARK}: independent file-backed payload\n"
        "\t\tScummFile *streamFile;\n"
        "\t\tuint32 streamBase;\n"
        "\t\tuint32 streamSize;\n"
        "#endif\n",
        "sndmgr.h SoundDesc streaming fields",
    )
    s = replace_once(
        s,
        "\tvoid prepareSound(byte *ptr, SoundDesc *sound);\n",
        "\tvoid prepareSound(byte *ptr, SoundDesc *sound);\n"
        "#ifdef N64_FT_ONLY\n"
        f"\t// {MARK}: parse iMUS metadata while leaving DATA on disk\n"
        "\tvoid prepareSoundFromFTStream(SoundDesc *sound);\n"
        "#endif\n",
        "sndmgr.h streaming parser declaration",
    )
    snd_h.write_text(s)

    s = snd_cpp.read_text()
    s = replace_once(
        s,
        '#include "scumm/resource.h"\n',
        '#include "scumm/resource.h"\n'
        '#ifdef N64_FT_ONLY\n'
        f'// {MARK}: file-backed iMUS payload\n'
        '#include "scumm/file.h"\n'
        'extern void ft64_diag_resource_event(const char *phase, const char *typeName, int typeId, int resourceId, uint32 resourceSize, uint32 allocationSize, uint32 cacheAllocated, uint32 minThreshold, uint32 maxThreshold, uint32 victimSize, int victimCounter);\n'
        '#endif\n',
        "sndmgr.cpp include/diagnostic bridge",
    )

    parser = r'''
#ifdef N64_FT_ONLY
// FT64 r2v structural: v19 large iMUS streaming: metadata-only parser
void ImuseDigiSndMgr::prepareSoundFromFTStream(SoundDesc *sound) {
	ScummFile *file = sound->streamFile;
	if (!file)
		error("FT64 stream: missing file for sound %d", sound->soundId);

	const uint32 base = sound->streamBase;
	const uint32 streamSize = sound->streamSize;
	const uint32 limit = base + streamSize;
	if (limit < base || streamSize < 24)
		error("FT64 stream: invalid resource bounds for sound %d", sound->soundId);

	if (!file->seek(base, SEEK_SET) || file->readUint32BE() != MKTAG('i','M','U','S'))
		error("FT64 stream: missing iMUS header for sound %d", sound->soundId);
	if (!file->seek(base + 16, SEEK_SET))
		error("FT64 stream: cannot seek metadata for sound %d", sound->soundId);

	int numRegions = 0;
	int numJumps = 0;
	int numSyncs = 0;
	int numMarkers = 0;
	bool foundData = false;

	while (!foundData) {
		const int32 rawPos = file->pos();
		if (rawPos < 0 || (uint32)rawPos > limit || limit - (uint32)rawPos < 8)
			error("FT64 stream: truncated metadata for sound %d", sound->soundId);

		const uint32 tag = file->readUint32BE();
		const uint32 chunkSize = file->readUint32BE();
		const uint32 payload = (uint32)file->pos();
		if (payload > limit || chunkSize > limit - payload)
			error("FT64 stream: chunk outside resource for sound %d", sound->soundId);

		switch (tag) {
		case MKTAG('F','R','M','T'):
		case MKTAG('S','T','O','P'):
			break;
		case MKTAG('R','E','G','N'):
			++numRegions;
			break;
		case MKTAG('J','U','M','P'):
			++numJumps;
			break;
		case MKTAG('S','Y','N','C'):
			++numSyncs;
			break;
		case MKTAG('T','E','X','T'): {
			if (chunkSize >= 8) {
				if (!file->seek(payload + 4, SEEK_SET))
					error("FT64 stream: marker seek failed for sound %d", sound->soundId);
				char markerName[5] = { 0, 0, 0, 0, 0 };
				uint32 chars = chunkSize - 4;
				if (chars > 4)
					chars = 4;
				if (file->read(markerName, chars) != chars)
					error("FT64 stream: marker read failed for sound %d", sound->soundId);
				if (!scumm_stricmp(markerName, "exit"))
					++numMarkers;
			}
			break;
		}
		case MKTAG('D','A','T','A'):
			foundData = true;
			break;
		default:
			error("FT64 stream: unknown iMUS header '%s' for sound %d", tag2str(tag), sound->soundId);
		}

		if (!foundData && !file->seek(payload + chunkSize, SEEK_SET))
			error("FT64 stream: chunk seek failed for sound %d", sound->soundId);
	}

	sound->numRegions = numRegions;
	sound->numJumps = numJumps;
	sound->numSyncs = numSyncs;
	sound->numMarkers = numMarkers;
	sound->region = new Region[numRegions];
	sound->jump = new Jump[numJumps];
	sound->sync = new Sync[numSyncs];
	sound->marker = new Marker[numMarkers];
	assert(sound->region);
	assert(sound->jump);
	assert(sound->sync);
	assert(sound->marker);

	if (!file->seek(base + 16, SEEK_SET))
		error("FT64 stream: second metadata seek failed for sound %d", sound->soundId);

	int curRegion = 0;
	int curJump = 0;
	int curSync = 0;
	int curMarker = 0;
	foundData = false;

	while (!foundData) {
		const int32 rawPos = file->pos();
		if (rawPos < 0 || (uint32)rawPos > limit || limit - (uint32)rawPos < 8)
			error("FT64 stream: truncated second pass for sound %d", sound->soundId);

		const uint32 tag = file->readUint32BE();
		const uint32 chunkSize = file->readUint32BE();
		const uint32 payload = (uint32)file->pos();
		if (payload > limit || chunkSize > limit - payload)
			error("FT64 stream: second-pass chunk outside resource for sound %d", sound->soundId);

		switch (tag) {
		case MKTAG('F','R','M','T'):
			if (chunkSize < 20)
				error("FT64 stream: short FRMT for sound %d", sound->soundId);
			if (!file->seek(payload + 8, SEEK_SET))
				error("FT64 stream: FRMT seek failed for sound %d", sound->soundId);
			sound->bits = file->readUint32BE();
			sound->freq = file->readUint32BE();
			sound->channels = file->readUint32BE();
			break;

		case MKTAG('T','E','X','T'):
			if (chunkSize >= 8) {
				if (!file->seek(payload, SEEK_SET))
					error("FT64 stream: TEXT seek failed for sound %d", sound->soundId);
				const uint32 markerPos = file->readUint32BE();
				char markerName[5] = { 0, 0, 0, 0, 0 };
				uint32 chars = chunkSize - 4;
				if (chars > 4)
					chars = 4;
				if (file->read(markerName, chars) != chars)
					error("FT64 stream: TEXT read failed for sound %d", sound->soundId);
				if (!scumm_stricmp(markerName, "exit")) {
					if (curMarker >= numMarkers)
						error("FT64 stream: marker count overflow for sound %d", sound->soundId);
					sound->marker[curMarker].pos = markerPos;
					sound->marker[curMarker].length = 5;
					sound->marker[curMarker].ptr = new char[5];
					assert(sound->marker[curMarker].ptr);
					strcpy(sound->marker[curMarker].ptr, "exit");
					++curMarker;
				}
			}
			break;

		case MKTAG('S','T','O','P'):
			break;

		case MKTAG('R','E','G','N'):
			if (chunkSize < 8 || curRegion >= numRegions)
				error("FT64 stream: malformed REGN for sound %d", sound->soundId);
			if (!file->seek(payload, SEEK_SET))
				error("FT64 stream: REGN seek failed for sound %d", sound->soundId);
			sound->region[curRegion].offset = file->readUint32BE();
			sound->region[curRegion].length = file->readUint32BE();
			++curRegion;
			break;

		case MKTAG('J','U','M','P'):
			if (chunkSize < 16 || curJump >= numJumps)
				error("FT64 stream: malformed JUMP for sound %d", sound->soundId);
			if (!file->seek(payload, SEEK_SET))
				error("FT64 stream: JUMP seek failed for sound %d", sound->soundId);
			sound->jump[curJump].offset = file->readUint32BE();
			sound->jump[curJump].dest = file->readUint32BE();
			sound->jump[curJump].hookId = (byte)file->readUint32BE();
			sound->jump[curJump].fadeDelay = (int16)file->readUint32BE();
			++curJump;
			break;

		case MKTAG('S','Y','N','C'):
			if (curSync >= numSyncs)
				error("FT64 stream: sync count overflow for sound %d", sound->soundId);
			sound->sync[curSync].size = chunkSize;
			sound->sync[curSync].ptr = new byte[chunkSize];
			assert(sound->sync[curSync].ptr);
			if (chunkSize && file->read(sound->sync[curSync].ptr, chunkSize) != chunkSize)
				error("FT64 stream: SYNC read failed for sound %d", sound->soundId);
			++curSync;
			break;

		case MKTAG('D','A','T','A'):
			sound->offsetData = payload - base;
			foundData = true;
			break;

		default:
			error("FT64 stream: unknown second-pass header '%s' for sound %d", tag2str(tag), sound->soundId);
		}

		if (!foundData && !file->seek(payload + chunkSize, SEEK_SET))
			error("FT64 stream: second-pass seek failed for sound %d", sound->soundId);
	}

	if (curRegion != numRegions || curJump != numJumps ||
			curSync != numSyncs || curMarker != numMarkers)
		error("FT64 stream: metadata count mismatch for sound %d", sound->soundId);
}
#endif

'''
    s = replace_once(
        s,
        "ImuseDigiSndMgr::SoundDesc *ImuseDigiSndMgr::openSound(int32 soundId, const char *soundName, int soundType, int volGroupId, int disk) {",
        parser + "ImuseDigiSndMgr::SoundDesc *ImuseDigiSndMgr::openSound(int32 soundId, const char *soundName, int soundType, int volGroupId, int disk) {",
        "sndmgr.cpp stream parser insertion",
    )

    new_case = r'''	case IMUSE_RESOURCE:
		assert(soundName[0] == 0);	// Paranoia check
#ifdef N64_FT_ONLY
		// FT64 r2v structural: v19 large iMUS streaming: bypass whole-resource allocation.
		if (_vm->_game.id == GID_FT) {
			ScummFile *ft64Stream = new ScummFile();
			assert(ft64Stream);
			uint32 ft64Base = 0;
			uint32 ft64Size = 0;
			if (_vm->openFTLargeSoundStream(soundId, *ft64Stream, ft64Base, ft64Size)) {
				strcpy(sound->name, soundName);
				sound->soundId = soundId;
				sound->type = soundType;
				sound->volGroupId = volGroupId;
				sound->disk = _disk;
				sound->streamFile = ft64Stream;
				sound->streamBase = ft64Base;
				sound->streamSize = ft64Size;
				prepareSoundFromFTStream(sound);
				::ft64_diag_resource_event("stream-open", "sound", (int)rtSound, soundId,
					ft64Size, 0, 0, 0, 0, 0, -1);
				return sound;
			}
			delete ft64Stream;
		}
#endif
		_vm->ensureResourceLoaded(rtSound, soundId);
		_vm->_res->lock(rtSound, soundId);
		ptr = _vm->getResourceAddress(rtSound, soundId);
		if (ptr == NULL) {
			closeSound(sound);
			return NULL;
		}
		sound->resPtr = ptr;
		break;'''
    ft64_case_start, ft64_case_end = locate_imuse_resource_case(s)
    s = replace_line_region(s, ft64_case_start, ft64_case_end, new_case)

    ft64_close_idx = locate_close_sound_delete(s)
    ft64_close_replacement = (
        "#ifdef N64_FT_ONLY\n"
        f"\t// {MARK}: close independent payload file\n"
        "\tif (soundDesc->streamFile) {\n"
        "\t\t::ft64_diag_resource_event(\"stream-close\", \"sound\", (int)rtSound, soundDesc->soundId,\n"
        "\t\t\tsoundDesc->streamSize, 0, 0, 0, 0, 0, -1);\n"
        "\t\tdelete soundDesc->streamFile;\n"
        "\t\tsoundDesc->streamFile = NULL;\n"
        "\t}\n"
        "#endif\n"
        "\tdelete soundDesc->compressedStream;"
    )
    s = replace_line_region(s, ft64_close_idx, ft64_close_idx + 1, ft64_close_replacement)

    new_read = r'''#ifdef N64_FT_ONLY
	} else if (soundDesc->streamFile) {
		// FT64 r2v structural: v19 large iMUS streaming: callback-sized DATA read.
		*buf = (byte *)malloc(size);
		assert(*buf);
		const int32 relative = start + offset + header_size;
		if (relative < 0 || (uint32)relative > soundDesc->streamSize ||
				(uint32)size > soundDesc->streamSize - (uint32)relative)
			error("FT64 stream: region read outside sound %d", soundDesc->soundId);
		const uint32 absolute = soundDesc->streamBase + (uint32)relative;
		if (absolute < soundDesc->streamBase ||
				!soundDesc->streamFile->seek(absolute, SEEK_SET))
			error("FT64 stream: region seek failed for sound %d", soundDesc->soundId);
		if (size && soundDesc->streamFile->read(*buf, size) != (uint32)size)
			error("FT64 stream: short region read for sound %d", soundDesc->soundId);
#endif
	} else if (soundDesc->resPtr) {
		*buf = (byte *)malloc(size);
		assert(*buf);
		memcpy(*buf, soundDesc->resPtr + start + offset + header_size, size);'''
    ft64_read_start, ft64_read_end = locate_resptr_branch(s)
    s = replace_line_region(s, ft64_read_start, ft64_read_end, new_read)
    snd_cpp.write_text(s)


def verify(root: Path) -> None:
    scumm_h, sound_cpp, snd_h, snd_cpp = paths(root)
    texts = {p: p.read_text() for p in (scumm_h, sound_cpp, snd_h, snd_cpp)}

    required = {
        scumm_h: [
            "class ScummFile;",
            "bool openFTLargeSoundStream(ResId idx, ScummFile &file, uint32 &resourceOffset, uint32 &resourceSize);",
        ],
        sound_cpp: [
            "bool ScummEngine::openFTLargeSoundStream(ResId idx, ScummFile &file, uint32 &resourceOffset, uint32 &resourceSize) {",
            "fullSize < 512 * 1024",
            "resourceOffset = outerOffset + 8;",
        ],
        snd_h: [
            "ScummFile *streamFile;",
            "uint32 streamBase;",
            "uint32 streamSize;",
            "void prepareSoundFromFTStream(SoundDesc *sound);",
        ],
        snd_cpp: [
            "void ImuseDigiSndMgr::prepareSoundFromFTStream(SoundDesc *sound) {",
            '::ft64_diag_resource_event("stream-open"',
            '::ft64_diag_resource_event("stream-close"',
            "if (_vm->openFTLargeSoundStream(soundId, *ft64Stream, ft64Base, ft64Size))",
            "} else if (soundDesc->streamFile) {",
            "soundDesc->streamFile->read(*buf, size)",
        ],
    }
    for p, tokens in required.items():
        for token in tokens:
            if token not in texts[p]:
                raise PatchError(f"verify missing {token!r} in {p}")

    all_text = "\n".join(texts.values())
    if all_text.count(MARK) < 6:
        raise PatchError("too few v19 streaming structural markers")

    s = texts[snd_cpp]
    stream_pos = s.index("openFTLargeSoundStream(soundId")
    fallback_pos = s.index("_vm->ensureResourceLoaded(rtSound, soundId);", stream_pos)
    if stream_pos >= fallback_pos:
        raise PatchError("streaming branch is not before whole-resource fallback")

    if "ft64LargeSoundArena" in all_text or "large-sound-arena" in all_text:
        raise PatchError("arena code leaked into v19 stream-touched sources")


def main() -> int:
    ap = argparse.ArgumentParser()
    mode = ap.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--apply", action="store_true")
    mode.add_argument("--verify", action="store_true")
    ap.add_argument("root")
    ns = ap.parse_args()
    root = Path(ns.root)

    try:
        if ns.check:
            check_pristine(root)
            print("[ft-stream] check OK")
        elif ns.apply:
            apply(root)
            print("[ft-stream] applied")
        else:
            verify(root)
            print("[ft-stream] verified")
    except PatchError as exc:
        print(f"[ft-stream] ERROR: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
