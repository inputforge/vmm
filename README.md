# vmm

`vmm` is a small macOS Virtualization.framework runner for Linux VMs. It boots a VM from a JSON configuration, supports optional PID-file management, can expose the VM console over a Unix socket, and handles `SIGTERM` by requesting a graceful guest shutdown before forcing a stop.

## Requirements

- macOS 12 or newer
- Apple Silicon host
- Swift toolchain
- Virtualization.framework entitlement when running the signed release binary

## Build

```sh
swift build
```

For the release binary used by the Makefile:

```sh
make build
make sign
```

By default, `make sign` uses ad-hoc signing with `SIGN_IDENTITY=-` and the entitlements in `vmm.entitlements`.

## Usage

```sh
vmm run [--pid-file <path>] [--socket <path>] <config.json>
```

During development, run through SwiftPM:

```sh
swift run vmm run test.json
```

Run the signed release binary:

```sh
make run
```

Use a different config with:

```sh
make run CONFIG=/path/to/config.json
```

## PID File

Pass `--pid-file` to write the running `vmm` process ID to a file:

```sh
vmm run --pid-file /tmp/vmm.pid test.json
```

The file is removed when `vmm` exits cleanly, including after a handled `SIGTERM`.

## Unix Socket Console

By default, the VM console is attached to the current terminal using stdin/stdout.

Pass `--socket` to expose console input and output over a Unix socket instead:

```sh
vmm run --socket /tmp/vmm.sock test.json
```

The VM remains running if a socket client disconnects. A later client can reconnect to the same socket path. Output produced while no client is connected is discarded.

Example client:

```sh
nc -U /tmp/vmm.sock
```

The socket file is removed when `vmm` exits.

## Shutdown

Send `SIGTERM` to the `vmm` process to shut down the VM:

```sh
kill -TERM "$(cat /tmp/vmm.pid)"
```

On `SIGTERM`, `vmm` asks the VM to stop gracefully with `requestStop()`. If the guest has not stopped within 30 seconds, `vmm` forces the VM to stop.

## Configuration

The config file is JSON:

```json
{
  "cpuCount": 2,
  "memoryMB": 2048,
  "kernel": "assets/ubuntu-resolute-arm64/Image",
  "initrd": "assets/ubuntu-resolute-arm64/initrd.img",
  "disk": "assets/ubuntu-resolute-arm64/root.squashfs",
  "diskReadOnly": true,
  "extraDisks": [
    {
      "path": "assets/ubuntu-resolute-arm64/overlay.raw",
      "readOnly": false
    },
    {
      "path": "assets/ubuntu-resolute-arm64/seed.iso",
      "readOnly": true
    }
  ],
  "cmdline": "console=hvc0 root=/dev/vda rootfstype=squashfs ro"
}
```

Relative paths are resolved relative to the config file location.

## Make Targets

```sh
make build    # Build release binary
make sign     # Sign release binary with Virtualization entitlement
make run      # Sign and run CONFIG, defaulting to test.json
make smoke    # Run basic CLI smoke tests
make clean    # Clean SwiftPM build output
```

## Tests

Basic checks:

```sh
swift build
swift run vmm --help
swift run vmm run --help
make smoke
```
