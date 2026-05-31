# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```sh
swift build                  # debug build (no signing required, works for swift run)
swift build -c release       # release build
make sign                    # release build + ad-hoc codesign with Virtualization entitlement
make run                     # sign + run with test.json (CONFIG= to override)
make smoke                   # basic CLI smoke tests (checks bad args, missing file)
make clean                   # clean SwiftPM build output
```

Development run (no signing needed):
```sh
swift run vmm run test.json
```

The release binary **must be signed** before use because `Virtualization.framework` requires the `com.apple.security.virtualization` entitlement declared in `vmm.entitlements`. `swift run` bypasses this requirement and is the normal dev path.

There is no formal test suite — `make smoke` is the only automated check.

## Architecture

Single Swift executable target (`Sources/vmm/`) using `swift-argument-parser` and `Virtualization.framework`. Requires macOS 13+. Works on both Apple Silicon and Intel Macs.

**Data flow for a `vmm run` invocation:**

1. `main.swift` — parses CLI args; writes PID file; creates `SocketManager` if `--socket` given; calls `buildConfiguration`, then `VMRunner.run()`
2. `VMConfig.swift` — decodes JSON config; resolves relative paths against the config file's directory
3. `VMBuilder.swift` — translates `VMConfig` into a `VZVirtualMachineConfiguration` (boot loader, virtio-blk storage, NAT network, virtio serial, entropy device)
4. `VMRunner.swift` — starts the VM; drives the main `RunLoop` manually (Virtualization.framework requires it); installs a `SIGTERM` handler that calls `requestStop()` and force-stops after 30 s if the guest hasn't halted
5. `SocketManager.swift` — when `--socket` is used, owns a Unix domain socket listener; bridges one active client at a time to/from the VM's serial port via `Pipe` pairs; reconnecting clients replace the previous connection
6. `Terminal.swift` — when no socket is used, switches stdin to raw mode so the terminal acts as a direct console

**Console I/O paths:**

- Direct mode: `stdin`/`stdout` → `VZFileHandleSerialPortAttachment`; raw terminal mode enabled via `Terminal.swift`
- Socket mode: `SocketManager` creates two `Pipe`s; the read end of one pipe becomes `serialInput`, the write end of the other becomes `serialOutput`; socket clients are bridged to those pipes
