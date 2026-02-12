#!/bin/sh
# CEX deployment setup — provisions a fresh Debian 12 VM
# Usage: sudo ./setup.sh
#
# Installs m68k cross-compilers and Compiler Explorer as a systemd service
# on port 80 (via iptables redirect from 80 -> 10240).

set -eu

if [ "$(id -u)" -ne 0 ]; then
    echo "Error: must run as root (sudo ./setup.sh)"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CEX_USER="cex"
CEX_HOME="/home/$CEX_USER"
CEX_DIR="$CEX_HOME/cex"

NODE_VERSION="22.22.0"
NODE_TARBALL="node-v${NODE_VERSION}-linux-x64.tar.xz"
NODE_URL="https://nodejs.org/dist/v${NODE_VERSION}/${NODE_TARBALL}"

ELF2X68K_TAG="20251124"
ELF2X68K_TARBALL="elf2x68k-Linux-${ELF2X68K_TAG}.tar.bz2"
ELF2X68K_URL="https://github.com/yunkya2/elf2x68k/releases/download/${ELF2X68K_TAG}/${ELF2X68K_TARBALL}"

CE_REPO="https://github.com/erique/compiler-explorer.git"

# ---------------------------------------------------------------------------
# Step 1: apt dependencies
# ---------------------------------------------------------------------------
echo "=== Step 1: Installing apt dependencies ==="
apt-get update
apt-get install -y \
    build-essential git wget curl lhasa libgmp-dev libmpfr-dev libmpc-dev \
    flex bison gettext texinfo libncurses-dev autoconf rsync libreadline-dev \
    gcc-m68k-linux-gnu g++-m68k-linux-gnu \
    iptables netfilter-persistent iptables-persistent

# ---------------------------------------------------------------------------
# Step 2: Node.js 22
# ---------------------------------------------------------------------------
echo "=== Step 2: Installing Node.js $NODE_VERSION ==="
if [ ! -x /opt/node/bin/node ]; then
    wget -q "$NODE_URL" -O "/tmp/$NODE_TARBALL"
    mkdir -p /opt/node
    tar xf "/tmp/$NODE_TARBALL" -C /opt/node --strip-components=1
    rm "/tmp/$NODE_TARBALL"
fi
/opt/node/bin/node --version

# ---------------------------------------------------------------------------
# Step 3: Build bebbo's amiga-gcc
# ---------------------------------------------------------------------------
echo "=== Step 3: Building amiga-gcc (this takes a while) ==="
if [ ! -x /opt/amiga/bin/m68k-amigaos-gcc ]; then
    cd /tmp
    if [ ! -d amiga-gcc ]; then
        git clone https://github.com/bebbo/amiga-gcc.git
    fi
    cd amiga-gcc
    make update
    make all -j"$(nproc)" PREFIX=/opt/amiga
fi
/opt/amiga/bin/m68k-amigaos-gcc --version | head -1

# ---------------------------------------------------------------------------
# Step 4: Build human68k-gcc
# ---------------------------------------------------------------------------
echo "=== Step 4: Building human68k-gcc (this takes a while) ==="
if [ ! -x /opt/human68k/bin/human68k-gcc ]; then
    cd /tmp
    if [ ! -d human68k-gcc ]; then
        git clone -b gcc-6.5.0 https://github.com/erique/human68k-gcc.git
    fi
    cd human68k-gcc
    make min -j"$(nproc)" PREFIX=/opt/human68k
fi
/opt/human68k/bin/human68k-gcc --version | head -1

# ---------------------------------------------------------------------------
# Step 5: Download elf2x68k
# ---------------------------------------------------------------------------
echo "=== Step 5: Installing elf2x68k ==="
if [ ! -x /opt/elf2x68k/bin/m68k-xelf-gcc ]; then
    wget -q "$ELF2X68K_URL" -O "/tmp/$ELF2X68K_TARBALL"
    mkdir -p /opt/elf2x68k
    tar xf "/tmp/$ELF2X68K_TARBALL" -C /opt/elf2x68k --strip-components=1
    rm "/tmp/$ELF2X68K_TARBALL"
fi
/opt/elf2x68k/bin/m68k-xelf-gcc --version | head -1

# ---------------------------------------------------------------------------
# Step 6: Create cex user and clone repo
# ---------------------------------------------------------------------------
echo "=== Step 6: Setting up cex user and repo ==="
if ! id "$CEX_USER" >/dev/null 2>&1; then
    useradd -m -s /bin/bash "$CEX_USER"
fi

if [ ! -d "$CEX_DIR" ]; then
    cp -a "$SCRIPT_DIR" "$CEX_DIR"
    chown -R "$CEX_USER:$CEX_USER" "$CEX_DIR"
fi

# ---------------------------------------------------------------------------
# Step 7: Clone CE fork
# ---------------------------------------------------------------------------
echo "=== Step 7: Cloning Compiler Explorer fork ==="
if [ ! -d "$CEX_DIR/compiler-explorer" ]; then
    su - "$CEX_USER" -c "git clone $CE_REPO $CEX_DIR/compiler-explorer"
fi

# ---------------------------------------------------------------------------
# Step 8: npm ci
# ---------------------------------------------------------------------------
echo "=== Step 8: Installing CE dependencies ==="
export PATH="/opt/node/bin:$PATH"
su - "$CEX_USER" -c "export PATH=/opt/node/bin:\$PATH && cd $CEX_DIR/compiler-explorer && npm ci"

# ---------------------------------------------------------------------------
# Step 9: Copy config files
# ---------------------------------------------------------------------------
echo "=== Step 9: Copying config files ==="
cp "$CEX_DIR/config/c.local.properties" "$CEX_DIR/compiler-explorer/etc/config/"
cp "$CEX_DIR/config/c++.local.properties" "$CEX_DIR/compiler-explorer/etc/config/"

# ---------------------------------------------------------------------------
# Step 10: Copy custom examples
# ---------------------------------------------------------------------------
echo "=== Step 10: Copying custom examples ==="
cp -a "$CEX_DIR/examples/c/" "$CEX_DIR/compiler-explorer/examples/c/"
cp -a "$CEX_DIR/examples/c++/" "$CEX_DIR/compiler-explorer/examples/c++/"

# ---------------------------------------------------------------------------
# Step 11: Build CE for production
# ---------------------------------------------------------------------------
echo "=== Step 11: Building CE (prebuild) ==="
su - "$CEX_USER" -c "export PATH=/opt/node/bin:\$PATH && cd $CEX_DIR/compiler-explorer && make prebuild"

# ---------------------------------------------------------------------------
# Step 12: Port 80 redirect
# ---------------------------------------------------------------------------
echo "=== Step 12: Setting up port 80 redirect ==="
if ! iptables -t nat -C PREROUTING -p tcp --dport 80 -j REDIRECT --to-port 10240 2>/dev/null; then
    iptables -t nat -A PREROUTING -p tcp --dport 80 -j REDIRECT --to-port 10240
fi
netfilter-persistent save

# ---------------------------------------------------------------------------
# Step 13: Install and start systemd service
# ---------------------------------------------------------------------------
echo "=== Step 13: Installing systemd service ==="
cp "$CEX_DIR/config/cex.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable cex
systemctl start cex

echo ""
echo "=== Setup complete ==="
echo "Compiler Explorer should be running on port 80."
echo "Check status: systemctl status cex"
echo "View logs:    journalctl -u cex -f"
