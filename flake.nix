{
  description = "Bluetooth LE WiFi Setup Service";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, rust-overlay, flake-utils }:
    flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" ] (system:
      let
        overlays = [ (import rust-overlay) ];
        pkgs = import nixpkgs {
          inherit system overlays;
        };

        # Common dependencies
        commonBuildInputs = with pkgs; [
          pkg-config
          dbus.dev
          udev.dev
          bluez
          openssl.dev
        ];

        # Rust toolchain with cross-compilation support
        rustToolchain = pkgs.rust-bin.stable.latest.default.override {
          targets = [ "aarch64-unknown-linux-gnu" ];
        };

        # Build for current platform
        nativeBuildInputs = with pkgs; [
          rustToolchain
          clippy
          rust-analyzer
          rustfmt
        ] ++ commonBuildInputs;

        # Cross compilation settings for Raspberry Pi Zero 2 W
        aarch64Pkgs = import nixpkgs {
          system = "x86_64-linux";
          crossSystem = {
            config = "aarch64-unknown-linux-gnu";
            system = "aarch64-linux";
          };
        };

        crossBuildInputs = with aarch64Pkgs; [
          pkg-config
          dbus.dev
          udev.dev
          bluez
          openssl.dev
        ];

      in
      {
        # Development shell
        devShells.default = pkgs.mkShell {
          buildInputs = nativeBuildInputs;

          shellHook = ''
            # Setup Rust environment
            export RUST_SRC_PATH=${rustToolchain}/lib/rustlib/src/rust/library

            # PKG config for native build
            export PKG_CONFIG_PATH="${pkgs.dbus.dev}/lib/pkgconfig:${pkgs.udev.dev}/lib/pkgconfig"

            # For cross-compilation
            export PKG_CONFIG_ALLOW_CROSS=1
            export PKG_CONFIG_SYSROOT_DIR="/run/current-system"

            echo "Rust development environment ready!"
          '';
        };

        # Package definition
        packages = rec {
          # Native build
          wifi-setup = pkgs.rustPlatform.buildRustPackage {
            pname = "wifi-setup";
            version = "0.1.0";
            src = ./.;

            buildInputs = commonBuildInputs;
            nativeBuildInputs = [ pkgs.pkg-config ];

            cargoLock = {
              lockFile = ./Cargo.lock;
            };
          };

          # Cross-compiled build for Raspberry Pi Zero 2 W
          wifi-setup-aarch64 = pkgs.rustPlatform.buildRustPackage {
            pname = "wifi-setup";
            version = "0.1.0";
            src = ./.;

            buildInputs = crossBuildInputs;
            nativeBuildInputs = [ pkgs.pkg-config ];

            CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER = "${pkgs.pkgsCross.aarch64-multiplatform.stdenv.cc}/bin/aarch64-unknown-linux-gnu-gcc";
            CARGO_BUILD_TARGET = "aarch64-unknown-linux-gnu";

            cargoLock = {
              lockFile = ./Cargo.lock;
            };
          };

          default = wifi-setup;
        };

        # Deployment script
        apps.default = flake-utils.lib.mkApp {
          drv = pkgs.writeScriptBin "deploy-wifi-setup" ''
            #!${pkgs.stdenv.shell}

            PI_HOST="''${1:-domino-display}"
            PI_PATH="/opt/display/"

            echo "Deploying to $PI_HOST..."

            # Ensure target directory exists
            ssh $PI_HOST "mkdir -p $PI_PATH"

            # Copy binary
            scp ${self.packages.${system}.wifi-setup-aarch64}/bin/wifi-setup $PI_HOST:$PI_PATH/

            # Create and copy systemd service
            cat > wifi-setup.service << EOF
            [Unit]
            Description=BLE WiFi Setup Service
            After=bluetooth.target
            StartLimitIntervalSec=0

            [Service]
            Type=simple
            Restart=always
            RestartSec=1
            User=root
            ExecStart=$PI_PATH/wifi-setup

            [Install]
            WantedBy=multi-user.target
            EOF

            scp wifi-setup.service $PI_HOST:/tmp/
            ssh $PI_HOST "sudo mv /tmp/wifi-setup.service /etc/systemd/system/ && \
                         sudo systemctl daemon-reload && \
                         sudo systemctl enable wifi-setup && \
                         sudo systemctl restart wifi-setup"

            echo "Deployment complete!"
          '';
        };
      });
}
