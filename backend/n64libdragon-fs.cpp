#define FORBIDDEN_SYMBOL_ALLOW_ALL

#include "backends/platform/n64libdragon/n64libdragon-fs.h"
#include "backends/fs/stdiostream.h"
#include "common/str.h"

#include <dir.h>
#include <libdragon.h>
#include <string.h>

static const char *kN64SdRoot = "sd:/";
static uint32_t s_diagFsMisses = 0;
static uint32_t s_diagFsOps = 0;
static const uint32_t kDiagFsMissLimit = 96;
static const uint32_t kDiagFsOpLimit = 192;

static Common::String canonicalizeN64Path(const Common::String &input) {
    Common::String path = input;

    if (path.empty() || path == "." || path == "/" || path == "sd:" || path == "sd:/")
        return Common::String(kN64SdRoot);

    if (!path.hasPrefix("sd:/")) {
        if (path.hasPrefix("/"))
            path = Common::String("sd:") + path;
        else
            path = Common::String("sd:/") + path;
    }

    path = Common::normalizePath(path, '/');
    if (path == "sd:")
        path = kN64SdRoot;
    return path;
}

static void splitParentAndName(const Common::String &path,
                               Common::String &parent,
                               Common::String &name) {
    if (path == kN64SdRoot) {
        parent = kN64SdRoot;
        name.clear();
        return;
    }

    const char *start = path.c_str();
    const char *end = start + path.size();
    const char *component = end;

    while (component > start && *(component - 1) != '/')
        --component;

    parent = Common::String(start, component);
    if (parent.empty() || parent == "sd:")
        parent = kN64SdRoot;
    name = Common::String(component, end);
}

static bool findEntryInDirectory(const Common::String &parent,
                                 const Common::String &name,
                                 dir_t &found) {
    dir_t entry;
    int rc = dir_findfirst(parent.c_str(), &entry);
    bool matched = false;

    while (rc == 0) {
        if (!matched && Common::String(entry.d_name).equalsIgnoreCase(name)) {
            found = entry;
            matched = true;
        }
        // Exhaust the walk even after a match. The pinned libdragon FAT
        // implementation closes its single internal directory handle only
        // when dir_findnext() reaches the end.
        rc = dir_findnext(parent.c_str(), &entry);
    }

    return matched;
}

N64LibdragonFilesystemNode::N64LibdragonFilesystemNode()
    : _isDirectory(false), _isValid(false) {
}

N64LibdragonFilesystemNode::N64LibdragonFilesystemNode(const Common::String &path)
    : _path(canonicalizeN64Path(path)), _isDirectory(false), _isValid(false) {
    if (_path == kN64SdRoot)
        _displayName = "SD Card";
    else
        _displayName = Common::lastPathComponent(_path, '/');

    setFlags();
}

void N64LibdragonFilesystemNode::setFlags() {
    if (_path == kN64SdRoot) {
        _isValid = true;
        _isDirectory = true;
        return;
    }

    Common::String parent;
    Common::String name;
    splitParentAndName(_path, parent, name);

    dir_t entry;
    if (!findEntryInDirectory(parent, name, entry)) {
        if (_path.hasPrefix("sd:/fullthrottle/") && s_diagFsMisses < kDiagFsMissLimit) {
            debugf("[FT64DIAG r2t] FS MISS %s\n", _path.c_str());
            ++s_diagFsMisses;
        }
        _isValid = false;
        _isDirectory = false;
        return;
    }

    _isValid = (entry.d_type == DT_DIR || entry.d_type == DT_REG);
    _isDirectory = (entry.d_type == DT_DIR);
}

bool N64LibdragonFilesystemNode::isWritable() const {
    // The mounted SummerCart FAT filesystem supports file create/write in
    // existing directories. Directory creation itself is not exposed by the
    // pinned libdragon FAT adapter, so sd:/fullthrottle/saves must already
    // exist on the user's card.
    return _path.hasPrefix("sd:/");
}

AbstractFSNode *N64LibdragonFilesystemNode::getChild(const Common::String &name) const {
    if (!_isDirectory || name.empty() || name.contains('/'))
        return 0;

    Common::String childPath = _path;
    if (childPath.lastChar() != '/')
        childPath += '/';
    childPath += name;
    return new N64LibdragonFilesystemNode(childPath);
}

bool N64LibdragonFilesystemNode::getChildren(AbstractFSList &list,
                                              ListMode mode,
                                              bool hidden) const {
    if (!_isValid || !_isDirectory)
        return false;

    // libdragon's pinned FAT implementation maintains one directory walk
    // internally. Do not call setFlags() while this enumeration is active;
    // populate the child metadata directly from dir_t instead.
    dir_t entry;
    int rc = dir_findfirst(_path.c_str(), &entry);

    // -1 is also the documented result for an existing empty directory.
    if (rc < -1)
        return false;

    while (rc == 0) {
        const char *entryName = entry.d_name;

        if ((entryName[0] == '.' && entryName[1] == '\0') ||
            (entryName[0] == '.' && entryName[1] == '.' && entryName[2] == '\0')) {
            rc = dir_findnext(_path.c_str(), &entry);
            continue;
        }

        if (!hidden && entryName[0] == '.') {
            rc = dir_findnext(_path.c_str(), &entry);
            continue;
        }

        const bool isDir = entry.d_type == DT_DIR;
        const bool valid = isDir || entry.d_type == DT_REG;
        if (!valid) {
            rc = dir_findnext(_path.c_str(), &entry);
            continue;
        }

        if ((mode == Common::FSNode::kListFilesOnly && isDir) ||
            (mode == Common::FSNode::kListDirectoriesOnly && !isDir)) {
            rc = dir_findnext(_path.c_str(), &entry);
            continue;
        }

        N64LibdragonFilesystemNode *child = new N64LibdragonFilesystemNode();
        child->_displayName = entryName;
        child->_path = _path;
        if (child->_path.lastChar() != '/')
            child->_path += '/';
        child->_path += entryName;
        child->_isDirectory = isDir;
        child->_isValid = true;
        list.push_back(child);

        rc = dir_findnext(_path.c_str(), &entry);
    }

    return true;
}

AbstractFSNode *N64LibdragonFilesystemNode::getParent() const {
    if (_path == kN64SdRoot)
        return new N64LibdragonFilesystemNode(kN64SdRoot);

    Common::String parent;
    Common::String name;
    splitParentAndName(_path, parent, name);
    return new N64LibdragonFilesystemNode(parent);
}

Common::SeekableReadStream *N64LibdragonFilesystemNode::createReadStream() {
    const bool diag = _path.hasPrefix("sd:/fullthrottle") && s_diagFsOps < kDiagFsOpLimit;
    if (diag) ++s_diagFsOps;
    if (!_isValid || _isDirectory) {
        if (diag)
            debugf("[FT64DIAG r2t] FS READ deny valid=%d dir=%d path=%s\n",
                   _isValid ? 1 : 0, _isDirectory ? 1 : 0, _path.c_str());
        return 0;
    }
    if (diag) debugf("[FT64DIAG r2t] FS READ open %s\n", _path.c_str());
    Common::SeekableReadStream *stream = StdioStream::makeFromPath(_path, false);
    if (diag)
        debugf("[FT64DIAG r2t] FS READ result=%d path=%s\n",
               stream ? 1 : 0, _path.c_str());
    return stream;
}

Common::WriteStream *N64LibdragonFilesystemNode::createWriteStream() {
    const bool diag = _path.hasPrefix("sd:/fullthrottle") && s_diagFsOps < kDiagFsOpLimit;
    if (diag) ++s_diagFsOps;
    if (_isDirectory) {
        if (diag) debugf("[FT64DIAG r2t] FS WRITE deny-dir %s\n", _path.c_str());
        return 0;
    }
    if (diag) debugf("[FT64DIAG r2t] FS WRITE open %s\n", _path.c_str());
    Common::WriteStream *stream = StdioStream::makeFromPath(_path, true);
    if (diag)
        debugf("[FT64DIAG r2t] FS WRITE result=%d path=%s\n",
               stream ? 1 : 0, _path.c_str());
    return stream;
}

AbstractFSNode *N64LibdragonFilesystemFactory::makeCurrentDirectoryFileNode() const {
    return new N64LibdragonFilesystemNode(kN64SdRoot);
}

AbstractFSNode *N64LibdragonFilesystemFactory::makeFileNodePath(const Common::String &path) const {
    return new N64LibdragonFilesystemNode(path);
}

AbstractFSNode *N64LibdragonFilesystemFactory::makeRootFileNode() const {
    return new N64LibdragonFilesystemNode(kN64SdRoot);
}
