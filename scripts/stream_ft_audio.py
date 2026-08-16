#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path
import sys

MARK = "FT64 r2v structural: v20 universal FT audio streaming"


class PatchError(RuntimeError):
    pass


def lines_of(text: str):
    return text.splitlines()


def find_unique(lines, target: str, label: str, start: int = 0, end=None) -> int:
    stop = len(lines) if end is None else end
    hits = [i for i in range(start, stop) if lines[i].strip() == target]
    if len(hits) != 1:
        raise PatchError(
            f"{label}: expected one stripped-line match for {target!r}, "
            f"found {len(hits)} at {[i + 1 for i in hits]}"
        )
    return hits[0]


def replace_region(text: str, start: int, end: int, replacement: str) -> str:
    final_nl = text.endswith("\n")
    lines = text.splitlines()
    lines[start:end] = replacement.splitlines()
    out = "\n".join(lines)
    if final_nl:
        out += "\n"
    return out


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise PatchError(f"{label}: expected one match, found {count}")
    return text.replace(old, new, 1)


def paths(root: Path):
    return (
        root / "engines/scumm/scumm.h",
        root / "engines/scumm/sound.cpp",
        root / "engines/scumm/imuse_digi/dimuse_sndmgr.h",
        root / "engines/scumm/imuse_digi/dimuse_sndmgr.cpp",
    )


def locate_imuse_case(text: str):
    lines = lines_of(text)
    sig = find_unique(
        lines,
        "ImuseDigiSndMgr::SoundDesc *ImuseDigiSndMgr::openSound(int32 soundId, const char *soundName, int soundType, int volGroupId, int disk) {",
        "openSound signature",
    )
    case = find_unique(lines, "case IMUSE_RESOURCE:", "IMUSE_RESOURCE case", sig + 1)
    boundary = find_unique(lines, "case IMUSE_BUNDLE:", "IMUSE_RESOURCE boundary", case + 1)
    block = [line.strip() for line in lines[case:boundary]]
    for token in (
        "_vm->ensureResourceLoaded(rtSound, soundId);",
        "_vm->_res->lock(rtSound, soundId);",
        "ptr = _vm->getResourceAddress(rtSound, soundId);",
        "sound->resPtr = ptr;",
        "break;",
    ):
        if block.count(token) != 1:
            raise PatchError(
                f"IMUSE_RESOURCE token {token!r}: expected one, found {block.count(token)}"
            )
    return case, boundary


def locate_close_delete(text: str):
    lines = lines_of(text)
    start = find_unique(
        lines,
        "void ImuseDigiSndMgr::closeSound(SoundDesc *soundDesc) {",
        "closeSound signature",
    )
    end = find_unique(
        lines,
        "ImuseDigiSndMgr::SoundDesc *ImuseDigiSndMgr::cloneSound(SoundDesc *soundDesc) {",
        "closeSound boundary",
        start + 1,
    )
    return find_unique(
        lines,
        "delete soundDesc->compressedStream;",
        "closeSound compressed stream delete",
        start + 1,
        end,
    )


def locate_resptr_branch(text: str):
    lines = lines_of(text)
    sig = find_unique(
        lines,
        "int32 ImuseDigiSndMgr::getDataFromRegion(SoundDesc *soundDesc, int region, byte **buf, int32 offset, int32 size) {",
        "getDataFromRegion signature",
    )
    start = find_unique(
        lines,
        "} else if (soundDesc->resPtr) {",
        "resident resource branch",
        sig + 1,
    )
    end = find_unique(
        lines,
        "} else if ((soundDesc->bundle) && (soundDesc->compressed)) {",
        "resident resource branch boundary",
        start + 1,
    )
    return start, end


def check_pristine(root: Path):
    scumm_h, sound_cpp, snd_h, snd_cpp = paths(root)
    for p in (scumm_h, sound_cpp, snd_h, snd_cpp):
        if not p.is_file():
            raise PatchError(f"missing pinned source file: {p}")
        if MARK in p.read_text():
            raise PatchError(f"v20 streaming patch already present: {p}")

    s = scumm_h.read_text()
    for token in (
        "class BaseScummFile;",
        "bool openFile(BaseScummFile &file, const Common::String &filename, bool resourceFile = false);",
    ):
        if s.count(token) != 1:
            raise PatchError(f"scumm.h anchor count for {token!r}: {s.count(token)}")

    s = sound_cpp.read_text()
    lines = lines_of(s)
    find_unique(lines, "int ScummEngine::readSoundResource(ResId idx) {", "readSoundResource")
    find_unique(lines, "void Sound::addSoundToQueue(int sound, int heOffset, int heChannel, int heFlags) {", "addSoundToQueue")
    find_unique(lines, "_vm->ensureResourceLoaded(rtSound, sound);", "addSoundToQueue preload")

    s = snd_h.read_text()
    for token in (
        "class ScummEngine;",
        "byte *resPtr;",
        "void prepareSound(byte *ptr, SoundDesc *sound);",
    ):
        if sum(1 for line in s.splitlines() if line.strip() == token) != 1:
            raise PatchError(f"dimuse_sndmgr.h anchor count for {token!r} changed")

    s = snd_cpp.read_text()
    lines = lines_of(s)
    find_unique(lines, '#include "scumm/resource.h"', "resource include")
    locate_imuse_case(s)
    locate_close_delete(s)
    locate_resptr_branch(s)


def apply(root: Path):
    check_pristine(root)
    scumm_h, sound_cpp, snd_h, snd_cpp = paths(root)

    s = scumm_h.read_text()
    s = replace_once(
        s,
        "class BaseScummFile;\n",
        "class BaseScummFile;\n"
        "#ifdef N64_FT_ONLY\n"
        f"// {MARK}: independent stream handle\n"
        "class ScummFile;\n"
        "#endif\n",
        "ScummFile forward declaration",
    )
    s = replace_once(
        s,
        "\tbool openFile(BaseScummFile &file, const Common::String &filename, bool resourceFile = false);\n",
        "\tbool openFile(BaseScummFile &file, const Common::String &filename, bool resourceFile = false);\n"
        "#ifdef N64_FT_ONLY\n"
        f"\t// {MARK}: locate exact FT sound payload selected by openRoom\n"
        "\tbool openFTSoundStream(ResId idx, ScummFile &file, uint32 &resourceOffset, uint32 &resourceSize, uint32 &resourceTag);\n"
        "#endif\n",
        "stream helper declaration",
    )
    scumm_h.write_text(s)

    locator = r'''
#ifdef N64_FT_ONLY
// FT64 r2v structural: v20 universal FT audio streaming: exact resource locator
bool ScummEngine::openFTSoundStream(ResId idx, ScummFile &file, uint32 &resourceOffset, uint32 &resourceSize, uint32 &resourceTag) {
	if (_game.id != GID_FT || _game.version != 7)
		return false;

	int roomNr = getResourceRoomNr(rtSound, idx);
	if (roomNr == 0)
		roomNr = _roomResource;

	const uint32 fileOffs = getResourceRoomOffset(rtSound, idx);
	if (fileOffs == RES_INVALID_OFFSET) {
		::ft64_diag_resource_event("stream-fail-offset", "sound-stream", (int)rtSound, (int)idx, 0, 0, 0, 0, 0, 0, -1);
		return false;
	}

	openRoom(roomNr);
	const uint32 outerOffset = fileOffs + _fileOffset;
	if (outerOffset < fileOffs || !_fileHandle->seek(outerOffset, SEEK_SET)) {
		::ft64_diag_resource_event("stream-fail-seek", "sound-stream", (int)rtSound, (int)idx, 0, 0, 0, 0, 0, outerOffset, -1);
		return false;
	}

	_fileHandle->readUint32LE();
	const uint32 outerSize = _fileHandle->readUint32BE();
	const uint32 baseTag = _fileHandle->readUint32BE();
	const uint32 innerSize = _fileHandle->readUint32BE();
	if (_fileHandle->err() || _fileHandle->eos()) {
		::ft64_diag_resource_event("stream-fail-header", "sound-stream", (int)rtSound, (int)idx, 0, 0, 0, 0, 0, baseTag, -1);
		return false;
	}

	if (baseTag == MKTAG('i','M','U','S')) {
		resourceOffset = outerOffset + 8;
		resourceSize = innerSize + 8;
		resourceTag = baseTag;
		if (resourceSize < innerSize) {
			::ft64_diag_resource_event("stream-fail-overflow", "sound-stream", (int)rtSound, (int)idx, innerSize, 0, 0, 0, 0, baseTag, -1);
			return false;
		}
	} else if (baseTag == MKTAG('C','r','e','a')) {
		if (outerSize <= 8) {
			::ft64_diag_resource_event("stream-fail-size", "sound-stream", (int)rtSound, (int)idx, outerSize, 0, 0, 0, 0, baseTag, -1);
			return false;
		}
		resourceOffset = outerOffset + 8;
		resourceSize = outerSize - 8;
		resourceTag = baseTag;
	} else {
		::ft64_diag_resource_event("stream-fail-format", "sound-stream", (int)rtSound, (int)idx, innerSize, 0, 0, 0, 0, baseTag, -1);
		return false;
	}

	const char *openName = _fileHandle->getName();
	if (!openName || !*openName || !openFile(file, Common::String(openName), true)) {
		::ft64_diag_resource_event("stream-fail-open", "sound-stream", (int)rtSound, (int)idx, resourceSize, 0, 0, 0, 0, baseTag, -1);
		return false;
	}

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

	const int32 signedFileSize = file.size();
	if (signedFileSize < 0 || resourceOffset > (uint32)signedFileSize ||
		resourceSize > (uint32)signedFileSize - resourceOffset) {
		::ft64_diag_resource_event("stream-fail-bounds", "sound-stream", (int)rtSound, (int)idx, resourceSize, 0, 0, 0, 0, (uint32)signedFileSize, -1);
		return false;
	}

	if (!file.seek(resourceOffset, SEEK_SET)) {
		::ft64_diag_resource_event("stream-fail-reseek", "sound-stream", (int)rtSound, (int)idx, resourceSize, 0, 0, 0, 0, resourceOffset, -1);
		return false;
	}
	const uint32 verifyTag = file.readUint32BE();
	if (verifyTag != resourceTag) {
		::ft64_diag_resource_event("stream-fail-magic", "sound-stream", (int)rtSound, (int)idx, resourceSize, 0, 0, 0, 0, verifyTag, -1);
		return false;
	}
	if (!file.seek(resourceOffset, SEEK_SET))
		return false;

	::ft64_diag_resource_event("stream-locate", "sound-stream", (int)rtSound, (int)idx, resourceSize, 0, 0, 0, 0, resourceTag, -1);
	return true;
}
#endif

'''
    s = sound_cpp.read_text()
    include_anchor = '#include "scumm/util.h"\n'
    s = replace_once(
        s,
        include_anchor,
        include_anchor
        + "#ifdef N64_FT_ONLY\n"
        + f"// {MARK}: resource diagnostic bridge\n"
        + "extern void ft64_diag_resource_event(const char *phase, const char *typeName, int typeId, int resourceId, uint32 resourceSize, uint32 allocationSize, uint32 cacheAllocated, uint32 minThreshold, uint32 maxThreshold, uint32 victimSize, int victimCounter);\n"
        + "#endif\n",
        "sound.cpp diagnostic bridge",
    )
    s = replace_once(
        s,
        "int ScummEngine::readSoundResource(ResId idx) {",
        locator + "int ScummEngine::readSoundResource(ResId idx) {",
        "locator insertion",
    )
    preload_old = "\tif (sound <= _vm->_numSounds)\n\t\t_vm->ensureResourceLoaded(rtSound, sound);\n"
    preload_new = (
        "\tif (sound <= _vm->_numSounds) {\n"
        "#ifdef N64_FT_ONLY\n"
        f"\t\t// {MARK}: iMUSE Digital owns FT sound payload residency\n"
        "\t\tif (_vm->_game.id != GID_FT)\n"
        "\t\t\t_vm->ensureResourceLoaded(rtSound, sound);\n"
        "#else\n"
        "\t\t_vm->ensureResourceLoaded(rtSound, sound);\n"
        "#endif\n"
        "\t}\n"
    )
    s = replace_once(s, preload_old, preload_new, "FT queue preload bypass")
    sound_cpp.write_text(s)

    s = snd_h.read_text()
    s = replace_once(
        s,
        "class ScummEngine;\n",
        "class ScummEngine;\n"
        "#ifdef N64_FT_ONLY\n"
        f"// {MARK}: stream handle forward declaration\n"
        "class ScummFile;\n"
        "#endif\n",
        "sndmgr ScummFile declaration",
    )
    old_line = next(line for line in s.splitlines(True) if line.strip() == "byte *resPtr;")
    s = replace_once(
        s,
        old_line,
        old_line
        + "#ifdef N64_FT_ONLY\n"
        + f"\t\t// {MARK}: universal FT streamed-resource state\n"
        + "\t\tScummFile *streamFile;\n"
        + "\t\tuint32 streamBase;\n"
        + "\t\tuint32 streamSize;\n"
        + "\t\tuint32 streamTag;\n"
        + "\t\tbyte *streamCache;\n"
        + "\t\tuint32 streamCacheStart;\n"
        + "\t\tuint32 streamCacheValid;\n"
        + "\t\tbool streamReadLogged;\n"
        + "#endif\n",
        "SoundDesc stream fields",
    )
    old_line = next(line for line in s.splitlines(True) if line.strip() == "void prepareSound(byte *ptr, SoundDesc *sound);")
    s = replace_once(
        s,
        old_line,
        old_line
        + "#ifdef N64_FT_ONLY\n"
        + f"\t// {MARK}: file-backed FT Crea/iMUS parser and buffered reader\n"
        + "\tvoid prepareSoundFromFTStream(SoundDesc *sound);\n"
        + "\tbool readFTStreamCached(SoundDesc *sound, uint32 relative, byte *dst, uint32 size);\n"
        + "#endif\n",
        "stream method declarations",
    )
    snd_h.write_text(s)

    s = snd_cpp.read_text()
    s = replace_once(
        s,
        '#include "scumm/resource.h"\n',
        '#include "scumm/resource.h"\n'
        '#ifdef N64_FT_ONLY\n'
        f'// {MARK}: file-backed FT audio\n'
        '#include "scumm/file.h"\n'
        'extern void ft64_diag_resource_event(const char *phase, const char *typeName, int typeId, int resourceId, uint32 resourceSize, uint32 allocationSize, uint32 cacheAllocated, uint32 minThreshold, uint32 maxThreshold, uint32 victimSize, int victimCounter);\n'
        '#endif\n',
        "sndmgr include bridge",
    )

    methods = r'''
#ifdef N64_FT_ONLY
// FT64 r2v structural: v20 universal FT audio streaming: buffered payload reader
static const uint32 kFT64StreamCacheSize = 16384;

bool ImuseDigiSndMgr::readFTStreamCached(SoundDesc *sound, uint32 relative, byte *dst, uint32 size) {
	if (!sound || !sound->streamFile || !sound->streamCache)
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
			if (want > kFT64StreamCacheSize)
				want = kFT64StreamCacheSize;

			const uint32 absolute = sound->streamBase + relative;
			if (absolute < sound->streamBase || !sound->streamFile->seek(absolute, SEEK_SET))
				return false;

			const uint32 got = sound->streamFile->read(sound->streamCache, want);
			if (got != want)
				return false;
			sound->streamCacheValid = got;

			if (!sound->streamReadLogged) {
				sound->streamReadLogged = true;
				::ft64_diag_resource_event("stream-read", "sound-stream", (int)rtSound, sound->soundId, sound->streamSize, size, 0, 0, 0, got, -1);
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
}

// FT64 r2v structural: v20 universal FT audio streaming: metadata-only parser
void ImuseDigiSndMgr::prepareSoundFromFTStream(SoundDesc *sound) {
	ScummFile *file = sound->streamFile;
	if (!file || sound->streamSize < 4)
		error("FT64 stream: invalid handle for sound %d", sound->soundId);

	const uint32 base = sound->streamBase;
	const uint32 limit = base + sound->streamSize;
	if (limit < base)
		error("FT64 stream: size overflow for sound %d", sound->soundId);

	if (!file->seek(base, SEEK_SET))
		error("FT64 stream: metadata seek failed for sound %d", sound->soundId);
	const uint32 tag = file->readUint32BE();
	if (tag != sound->streamTag)
		error("FT64 stream: metadata tag changed for sound %d", sound->soundId);

	if (tag == MKTAG('C','r','e','a')) {
		if (sound->streamSize < 26)
			error("FT64 stream: short Crea resource %d", sound->soundId);
		byte header[26];
		if (!file->seek(base, SEEK_SET) || file->read(header, sizeof(header)) != sizeof(header))
			error("FT64 stream: Crea header read failed for sound %d", sound->soundId);

		uint32 offset = READ_LE_UINT16(header + 20);
		sound->bits = 8;
		sound->channels = 1;
		sound->numRegions = 0;
		sound->numJumps = 0;
		sound->numSyncs = 0;
		sound->numMarkers = 0;
		sound->region = new Region[70];
		sound->jump = new Jump[1];
		sound->sync = NULL;
		sound->marker = NULL;
		assert(sound->region);
		assert(sound->jump);
		sound->offsetData = 0;

		bool quit = false;
		while (!quit) {
			if (offset > sound->streamSize || sound->streamSize - offset < 4)
				error("FT64 stream: Crea block outside sound %d", sound->soundId);
			byte lenBytes[4];
			if (!file->seek(base + offset, SEEK_SET) || file->read(lenBytes, 4) != 4)
				error("FT64 stream: Crea block read failed for sound %d", sound->soundId);

			uint32 packed = READ_LE_UINT32(lenBytes);
			int code = packed & 0xFF;
			if (code != 0 && code != 1 && code != 6 && code != 7) {
				offset += 2;
				if (offset > sound->streamSize || sound->streamSize - offset < 4 ||
					!file->seek(base + offset, SEEK_SET) || file->read(lenBytes, 4) != 4)
					error("FT64 stream: Crea workaround read failed for sound %d", sound->soundId);
				packed = READ_LE_UINT32(lenBytes);
				code = packed & 0xFF;
				if (code != 0 && code != 1 && code != 6 && code != 7)
					error("FT64 stream: invalid Crea code %d for sound %d", code, sound->soundId);
			}

			offset += 4;
			uint32 len = packed >> 8;
			if (len > sound->streamSize - offset)
				error("FT64 stream: Crea payload outside sound %d", sound->soundId);

			switch (code) {
			case 0:
				quit = true;
				break;
			case 1: {
				if (len < 2 || sound->numRegions >= 70)
					error("FT64 stream: malformed Crea data block for sound %d", sound->soundId);
				byte voc[2];
				if (!file->seek(base + offset, SEEK_SET) || file->read(voc, 2) != 2)
					error("FT64 stream: Crea rate read failed for sound %d", sound->soundId);
				const int timeConstant = voc[0];
				offset += 2;
				len -= 2;
				sound->freq = Audio::getSampleRateFromVOCRate(timeConstant);
				sound->region[sound->numRegions].offset = offset;
				sound->region[sound->numRegions].length = len;
				sound->numRegions++;
				break;
			}
			case 6:
				sound->jump[0].dest = offset + 8;
				sound->jump[0].hookId = 0;
				sound->jump[0].fadeDelay = 0;
				break;
			case 7:
				if (sound->numRegions >= 70)
					error("FT64 stream: too many Crea regions for sound %d", sound->soundId);
				sound->jump[0].offset = offset - 4;
				sound->numJumps++;
				sound->region[sound->numRegions].offset = offset - 4;
				sound->region[sound->numRegions].length = 0;
				sound->numRegions++;
				break;
			default:
				error("FT64 stream: invalid Crea code %d for sound %d", code, sound->soundId);
			}
			offset += len;
		}
		return;
	}

	if (tag != MKTAG('i','M','U','S'))
		error("FT64 stream: unsupported format for sound %d", sound->soundId);
	if (sound->streamSize < 24 || !file->seek(base + 16, SEEK_SET))
		error("FT64 stream: short iMUS header for sound %d", sound->soundId);

	int numRegions = 0;
	int numJumps = 0;
	int numSyncs = 0;
	int numMarkers = 0;
	bool foundData = false;

	while (!foundData) {
		const int32 rawPos = file->pos();
		if (rawPos < 0 || (uint32)rawPos > limit || limit - (uint32)rawPos < 8)
			error("FT64 stream: truncated iMUS metadata for sound %d", sound->soundId);
		const uint32 chunkTag = file->readUint32BE();
		const uint32 chunkSize = file->readUint32BE();
		const uint32 payload = (uint32)file->pos();
		if (payload > limit || chunkSize > limit - payload)
			error("FT64 stream: iMUS chunk outside sound %d", sound->soundId);

		switch (chunkTag) {
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
					error("FT64 stream: TEXT seek failed for sound %d", sound->soundId);
				char markerName[5] = { 0, 0, 0, 0, 0 };
				uint32 chars = chunkSize - 4;
				if (chars > 4)
					chars = 4;
				if (file->read(markerName, chars) != chars)
					error("FT64 stream: TEXT read failed for sound %d", sound->soundId);
				if (!scumm_stricmp(markerName, "exit"))
					++numMarkers;
			}
			break;
		}
		case MKTAG('D','A','T','A'):
			foundData = true;
			break;
		default:
			error("FT64 stream: unknown iMUS header '%s' for sound %d", tag2str(chunkTag), sound->soundId);
		}
		if (!foundData && !file->seek(payload + chunkSize, SEEK_SET))
			error("FT64 stream: iMUS chunk seek failed for sound %d", sound->soundId);
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
		const uint32 chunkTag = file->readUint32BE();
		const uint32 chunkSize = file->readUint32BE();
		const uint32 payload = (uint32)file->pos();
		if (payload > limit || chunkSize > limit - payload)
			error("FT64 stream: second-pass chunk outside sound %d", sound->soundId);

		switch (chunkTag) {
		case MKTAG('F','R','M','T'):
			if (chunkSize < 20 || !file->seek(payload + 8, SEEK_SET))
				error("FT64 stream: malformed FRMT for sound %d", sound->soundId);
			sound->bits = file->readUint32BE();
			sound->freq = file->readUint32BE();
			sound->channels = file->readUint32BE();
			break;
		case MKTAG('T','E','X','T'):
			if (chunkSize >= 8) {
				if (!file->seek(payload, SEEK_SET))
					error("FT64 stream: TEXT2 seek failed for sound %d", sound->soundId);
				const uint32 markerPos = file->readUint32BE();
				char markerName[5] = { 0, 0, 0, 0, 0 };
				uint32 chars = chunkSize - 4;
				if (chars > 4)
					chars = 4;
				if (file->read(markerName, chars) != chars)
					error("FT64 stream: TEXT2 read failed for sound %d", sound->soundId);
				if (!scumm_stricmp(markerName, "exit")) {
					if (curMarker >= numMarkers)
						error("FT64 stream: marker overflow for sound %d", sound->soundId);
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
			if (chunkSize < 8 || curRegion >= numRegions || !file->seek(payload, SEEK_SET))
				error("FT64 stream: malformed REGN for sound %d", sound->soundId);
			sound->region[curRegion].offset = file->readUint32BE();
			sound->region[curRegion].length = file->readUint32BE();
			++curRegion;
			break;
		case MKTAG('J','U','M','P'):
			if (chunkSize < 16 || curJump >= numJumps || !file->seek(payload, SEEK_SET))
				error("FT64 stream: malformed JUMP for sound %d", sound->soundId);
			sound->jump[curJump].offset = file->readUint32BE();
			sound->jump[curJump].dest = file->readUint32BE();
			sound->jump[curJump].hookId = (byte)file->readUint32BE();
			sound->jump[curJump].fadeDelay = (int16)file->readUint32BE();
			++curJump;
			break;
		case MKTAG('S','Y','N','C'):
			if (curSync >= numSyncs)
				error("FT64 stream: SYNC overflow for sound %d", sound->soundId);
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
			error("FT64 stream: unknown second-pass header '%s' for sound %d", tag2str(chunkTag), sound->soundId);
		}
		if (!foundData && !file->seek(payload + chunkSize, SEEK_SET))
			error("FT64 stream: second-pass seek failed for sound %d", sound->soundId);
	}

	if (curRegion != numRegions || curJump != numJumps || curSync != numSyncs || curMarker != numMarkers)
		error("FT64 stream: metadata count mismatch for sound %d", sound->soundId);
}
#endif

'''
    open_sig = "ImuseDigiSndMgr::SoundDesc *ImuseDigiSndMgr::openSound(int32 soundId, const char *soundName, int soundType, int volGroupId, int disk) {"
    s = replace_once(s, open_sig, methods + open_sig, "stream methods insertion")

    case_start, case_end = locate_imuse_case(s)
    new_case = r'''\tcase IMUSE_RESOURCE:
\t\tassert(soundName[0] == 0);\t// Paranoia check
#ifdef N64_FT_ONLY
\t\tif (_vm->_game.id == GID_FT) {
\t\t\tScummFile *ft64Stream = new ScummFile();
\t\t\tassert(ft64Stream);
\t\t\tuint32 ft64Base = 0;
\t\t\tuint32 ft64Size = 0;
\t\t\tuint32 ft64Tag = 0;
\t\t\tif (!_vm->openFTSoundStream(soundId, *ft64Stream, ft64Base, ft64Size, ft64Tag)) {
\t\t\t\t::ft64_diag_resource_event("stream-open-failed", "sound-stream", (int)rtSound, soundId, 0, 0, 0, 0, 0, 0, -1);
\t\t\t\tdelete ft64Stream;
\t\t\t\tcloseSound(sound);
\t\t\t\treturn NULL;
\t\t\t}
\t\t\tstrcpy(sound->name, soundName);
\t\t\tsound->soundId = soundId;
\t\t\tsound->type = soundType;
\t\t\tsound->volGroupId = volGroupId;
\t\t\tsound->disk = _disk;
\t\t\tsound->streamFile = ft64Stream;
\t\t\tsound->streamBase = ft64Base;
\t\t\tsound->streamSize = ft64Size;
\t\t\tsound->streamTag = ft64Tag;
\t\t\tsound->streamCache = new byte[kFT64StreamCacheSize];
\t\t\tassert(sound->streamCache);
\t\t\tsound->streamCacheStart = 0;
\t\t\tsound->streamCacheValid = 0;
\t\t\tsound->streamReadLogged = false;
\t\t\tprepareSoundFromFTStream(sound);
\t\t\t::ft64_diag_resource_event("stream-open", "sound-stream", (int)rtSound, soundId, ft64Size, kFT64StreamCacheSize, 0, 0, 0, ft64Tag, -1);
\t\t\treturn sound;
\t\t}
#endif
\t\t_vm->ensureResourceLoaded(rtSound, soundId);
\t\t_vm->_res->lock(rtSound, soundId);
\t\tptr = _vm->getResourceAddress(rtSound, soundId);
\t\tif (ptr == NULL) {
\t\t\tcloseSound(sound);
\t\t\treturn NULL;
\t\t}
\t\tsound->resPtr = ptr;
\t\tbreak;'''
    # This raw literal deliberately spells tab escapes; turn them into real tabs
    # before inserting into the C++ source.
    new_case = new_case.replace("\\t", "\t")
    s = replace_region(s, case_start, case_end, new_case)

    close_idx = locate_close_delete(s)
    close_block = (
        "#ifdef N64_FT_ONLY\n"
        f"\t// {MARK}: release independent stream and read-ahead cache\n"
        "\tif (soundDesc->streamFile) {\n"
        "\t\t::ft64_diag_resource_event(\"stream-close\", \"sound-stream\", (int)rtSound, soundDesc->soundId, soundDesc->streamSize, kFT64StreamCacheSize, 0, 0, 0, soundDesc->streamTag, -1);\n"
        "\t\tdelete soundDesc->streamFile;\n"
        "\t\tsoundDesc->streamFile = NULL;\n"
        "\t}\n"
        "\tdelete[] soundDesc->streamCache;\n"
        "\tsoundDesc->streamCache = NULL;\n"
        "#endif\n"
        "\tdelete soundDesc->compressedStream;"
    )
    s = replace_region(s, close_idx, close_idx + 1, close_block)

    read_start, read_end = locate_resptr_branch(s)
    stream_read = r'''#ifdef N64_FT_ONLY
\t} else if (soundDesc->streamFile) {
\t\t// FT64 r2v structural: v20 universal FT audio streaming: callback read
\t\t*buf = (byte *)malloc(size);
\t\tassert(*buf);
\t\tconst int32 relative = start + offset + header_size;
\t\tif (relative < 0 || !readFTStreamCached(soundDesc, (uint32)relative, *buf, (uint32)size))
\t\t\terror("FT64 stream: payload read failed for sound %d", soundDesc->soundId);
#endif
\t} else if (soundDesc->resPtr) {
\t\t*buf = (byte *)malloc(size);
\t\tassert(*buf);
\t\tmemcpy(*buf, soundDesc->resPtr + start + offset + header_size, size);'''.replace("\\t", "\t")
    s = replace_region(s, read_start, read_end, stream_read)
    snd_cpp.write_text(s)


def verify(root: Path):
    scumm_h, sound_cpp, snd_h, snd_cpp = paths(root)
    texts = {p: p.read_text() for p in (scumm_h, sound_cpp, snd_h, snd_cpp)}
    all_text = "\n".join(texts.values())

    for token in (
        "openFTSoundStream",
        "_fileHandle->getName()",
        "MKTAG('C','r','e','a')",
        "MKTAG('i','M','U','S')",
        "kFT64StreamCacheSize = 16384",
        "prepareSoundFromFTStream",
        "readFTStreamCached",
        '"stream-locate"',
        '"stream-open"',
        '"stream-read"',
        '"stream-close"',
        '"stream-open-failed"',
        '"stream-fail-format"',
        "soundDesc->streamFile",
        "soundDesc->streamCache",
        "if (_vm->_game.id != GID_FT)",
    ):
        if token not in all_text:
            raise PatchError(f"verify missing token: {token}")

    for token in (
        "fullSize < 512 * 1024",
        "size >= 512 * 1024",
        "ft64LargeSoundArena",
        "large-sound-arena",
        "sound-633-stop",
        "ft64PreviousSoundId = 622",
    ):
        if token in all_text:
            raise PatchError(f"forbidden legacy token remains: {token}")

    s = texts[snd_cpp]
    stream_pos = s.index("if (_vm->_game.id == GID_FT)")
    fail_pos = s.index('"stream-open-failed"', stream_pos)
    original_load = s.index("_vm->ensureResourceLoaded(rtSound, soundId);", stream_pos)
    if not stream_pos < fail_pos < original_load:
        raise PatchError("FT streaming failure is not handled before original resource loading")
    if "return NULL;" not in s[fail_pos:original_load]:
        raise PatchError("FT streaming failure can still fall through to whole-resource loading")

    if all_text.count(MARK) < 7:
        raise PatchError("too few v20 structural markers")
    print("[ft-stream-v20] verified")


def main() -> int:
    ap = argparse.ArgumentParser()
    mode = ap.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--apply", action="store_true")
    mode.add_argument("--verify", action="store_true")
    ap.add_argument("root")
    ns = ap.parse_args()

    try:
        if ns.check:
            check_pristine(Path(ns.root))
            print("[ft-stream-v20] check OK")
        elif ns.apply:
            apply(Path(ns.root))
            print("[ft-stream-v20] applied")
        else:
            verify(Path(ns.root))
    except PatchError as exc:
        print(f"[ft-stream-v20] ERROR: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
