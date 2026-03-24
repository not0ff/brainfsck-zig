> [!WARNING]
> This is the development branch and functionality isn't guaranteed to work properly

# brainfsck-zig
Brainf*ck compiler and interpreter written in Zig.

## Usage
Run a brainf*ck file with the interpreter:
```
$ brainfsck-zig interpret <filepath>
```
or compile to x86_64 assembly:
```
$ brainfsck-zig compile examples/hello_world.bf
```
and generate an ELF executable with fasm
```
$ fasm hello_world.asm
$ ./hello_world
```

## Compiling
Zig version 0.15.2 is required. To build in release mode run:
```
$ zig build -Drelease=true
```

## TODO
- [x] Optimized  [-] and [+] operations
- [ ] Implement even more optimizations [1]
- [ ] Producing an executable directly

## References
- https://esolangs.org/wiki/Brainfuck
- https://en.wikipedia.org/wiki/Brainfuck
- https://flatassembler.net/
- http://calmerthanyouare.org/2015/01/07/optimizing-brainfuck.html [1]