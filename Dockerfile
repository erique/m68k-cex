# Stage 1: Build dependencies (shared base for toolchain stages)
FROM debian:12 AS build-base
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y \
    build-essential git wget curl lhasa libgmp-dev libmpfr-dev libmpc-dev \
    flex bison gettext texinfo libncurses-dev autoconf rsync libreadline-dev expect \
    && rm -rf /var/lib/apt/lists/*

# Stage 2: Build bebbo's amiga-gcc
FROM build-base AS amiga-gcc
RUN cd /tmp \
    && git clone https://github.com/erique/amiga-gcc.git \
    && cd amiga-gcc \
    && make update \
    && make all -j"$(nproc)" PREFIX=/opt/amiga

# Stage 3: Build Lydux human68k-gcc (4.6.2)
FROM build-base AS human68k-lydux
RUN cd /tmp \
    && git clone -b gcc-4.6.2 https://github.com/erique/human68k-gcc.git \
    && cd human68k-gcc \
    && sh build_x68_gcc.sh

# Stage 4: Build human68k-gcc (6.5.0b)
FROM build-base AS human68k-650b
RUN cd /tmp \
    && git clone -b gcc-6.5.0 https://github.com/erique/human68k-gcc.git \
    && cd human68k-gcc \
    && make min -j"$(nproc)" PREFIX=/opt/toolchains/human68k

# Stage 5: Download elf2x68k
FROM debian:12 AS elf2x68k
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y wget bzip2 && rm -rf /var/lib/apt/lists/*
ARG ELF2X68K_TAG=20251124
RUN wget -q "https://github.com/yunkya2/elf2x68k/releases/download/${ELF2X68K_TAG}/elf2x68k-Linux-${ELF2X68K_TAG}.tar.bz2" -O /tmp/elf2x68k.tar.bz2 \
    && mkdir -p /opt/elf2x68k \
    && tar xf /tmp/elf2x68k.tar.bz2 -C /opt/elf2x68k --strip-components=1 \
    && rm /tmp/elf2x68k.tar.bz2

# Stage 6: Final image
FROM debian:12
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    git make gcc g++ wget xz-utils \
    gcc-m68k-linux-gnu g++-m68k-linux-gnu \
    && rm -rf /var/lib/apt/lists/*

# Node.js
ARG NODE_VERSION=22.22.0
RUN wget -q "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz" -O /tmp/node.tar.xz \
    && mkdir -p /opt/node \
    && tar xf /tmp/node.tar.xz -C /opt/node --strip-components=1 \
    && rm /tmp/node.tar.xz
ENV PATH="/opt/node/bin:$PATH"

# Copy toolchains from build stages
COPY --from=amiga-gcc /opt/amiga /opt/amiga
COPY --from=human68k-lydux /opt/toolchains/x68k /opt/toolchains/x68k
COPY --from=human68k-650b /opt/toolchains/human68k /opt/toolchains/human68k
COPY --from=elf2x68k /opt/elf2x68k /opt/elf2x68k

# Create user and copy repo
RUN useradd -m -s /bin/bash cex
COPY --chown=cex:cex . /home/cex/cex

USER cex
WORKDIR /home/cex/cex

# Clone CE fork
RUN git clone https://github.com/erique/compiler-explorer.git

# Copy config and examples into CE
RUN cp config/c.local.properties compiler-explorer/etc/config/ \
    && cp config/c++.local.properties compiler-explorer/etc/config/ \
    && cp -a examples/c/ compiler-explorer/examples/c/ \
    && cp -a examples/c++/ compiler-explorer/examples/c++/

# Install CE dependencies and build for production
RUN cd compiler-explorer && npm ci
RUN cd compiler-explorer && make prebuild

EXPOSE 10240
CMD ["./run.sh"]
