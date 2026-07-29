#ifndef BACKENDS_FS_N64LIBDRAGON_H
#define BACKENDS_FS_N64LIBDRAGON_H

#include "backends/fs/abstract-fs.h"
#include "backends/fs/fs-factory.h"

class N64LibdragonFilesystemNode : public AbstractFSNode {
protected:
    Common::String _displayName;
    Common::String _path;
    bool _isDirectory;
    bool _isValid;

    N64LibdragonFilesystemNode();
    void setFlags();

public:
    explicit N64LibdragonFilesystemNode(const Common::String &path);

    virtual bool exists() const { return _isValid; }
    virtual Common::String getDisplayName() const { return _displayName; }
    virtual Common::String getName() const { return _displayName; }
    virtual Common::String getPath() const { return _path; }
    virtual bool isDirectory() const { return _isDirectory; }
    virtual bool isReadable() const { return _isValid; }
    virtual bool isWritable() const;

    virtual AbstractFSNode *getChild(const Common::String &name) const;
    virtual bool getChildren(AbstractFSList &list, ListMode mode, bool hidden) const;
    virtual AbstractFSNode *getParent() const;

    virtual Common::SeekableReadStream *createReadStream();
    virtual Common::WriteStream *createWriteStream();
};

class N64LibdragonFilesystemFactory : public FilesystemFactory {
public:
    virtual AbstractFSNode *makeCurrentDirectoryFileNode() const;
    virtual AbstractFSNode *makeFileNodePath(const Common::String &path) const;
    virtual AbstractFSNode *makeRootFileNode() const;
};

#endif
