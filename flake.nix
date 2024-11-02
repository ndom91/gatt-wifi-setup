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
   flake-utils.lib.eachSystem [ "x86_64-linux" ] (system:
      let
        overlays = [ (import rust-overlay) ];
        pkgs = import nixpkgs {
          inherit system overlays;
        };

        # Cross compilation target
        crossSystem = {
          config = "aarch64-unknown-linux-gnu";
          system = "aarch64-linux";
          libc = "glibc";
        };

        # Cross pkgs
        pkgsCross = import nixpkgs {
          inherit system overlays;
          crossSystem = crossSystem;
        };

        # Rust toolchain with cross-compilation support
        rustToolchain = pkgs.rust-bin.stable.latest.default.override {
          targets = [ "aarch64-unknown-linux-gnu" ];
        };

        # Native build inputs (tools that run on the build system)
        nativeBuildInputs = with pkgs; [
          rustToolchain
          pkg-config
          pkgsCross.stdenv.cc
        ];

        # Build inputs (libraries that need to be available during compilation)
        buildInputs = with pkgsCross; [
          dbus.dev
          udev.dev
          bluez
          openssl.dev
        ];

      in
      {
        packages.default = pkgsCross.stdenv.mkDerivation {
          name = "wifi-setup";
          src = ./.;

           # Add cargo dependencies hash
  # cargoLock = {
  #   lockFile = ./Cargo.lock;
  # };

  # Add this to fetch dependencies before build
  cargoDeps = pkgs.rustPlatform.importCargoLock {
    lockFile = ./Cargo.lock;
  };


          nativeBuildInputs = nativeBuildInputs;
          buildInputs = buildInputs;


          # Create a cargo config for cross compilation
          preConfigure = ''
            mkdir -p .cargo
            cat > .cargo/config.toml << EOF
            [target.aarch64-unknown-linux-gnu]
            linker = "aarch64-unknown-linux-gnu-gcc"
            rustflags = [
              "-C", "link-arg=-L${pkgsCross.dbus}/lib",
              "-C", "link-arg=-L${pkgsCross.udev}/lib",
              "-C", "link-arg=-L${pkgsCross.bluez}/lib",
              "-C", "link-arg=-L${pkgsCross.openssl.out}/lib",
            ]

            [build]
            target = "aarch64-unknown-linux-gnu"
            EOF
          '';


          # Build the project
          buildPhase = ''
            cargo build --target aarch64-unknown-linux-gnu --release
          '';

          # Install the binary
          installPhase = ''
            mkdir -p $out/bin
            cp target/aarch64-unknown-linux-gnu/release/wifi-setup $out/bin/
          '';

         PKG_CONFIG_ALL_STATIC = "1";
          PKG_CONFIG_ALLOW_CROSS = "1";
          PKG_CONFIG_PATH = with pkgsCross; lib.makeSearchPath "lib/pkgconfig" [
            dbus.dev
            udev.dev
            bluez
            openssl.dev
          ];
          # Use the cross-compiled stdenv path instead of targetSysroot
          PKG_CONFIG_SYSROOT_DIR = "${pkgsCross.stdenv.cc}/aarch64-unknown-linux-gnu";


          # Set environment variables for pkg-config
          # PKG_CONFIG_PATH = with pkgsCross; lib.makeSearchPath "lib/pkgconfig" [
          #   dbus.dev
          #   udev.dev
          #   bluez
          #   openssl.dev
          # ];
          # PKG_CONFIG_SYSROOT_DIR = pkgsCross.stdenv.cc.targetSysroot;
          # PKG_CONFIG_ALLOW_CROSS = "1";
        };

        # Development shell
        devShells.default = pkgs.mkShell {
          buildInputs = nativeBuildInputs ++ (with pkgs; [
            pkg-config
            dbus.dev
            udev.dev
            bluez
          ]);

          shellHook = ''
            # Setup Rust environment
            export RUST_SRC_PATH=${rustToolchain}/lib/rustlib/src/rust/library

            # PKG config for cross compilation
            export PKG_CONFIG_ALLOW_CROSS=1
            export PKG_CONFIG_PATH="${pkgsCross.dbus.dev}/lib/pkgconfig:${pkgsCross.udev.dev}/lib/pkgconfig"
            export PKG_CONFIG_SYSROOT_DIR="/run/current-system"

            echo "Cross-compilation development environment ready!"
          '';
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
            scp ${self.packages.${system}.default}/bin/wifi-setup $PI_HOST:$PI_PATH/

            # Update example systemd service file
            cp systemd/wifi-setup.service.example systemd/wifi-setup.service
            sed -i 's|ExecStart=/path/to/wifi-setup|ExecStart=$PI_PATH/wifi-setup|g' systemd/wifi-setup.service

            # Copy service file
            scp systemd/wifi-setup.service $PI_HOST:/tmp/
            rm systemd/wifi-setup.service

            ssh $PI_HOST "sudo mv /tmp/wifi-setup.service /etc/systemd/system/ && \
                         sudo systemctl daemon-reload && \
                         sudo systemctl enable wifi-setup && \
                         sudo systemctl restart wifi-setup"

            echo "Deployment complete!"
          '';
        };
      });
    # flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" ] (system:
    #   let
    #     overlays = [ (import rust-overlay) ];
    #     pkgs = import nixpkgs {
    #       inherit system overlays;
    #     };
    #
    #     # Common dependencies
    #     commonBuildInputs = with pkgs; [
    #       pkg-config
    #       dbus.dev
    #       udev.dev
    #       bluez
    #       openssl.dev
    #     ];
    #
    #     # Rust toolchain with cross-compilation support
    #     rustToolchain = pkgs.rust-bin.stable.latest.default.override {
    #       targets = [ "aarch64-unknown-linux-gnu" ];
    #     };
    #
    #     # Build for current platform
    #     nativeBuildInputs = with pkgs; [
    #       rustToolchain
    #       clippy
    #       rust-analyzer
    #       rustfmt
    #     ] ++ commonBuildInputs;
    #
    #     # Cross compilation settings for Raspberry Pi Zero 2 W
    #     aarch64Pkgs = import nixpkgs {
    #       system = "x86_64-linux";
    #       crossSystem = {
    #         config = "aarch64-unknown-linux-gnu";
    #         system = "aarch64-linux";
    #       };
    #     };
    #
    #     crossBuildInputs = with aarch64Pkgs; [
    #       pkg-config
    #       dbus.dev
    #       udev.dev
    #       bluez
    #       openssl.dev
    #     ];
    #
    #   in
    #   {
    #     # Development shell
    #     devShells.default = pkgs.mkShell {
    #       # buildInputs = nativeBuildInputs;
    #       buildInputs = nativeBuildInputs ++ (with pkgs; [
    #         pkg-config
    #         dbus.dev
    #         udev.dev
    #         bluez
    #       ]);
    #
    #       shellHook = ''
    #         # Setup Rust environment
    #         export RUST_SRC_PATH=${rustToolchain}/lib/rustlib/src/rust/library
    #
    #         # PKG config for native build
    #         export PKG_CONFIG_PATH="${pkgs.dbus.dev}/lib/pkgconfig:${pkgs.udev.dev}/lib/pkgconfig"
    #
    #         # For cross-compilation
    #         export PKG_CONFIG_ALLOW_CROSS=1
    #         export PKG_CONFIG_SYSROOT_DIR="/run/current-system"
    #
    #
    #         echo "Rust development environment ready!"
    #       '';
    #     };
    #
    #     # Package definition
    #     packages = rec {
    #       # Native build
    #       wifi-setup = pkgs.rustPlatform.buildRustPackage {
    #         pname = "wifi-setup";
    #         version = "0.1.0";
    #         src = ./.;
    #
    #         buildInputs = commonBuildInputs;
    #         nativeBuildInputs = [ pkgs.pkg-config ];
    #
    #         # buildType = "debug";
    #
    #         cargoLock = {
    #           lockFile = ./Cargo.lock;
    #         };
    #       };
    #
    #       # Cross-compiled build for Raspberry Pi Zero 2 W
    #       wifi-setup-aarch64 = pkgs.rustPlatform.buildRustPackage {
    #         pname = "wifi-setup";
    #         version = "0.1.0";
    #         src = ./.;
    #
    #         buildInputs = crossBuildInputs;
    #         nativeBuildInputs = [ pkgs.pkg-config ];
    #
    #         # buildType = "debug";
    #
    #         CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER = "${pkgs.pkgsCross.aarch64-multiplatform.stdenv.cc}/bin/aarch64-unknown-linux-gnu-gcc";
    #         CARGO_BUILD_TARGET = "aarch64-unknown-linux-gnu";
    #
    #         cargoLock = {
    #           lockFile = ./Cargo.lock;
    #         };
    #       };
    #
    #       default = wifi-setup;
    #     };
    #
    #     # Deployment script
    #     apps.default = flake-utils.lib.mkApp {
    #       drv = pkgs.writeScriptBin "deploy-wifi-setup" ''
    #         #!${pkgs.stdenv.shell}
    #
    #         PI_HOST="''${1:-domino-display}"
    #         PI_PATH="/opt/display/"
    #
    #         echo "Deploying to $PI_HOST..."
    #
    #         # Ensure target directory exists
    #         ssh $PI_HOST "mkdir -p $PI_PATH"
    #
    #         # Copy binary
    #         scp ${self.packages.${system}.wifi-setup-aarch64}/bin/wifi-setup $PI_HOST:$PI_PATH/
    #
    #         # Update example systemd service file
    #         cp systemd/wifi-setup.service.example systemd/wifi-setup.service
    #         sed -i 's|ExecStart=/path/to/wifi-setup|ExecStart=$PI_PATH/wifi-setup|g' systemd/wifi-setup.service
    #
    #         # Copy service file
    #         scp systemd/wifi-setup.service $PI_HOST:/tmp/
    #         rm systemd/wifi-setup.service
    #
    #         ssh $PI_HOST "sudo mv /tmp/wifi-setup.service /etc/systemd/system/ && \
    #                      sudo systemctl daemon-reload && \
    #                      sudo systemctl enable wifi-setup && \
    #                      sudo systemctl restart wifi-setup"
    #
    #         echo "Deployment complete!"
    #       '';
    #     };
    #   });
}
