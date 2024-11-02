# 🖼️ Wifi Display Networking Setup

Bluetooth GATT Server to accept Wifi Credentials

## Develop

If you're on NixOS, run `direnv allow` once in the project's root directory.
From then on, the development environment will be initialized as soon as you
`cd` into the project's directory. Alternatively, you can run `nix develop`
manually. Now you should have the correct version of Rust, pkg-config, etc.
in your environment.

1. To run a development version of the project:

```
cargo run
```

## Build

1. To compile a release version of the project for your `x86_64` host machine:

```bash
nix build .#wifi-setup

# Alternatively
nix build
```

2. To cross-compile for `aarch64`, i.e. a Raspberry Pi

```bash
nix build .#wifi-setup-aarch64
```

## Deploy

To deploy the project on a Raspberry Pi, you'll need the following items:

- A systemd service (see `systemd/wifi-setup.service`)
- Bluetooth packages installed (`bluez` and `bluetooth`)
- The binary compiled for `aarch64` (see above)

Alternatively, on NixOS you can use the deployment script found in the
`flake.nix`. This will build the binary, copy it to your target and create the systemd service there for you.

```bash
nix run . -- pi@your-pi-hostname.local
```

## Debug

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
