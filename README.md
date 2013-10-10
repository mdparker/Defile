Defile
======

A convenience wrapper for the PHYSFS library, for the D Programming Language. Note that this is currently incomplete and will be fleshed out over time.

##Usage

This is an example. There is more functionality not demonstrated here.

```D
import defile.defile;

void main() {
    scope( exit ) Defile.terminate();
    Defile.initialize();

    // Read the entire content of a file.
    ubyte[] buf;
    Defile.readFile( "foo.bar", buf );

    // Manipulate the bytes.
    ...

    // Open a file for reading and read in smaller chunks.
    auto file = Defile( "foo.bar", OpenFor.Read );

    ubyte[] buf2;

    // Read 32 bytes
    file.read( buf2, 32, 1 );

    // Read 128 bytes
    file.read( buf2, 32, 4 );

    // Alternatively...
    file.read( buf2, 128, 1 );

    // Close if you want, but the destructor will do so automatically on scope exit.
    file.close();
}
```