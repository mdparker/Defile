module defile.defile;

private {
    import std.string;
    import std.conv;

    import derelict.physfs.physfs;
}

class DefileException : Exception {
    public this( string msg, string file = __FILE__, size_t line = __LINE__ ) {
        this( msg, true, file, line );
    }

    public this( string msg, bool getErrString, string file = __FILE__, size_t line = __LINE__ ) {
        if( getErrString ) {
            msg = format( "%s: %s", msg, Defile.lastError );
        }
        super( msg, file, line, null );
    }
}

enum OpenFor {
    Read,
    Write,
    Append,
}

enum ConfigFlags {
    None = 0x0,
    IncludeCDRoms = 0x1,
    ArchivesFirst = 0x2,
}

enum PathType {
    Write,
    Base,
    User,
}

struct Defile {
    private static {
        string _baseDir;
        string _userDir;
        string _writeDir;
    }

    public static {
        void initialize() {
            import core.runtime;

            DerelictPHYSFS.load();
            if( PHYSFS_init( Runtime.args[ 0 ].toStringz() ) == 0 ) {
                throw new DefileException( "Failed to initialize virtual file system" );
            }
        }

        void terminate() {
            if( DerelictPHYSFS.isLoaded ) {
                PHYSFS_deinit();
            }
        }

        void setSaneConfig( string organization, string appName, string archiveExt, ConfigFlags flags = ConfigFlags.None ) {
            int cds = flags & ConfigFlags.IncludeCDRoms;
            int af = flags & ConfigFlags.ArchivesFirst;
            auto ae = archiveExt is null ? null : archiveExt.toStringz();

            if( PHYSFS_setSaneConfig( organization.toStringz(), appName.toStringz(), ae, cds, af) == 0) {
                throw new DefileException( "Failed to configure virtual file system" );
            }
        }

        void mkdir( string dirName ) {
            if( PHYSFS_mkdir( dirName.toStringz() ) == 0 ) {
                throw new DefileException( "Failed to create directory " ~ dirName );
            }
        }

        bool exists( string filePath ) {
            return PHYSFS_exists( filePath.toStringz() ) != 0;
        }

        void mount( string newDir, string mountPoint, bool appendToPath ) {
            auto mp = mountPoint is null ? null : mountPoint.toStringz();
            if( PHYSFS_mount( newDir.toStringz(), mp, appendToPath ? 1 : 0 ) == 0 ) {
                throw new DefileException( "Failed to mount " ~ newDir );
            }
        }

        size_t readFile( string filePath, ref ubyte[] buffer ) {
            auto file = Defile( filePath, OpenFor.Read );
            auto size = file.length;
            auto ret = file.read( buffer, size, 1 );
            return ret * size;
        }

        size_t writeFile( string filePath, ubyte[] buffer ) {
            auto file = Defile( filePath, OpenFor.Write );
            auto ret = file.write( buffer, buffer.length, 1 );
            return ret * buffer.length;
        }

        string makeFilePath( PathType which, string fileName ) {
            version( Windows ) string fmtString = "%s\\%s";
            else string fmtString = "%s/%s";

            with( PathType ) final switch( which ) {
                case Write:
                    return format( fmtString, _writeDir, fileName );

                case Base:
                    return format( fmtString, _baseDir, fileName );

                case User:
                    return format( fmtString, _userDir, fileName );
            }
        }

        string findFilePath( string fileName ) {
            auto path = makeFilePath( PathType.Write, fileName );
            if( exists( path )) return path;

            path = makeFilePath( PathType.Base, fileName );
            if( exists( path )) return path;

            return null;
        }

        @property {
            string lastError() {
                return to!string( PHYSFS_getLastError() );
            }

            string baseDir() {
                if( _baseDir !is null ) {
                    return _baseDir;
                } else {
                    _baseDir = to!string( PHYSFS_getBaseDir() );
                    return _baseDir;
                }
            }

            string userDir() {
                if( _userDir !is null ) {
                    return _userDir;
                } else {
                    _userDir = to!string( PHYSFS_getUserDir() );
                    return _userDir;
                }
            }

            string writeDir() {
                if( _writeDir !is null ) {
                    return _writeDir;
                } else {
                    _writeDir = to!string( PHYSFS_getWriteDir() );
                    return _writeDir;
                }
            }

            void writeDir( string dir ) {
                auto ret = PHYSFS_setWriteDir( dir.toStringz() );
                if( ret == 0 ) {
                    throw new DefileException( "Failed to set write directory " ~ dir );
                }
                _writeDir = dir;
            }

            string[] searchPath()  {
                string[] ret;
                auto list = PHYSFS_getSearchPath();
                for( size_t i = 0; list[ i ]; ++i ) {
                    ret ~= to!string( list[ i ] );
                }
                PHYSFS_freeList( list );
                return ret;
            }
        }
    }

    private {
        string _name;
        PHYSFS_File *_handle;
    }

    public {
        this( string fileName, OpenFor ofor ) {
            open( fileName, ofor );
        }

        ~this() {
            close();
        }

        void open( string fileName, OpenFor ofor ) {
            auto cname = fileName.toStringz();
            with( OpenFor ) final switch( ofor ) {
                case Read:
                    _handle = PHYSFS_openRead( cname );
                    break;

                case Write:
                    _handle = PHYSFS_openWrite( cname );
                    break;

                case Append:
                    _handle = PHYSFS_openAppend( cname );
                    break;
            }

            if( !_handle ) {
                throw new DefileException( "Failed to open file " ~ fileName );
            }

            _name = fileName;
        }

        void close() {
            if( _handle ) {
                PHYSFS_close( _handle );
                _handle = null;
            }
        }

        void flush() {
            assert( _handle );
            if( PHYSFS_flush( _handle ) == 0 ) {
                throw new DefileException( "Failed to flush file " ~ _name );
            }
        }

        void seek( size_t position ) {
            assert( _handle );
            if( PHYSFS_seek( _handle, position ) == 0 ) {
                throw new DefileException( format( "Failed to seek to position %s in file %s", position, _name ));
            }
        }

        size_t tell() {
            assert( _handle );
            auto ret = PHYSFS_tell( _handle );
            if( ret == -1 ) {
                throw new DefileException( "Failed to determine position in file " ~ _name );
            }
            return cast( size_t )ret;
        }

        size_t read( ref ubyte[] buffer, size_t objSize, size_t objCount ) {
            assert( _handle );

            size_t bytesToRead = objSize * objCount;
            if( buffer.length == 0 ) {
                buffer = new ubyte[ bytesToRead ];
            } else if( buffer.length < bytesToRead ) {
                buffer.length += bytesToRead;
            }

            auto ret = PHYSFS_read( _handle, buffer.ptr, cast( uint )objSize, cast( uint )objCount );
            if( ret == -1 ) {
                throw new DefileException( "Failed to read from file " ~ _name );
            }
            return cast( size_t )ret;
        }

        size_t write( ubyte[] buffer, size_t objSize, size_t objCount ) {
            assert( _handle );
            auto ret = PHYSFS_write( _handle, buffer.ptr, cast( uint )objSize, cast( uint )objCount );
            if( ret == -1 ) {
                throw new DefileException( "Failed to write to file " ~ _name );
            }
            return cast( size_t )ret;
        }

        @property {
            size_t length() {
                if( !_handle ) return 0;

                auto len = PHYSFS_fileLength( _handle );
                if( len == -1 ) {
                    throw new DefileException( "Invalid length for file " ~ _name );
                }
                return cast( size_t )len;
            }

            bool eof() {
                if( !_handle ) return true;
                return PHYSFS_eof( _handle ) > 0;
            }

            void bufferSize( size_t size ) {
                assert( _handle );
                if( PHYSFS_setBuffer( _handle, size ) == 0 ) {
                    throw new DefileException( "Failed to set buffer size for file " ~ _name );
                }
            }
        }
    }
}