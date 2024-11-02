# 🖼️ Wifi Display Networking Setup

Bluetooth GATT Server to accept Wifi Credentials

## Getting Started

If you're on NixOS, the development environment will be initialized as soon as
you `cd` into the directory. Ensure you've run `direnv allow` once in the
projects root directory. Alternatively, you can run `nix develop`.

From there you should have the correct version of Rust, pkg-config, etc.

1. To compile the project for your x86_64 host machine:

```bash
nix build .#wifi-setup
```

2. To cross-compile for aarch64, i.e. a Raspberry Pi with an arm64 CPU:

```bash
nix build .#wifi-setup-aarch64
```

## Deployment

To deploy the project on a Raspberry Pi, you'll need the following items:

- A systemd service (see `systemd/wifi-setup.service`)
- Bluetooth packages installed (`bluez` and `bluetooth`)
- The binary compiled for aarch64 (see above)

Alternatively, on NixOS you can use the deployment script found in the
`flake.nix`. This will build the binary, copy it to your target and create the systemd service there for you.

```bash
nix run . -- pi@your-pi-hostname.local
```

## Debugging

On the Pi, you can check the logs of the service

```bash
# Check status
sudo systemctl status wifi-setup

# Follow logs
journalctl -u wifi-setup -f
```

In addition, you can check the status of the Bluetooth device and underlying
software.

```bash
# Open interactive bluetooth repl
sudo bluetoothctl
show
power on # If powered off, turn on the bluetooth device
```

## License

MIT
