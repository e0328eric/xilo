# xilo
An improved `rm` command. The origin of this program name comes from the greek word `ξήλωμα` which means the word `rip` in English.

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