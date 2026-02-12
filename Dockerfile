FROM debian:12

ENV DEBIAN_FRONTEND=noninteractive

# Step 1: apt dependencies
RUN apt-get update && apt-get install -y \
    build-essential git wget curl lhasa libgmp-dev libmpfr-dev libmpc-dev \
    flex bison gettext texinfo libncurses-dev autoconf rsync libreadline-dev \
    gcc-m68k-linux-gnu g++-m68k-linux-gnu \
    && rm -rf /var/lib/apt/lists/*

# Step 2: Node.js 22
ARG NODE_VERSION=22.22.0
RUN wget -q "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz" -O /tmp/node.tar.xz \
    && mkdir -p /opt/node \
    && tar xf /tmp/node.tar.xz -C /opt/node --strip-components=1 \
    && rm /tmp/node.tar.xz
ENV PATH="/opt/node/bin:$PATH"

# Step 3: Build bebbo's amiga-gcc
RUN cd /tmp \
    && git clone https://github.com/bebbo/amiga-gcc.git \
    && cd amiga-gcc \
    && make update \
    && make all -j"$(nproc)" PREFIX=/opt/amiga \
    && rm -rf /tmp/amiga-gcc

# Step 4a: Build Lydux human68k-gcc (4.6.2)
RUN cd /tmp \
    && git clone -b gcc-4.6.2 https://github.com/erique/human68k-gcc.git human68k-gcc-lydux \
    && cd human68k-gcc-lydux \
    && make min -j"$(nproc)" PREFIX=/opt/toolchains/x68k \
    && rm -rf /tmp/human68k-gcc-lydux

# Step 4b: Build human68k-gcc (6.5.0b)
RUN cd /tmp \
    && git clone -b gcc-6.5.0 https://github.com/erique/human68k-gcc.git human68k-gcc-650b \
    && cd human68k-gcc-650b \
    && make min -j"$(nproc)" PREFIX=/opt/toolchains/human68k \
    && rm -rf /tmp/human68k-gcc-650b

# Step 5: Download elf2x68k
ARG ELF2X68K_TAG=20251124
RUN wget -q "https://github.com/yunkya2/elf2x68k/releases/download/${ELF2X68K_TAG}/elf2x68k-Linux-${ELF2X68K_TAG}.tar.bz2" -O /tmp/elf2x68k.tar.bz2 \
    && mkdir -p /opt/elf2x68k \
    && tar xf /tmp/elf2x68k.tar.bz2 -C /opt/elf2x68k --strip-components=1 \
    && rm /tmp/elf2x68k.tar.bz2

# Copy repo
RUN useradd -m -s /bin/bash cex
COPY --chown=cex:cex . /home/cex/cex

# Clone CE fork and install deps
USER cex
WORKDIR /home/cex/cex
RUN git clone https://github.com/erique/compiler-explorer.git

# Copy config and examples into CE
RUN cp config/c.local.properties compiler-explorer/etc/config/ \
    && cp config/c++.local.properties compiler-explorer/etc/config/ \
    && cp -a examples/c/ compiler-explorer/examples/c/ \
    && cp -a examples/c++/ compiler-explorer/examples/c++/

# Install CE dependencies and build
RUN cd compiler-explorer && npm ci
RUN cd compiler-explorer && make prebuild

EXPOSE 10240
CMD ["./run.sh"]
