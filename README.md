# xilo-zig
A simple replacement of "rm" command. This is also a practical example how to use [zlap](https://github.com/e0328eric/zlap.git) library.

# How to install

## Use precompiled binary
Download binary from `Releases`. All binaries are compiled into `ReleaseSmall` optimize.

## Build from source
First, you need to 
```console
$ zig run install -p <install path> -Doptimize=ReleaseSafe
```
where `<install path>` is the path where you want to put compiled executable.
Then the executable will be saved at `<install path>/bin`.
