image := "debian:13"
packages := "packages.txt"

default: build

# Build the offline package tarball inside a debian:13 container.
build:
    #!/usr/bin/env bash
    set -euo pipefail
    HOST_UID=$(id -u)
    HOST_GID=$(id -g)
    echo "Starting docker container"
    docker run --rm \
        -v "$PWD:/work" \
        -w /work \
        -e HOST_UID="$HOST_UID" \
        -e HOST_GID="$HOST_GID" \
        {{image}} \
        bash -c '
            set -euo pipefail
            printf "%s\n" \
                "deb https://cloudfront.debian.net/debian/ trixie main contrib" \
                "deb https://cloudfront.debian.net/debian-security/ trixie-security main contrib" \
                "deb https://cloudfront.debian.net/debian/ trixie-updates main contrib" \
                > /etc/apt/sources.list
            chmod +x ./build_offline_packages.sh
            ./build_offline_packages.sh -f {{packages}}
            chown -R "$HOST_UID:$HOST_GID" local_packages local_packages.tar.gz
        '

# Build the offline package tarball directly on the host (must be Debian 13).
build-host:
    #!/usr/bin/env bash
    set -euo pipefail
    chmod +x ./build_offline_packages.sh
    sudo ./build_offline_packages.sh -f {{packages}}
    sudo chown -R "$(id -u):$(id -g)" local_packages local_packages.tar.gz

# Build age-plugin-yubikey .deb from the upstream crates.io crate.
# Usage: just build-age-plugin-yubikey 0.5.1
build-age-plugin-yubikey VERSION:
    #!/usr/bin/env bash
    set -euo pipefail
    HOST_UID=$(id -u)
    HOST_GID=$(id -g)
    echo "Building age-plugin-yubikey {{VERSION}} in {{image}}"
    docker run --rm \
        -v "$PWD:/work" \
        -w /work \
        -e HOST_UID="$HOST_UID" \
        -e HOST_GID="$HOST_GID" \
        -e VERSION="{{VERSION}}" \
        {{image}} \
        bash -c '
            set -euo pipefail
            apt-get update
            DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
                ca-certificates curl build-essential pkg-config \
                libpcsclite-dev libssl-dev \
                rustc cargo
            cargo install cargo-deb --locked --version 2.12.1
            export PATH="/root/.cargo/bin:$PATH"
            workdir=$(mktemp -d)
            cd "$workdir"
            curl -fsSL "https://crates.io/api/v1/crates/age-plugin-yubikey/${VERSION}/download" \
                -o age-plugin-yubikey.crate
            tar xzf age-plugin-yubikey.crate
            cd "age-plugin-yubikey-${VERSION}"
            cargo build --release --locked
            cargo run --example generate-docs
            cargo deb --no-build
            cp target/debian/*.deb /work/
            chown "$HOST_UID:$HOST_GID" /work/age-plugin-yubikey_*.deb
        '

# Remove generated artifacts.
clean:
    rm -rf local_packages local_packages.tar.gz

# Drop into an interactive debian:13 shell with the workdir mounted.
shell:
    docker run --rm -it -v "$PWD:/work" -w /work {{image}} bash
