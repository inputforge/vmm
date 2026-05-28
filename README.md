# vmm

`vmm` is a small macOS Virtualization.framework runner for Linux VMs. It boots a VM from a JSON configuration, supports optional PID-file management, can expose the VM console over a Unix socket, and handles `SIGTERM` by requesting a graceful guest shutdown before forcing a stop.

## Requirements

- macOS 13 or newer
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
swift run vmm run examples/linux.json
```

Run the signed release binary:

```sh
make run
```

Use a different config with:

```sh
make run CONFIG=examples/efi.json
```

## PID File

Pass `--pid-file` to write the running `vmm` process ID to a file:

```sh
vmm run --pid-file /tmp/vmm.pid examples/linux.json
```

The file is removed when `vmm` exits cleanly, including after a handled `SIGTERM`.

## Unix Socket Console

By default, the VM console is attached to the current terminal using stdin/stdout.

Pass `--socket` to expose console input and output over a Unix socket instead:

```sh
vmm run --socket /tmp/vmm.sock examples/linux.json
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

Config files live in `examples/`. Relative paths inside a config are resolved relative to the config file's directory.

### Linux direct-boot (`examples/linux.json`)

```json
{
  "bootMode": "linux",
  "cpuCount": 2,
  "memoryMB": 2048,
  "kernel": "assets/ubuntu-resolute-arm64/vmlinux",
  "initrd": "assets/ubuntu-resolute-arm64/initrd.img",
  "disk": "assets/ubuntu-resolute-arm64/root.squashfs",
  "diskReadOnly": true,
  "extraDisks": [
    { "path": "assets/ubuntu-resolute-arm64/overlay.raw", "readOnly": false },
    { "path": "assets/ubuntu-resolute-arm64/seed.iso",    "readOnly": true  }
  ],
  "cmdline": "console=hvc0 root=/dev/vda rootfstype=squashfs ro overlayroot=crypt:dev=/dev/vdb,mkfs=1,timeout=30 ds=nocloud"
}
```

| Field | Description |
|---|---|
| `bootMode` | `"linux"` — direct kernel boot |
| `cpuCount` | Number of vCPUs |
| `memoryMB` | RAM in MiB |
| `kernel` | Path to uncompressed kernel image |
| `initrd` | Path to initrd (optional) |
| `cmdline` | Kernel command line |
| `disk` | Primary virtio-blk disk |
| `diskReadOnly` | Mount primary disk read-only (default `false`) |
| `extraDisks` | Additional virtio-blk disks, each with `path` and `readOnly` |

### EFI boot (`examples/efi.json`)

```json
{
  "bootMode": "efi",
  "cpuCount": 2,
  "memoryMB": 4096,
  "disk": "assets/ubuntu-efi/disk.raw",
  "stateDir": "assets/ubuntu-efi/state"
}
```

| Field | Description |
|---|---|
| `bootMode` | `"efi"` — EFI firmware boot |
| `cpuCount` | Number of vCPUs |
| `memoryMB` | RAM in MiB |
| `disk` | Primary virtio-blk disk |
| `stateDir` | Directory for EFI NVRAM and machine-id state |

## Disk Utilities

```sh
vmm disk <subcommand>
```

| Subcommand | Description |
|---|---|
| `convert <input.qcow2> <output.raw>` | Convert a QCOW2 image to raw |
| `create <path> <size>` | Create a new sparse raw image (`10G`, `512M`, `1T`, …) |
| `resize <path> <size>` | Grow or shrink a raw image (warns before shrinking) |
| `info <path>` | Print format, virtual size, and disk usage |
| `clone <src> <dst>` | Copy-on-write clone on APFS, full copy otherwise |

## Make Targets

```sh
make build    # Build release binary
make sign     # Sign release binary with Virtualization entitlement
make run      # Sign and run CONFIG (default: examples/linux.json)
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
