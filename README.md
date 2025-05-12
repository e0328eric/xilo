# xilo
A simple replacement of "rm" command. This is also a practical example how to use [zlap](https://github.com/e0328eric/zlap.git) library.
The origin of this program name comes from the greek word `ξήλωμα` which means the word `rip` in English.

# How to install

## Use precompiled binary
Download binary from `Releases`. All binaries are compiled into `ReleaseSmall` optimize.

## Build from source
First, you need to
```console
$ zig run install -prefix-exe-dir <install path> -Doptimize=ReleaseSafe
```
where `<install path>` is the path where you want to put compiled executable.
Then the executable will be saved at `<install path>/bin`.

Recommended `<install path>` is `~/.local/bin`, so run this makes `xilo` to move into that directory.
```console
$ zig run install -prefix-exe-dir ~/.local/bin -Doptimize=ReleaseSafe
```

