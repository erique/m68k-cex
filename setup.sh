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
# Step 2: Create cex user and prepare prefix directories
# ---------------------------------------------------------------------------
echo "=== Step 2: Creating cex user and prefix directories ==="
if ! id "$CEX_USER" >/dev/null 2>&1; then
    useradd -m -s /bin/bash "$CEX_USER"
fi

mkdir -p /opt/node /opt/amiga /opt/toolchains/x68k /opt/toolchains/human68k /opt/elf2x68k
chown "$CEX_USER:$CEX_USER" /opt/amiga /opt/toolchains /opt/toolchains/x68k /opt/toolchains/human68k /opt/elf2x68k

# ---------------------------------------------------------------------------
# Step 3: Node.js 22
# ---------------------------------------------------------------------------
echo "=== Step 3: Installing Node.js $NODE_VERSION ==="
if [ ! -x /opt/node/bin/node ]; then
    wget -q "$NODE_URL" -O "/tmp/$NODE_TARBALL"
    mkdir -p /opt/node
    tar xf "/tmp/$NODE_TARBALL" -C /opt/node --strip-components=1
    rm "/tmp/$NODE_TARBALL"
fi
/opt/node/bin/node --version

# ---------------------------------------------------------------------------
# Step 4: Build bebbo's amiga-gcc
# ---------------------------------------------------------------------------
echo "=== Step 4: Building amiga-gcc (this takes a while) ==="
if [ ! -x /opt/amiga/bin/m68k-amigaos-gcc ]; then
    su - "$CEX_USER" -c "cd /tmp && \
        ([ -d amiga-gcc ] || git clone https://github.com/erique/amiga-gcc.git) && \
        cd amiga-gcc && make update && make all -j$(nproc) PREFIX=/opt/amiga"
fi
/opt/amiga/bin/m68k-amigaos-gcc --version | head -1

# ---------------------------------------------------------------------------
# Step 5a: Build Lydux human68k-gcc (4.6.2)
# ---------------------------------------------------------------------------
echo "=== Step 5a: Building Lydux human68k-gcc 4.6.2 (this takes a while) ==="
if [ ! -x /opt/toolchains/x68k/bin/human68k-gcc ]; then
    su - "$CEX_USER" -c "cd /tmp && \
        ([ -d human68k-gcc-lydux ] || git clone -b gcc-4.6.2 https://github.com/erique/human68k-gcc.git human68k-gcc-lydux) && \
        cd human68k-gcc-lydux && make min -j$(nproc) PREFIX=/opt/toolchains/x68k"
fi
/opt/toolchains/x68k/bin/human68k-gcc --version | head -1

# ---------------------------------------------------------------------------
# Step 5b: Build human68k-gcc (6.5.0b)
# ---------------------------------------------------------------------------
echo "=== Step 5b: Building human68k-gcc 6.5.0b (this takes a while) ==="
if [ ! -x /opt/toolchains/human68k/bin/m68k-human68k-gcc-6.5.0b ]; then
    su - "$CEX_USER" -c "cd /tmp && \
        ([ -d human68k-gcc-650b ] || git clone -b gcc-6.5.0 https://github.com/erique/human68k-gcc.git human68k-gcc-650b) && \
        cd human68k-gcc-650b && make min -j$(nproc) PREFIX=/opt/toolchains/human68k"
fi
/opt/toolchains/human68k/bin/m68k-human68k-gcc-6.5.0b --version | head -1

# ---------------------------------------------------------------------------
# Step 6: Download elf2x68k
# ---------------------------------------------------------------------------
echo "=== Step 6: Installing elf2x68k ==="
if [ ! -x /opt/elf2x68k/bin/m68k-xelf-gcc ]; then
    wget -q "$ELF2X68K_URL" -O "/tmp/elf2x68k.tar.bz2"
    tar xf "/tmp/elf2x68k.tar.bz2" -C /opt/elf2x68k --strip-components=1
    chown -R "$CEX_USER:$CEX_USER" /opt/elf2x68k
    rm "/tmp/elf2x68k.tar.bz2"
fi
/opt/elf2x68k/bin/m68k-xelf-gcc --version | head -1

# ---------------------------------------------------------------------------
# Step 7: Copy repo
# ---------------------------------------------------------------------------
echo "=== Step 7: Setting up cex repo ==="
if [ ! -d "$CEX_DIR" ]; then
    cp -a "$SCRIPT_DIR" "$CEX_DIR"
    chown -R "$CEX_USER:$CEX_USER" "$CEX_DIR"
fi

# ---------------------------------------------------------------------------
# Step 8: Clone CE fork
# ---------------------------------------------------------------------------
echo "=== Step 8: Cloning Compiler Explorer fork ==="
if [ ! -d "$CEX_DIR/compiler-explorer" ]; then
    su - "$CEX_USER" -c "git clone $CE_REPO $CEX_DIR/compiler-explorer"
fi

# ---------------------------------------------------------------------------
# Step 9: npm ci
# ---------------------------------------------------------------------------
echo "=== Step 9: Installing CE dependencies ==="
export PATH="/opt/node/bin:$PATH"
su - "$CEX_USER" -c "export PATH=/opt/node/bin:\$PATH && cd $CEX_DIR/compiler-explorer && npm ci"

# ---------------------------------------------------------------------------
# Step 10: Copy config files
# ---------------------------------------------------------------------------
echo "=== Step 10: Copying config files ==="
cp "$CEX_DIR/config/c.local.properties" "$CEX_DIR/compiler-explorer/etc/config/"
cp "$CEX_DIR/config/c++.local.properties" "$CEX_DIR/compiler-explorer/etc/config/"

# ---------------------------------------------------------------------------
# Step 11: Copy custom examples
# ---------------------------------------------------------------------------
echo "=== Step 11: Copying custom examples ==="
cp -a "$CEX_DIR/examples/c/" "$CEX_DIR/compiler-explorer/examples/c/"
cp -a "$CEX_DIR/examples/c++/" "$CEX_DIR/compiler-explorer/examples/c++/"

# ---------------------------------------------------------------------------
# Step 12: Build CE for production
# ---------------------------------------------------------------------------
echo "=== Step 12: Building CE (prebuild) ==="
su - "$CEX_USER" -c "export PATH=/opt/node/bin:\$PATH && cd $CEX_DIR/compiler-explorer && make prebuild"

# ---------------------------------------------------------------------------
# Step 13: Port 80 redirect
# ---------------------------------------------------------------------------
echo "=== Step 13: Setting up port 80 redirect ==="
if ! iptables -t nat -C PREROUTING -p tcp --dport 80 -j REDIRECT --to-port 10240 2>/dev/null; then
    iptables -t nat -A PREROUTING -p tcp --dport 80 -j REDIRECT --to-port 10240
fi
netfilter-persistent save

# ---------------------------------------------------------------------------
# Step 14: Install and start systemd service
# ---------------------------------------------------------------------------
echo "=== Step 14: Installing systemd service ==="
cp "$CEX_DIR/config/cex.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable cex
systemctl start cex

echo ""
echo "=== Setup complete ==="
echo "Compiler Explorer should be running on port 80."
echo "Check status: systemctl status cex"
echo "View logs:    journalctl -u cex -f"
