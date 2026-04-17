# ===============================
# Stage 1: Build C++ core + JS (sdkjs + web-apps) via build_tools
#   Patches: BinaryWriterD.cpp / BinaryReaderD.cpp for Thai Distributed alignment
#   NOTE: This stage downloads Qt (~700MB) from ONLYOFFICE servers and compiles the
#         full server C++ core (~30-60 min). Docker layer caching means it only
#         re-runs when build_tools/ or core/ changes.
# ===============================
FROM ubuntu:24.04 AS builder

ENV TZ=Etc/UTC
ENV DEBIAN_FRONTEND=noninteractive

# Use Thai mirror (KKU) for faster apt downloads
RUN sed -i 's|http://archive.ubuntu.com/ubuntu|http://mirror.kku.ac.th/ubuntu|g' /etc/apt/sources.list.d/ubuntu.sources && \
    sed -i 's|http://security.ubuntu.com/ubuntu|http://mirror.kku.ac.th/ubuntu|g' /etc/apt/sources.list.d/ubuntu.sources

RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone && \
    apt-get -y update && \
    apt-get -y install --no-install-recommends \
        sudo git git-lfs curl wget p7zip-full \
        default-jre-headless ca-certificates gnupg && \
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get -y install --no-install-recommends nodejs && \
    npm install -g grunt-cli && \
    rm -rf /var/lib/apt/lists/*

# Build environment setup (each step is cached independently)
COPY build_tools/ /build/build_tools/
WORKDIR /build/build_tools

RUN cd tools/linux && ./python.sh
RUN cd tools/linux && ./python3/bin/python3 ./qt_binary_fetch.py amd64

# Replace sudo binary with passthrough wrapper (already root in Docker)
RUN echo '#!/bin/sh' > /usr/bin/sudo && \
    echo 'exec "$@"' >> /usr/bin/sudo && \
    chmod +x /usr/bin/sudo

# Run system dependency installer (uses sudo apt-get internally)
RUN apt-get -y update && \
    cd tools/linux && ./python3/bin/python3 ./deps.py && \
    touch packages_complete && \
    rm -rf /var/lib/apt/lists/*

RUN cd tools/linux && ./cmake.sh
RUN cd tools/linux/sysroot && ../python3/bin/python3 ./fetch.py amd64

# Copy all source repos (invalidates build layer only when sources change)
COPY core/ /build/core/
COPY sdkjs/ /build/sdkjs/
COPY web-apps/ /build/web-apps/

# Configure: server module, Linux 64-bit, no source updates
# --sysroot 1 is required so bundled clang uses the downloaded sysroot headers
# instead of Ubuntu 24.04 system headers (avoids uint8_t/intptr_t errors in V8)
RUN ./tools/linux/python3/bin/python3 ./configure.py \
    --update=0 \
    --module=server \
    --clean=1 \
    --platform=linux_64 \
    --sysroot=1 \
    --qt-dir="$(pwd)/tools/linux/qt_build/Qt-5.9.9"

# Build C++ core (libBinDocument.so, x2t) + JS (sdkjs, web-apps)
# OO_SKIP_SERVER=1 skips build_server and deploy (we don't have server/ repo)
RUN OO_SKIP_SERVER=1 ./tools/linux/python3/bin/python3 ./make.py

# ===============================
# Stage 2: Final image
# ===============================
FROM onlyoffice/documentserver:9.3.1

# Use Thai mirror (KKU) for faster apt downloads
RUN if [ -f /etc/apt/sources.list.d/ubuntu.sources ]; then \
        sed -i 's|http://archive.ubuntu.com/ubuntu|https://mirror.kku.ac.th/ubuntu|g' /etc/apt/sources.list.d/ubuntu.sources && \
        sed -i 's|http://security.ubuntu.com/ubuntu|https://mirror.kku.ac.th/ubuntu|g' /etc/apt/sources.list.d/ubuntu.sources; \
    elif [ -f /etc/apt/sources.list ]; then \
        sed -i 's|http://archive.ubuntu.com/ubuntu|https://mirror.kku.ac.th/ubuntu|g' /etc/apt/sources.list && \
        sed -i 's|http://security.ubuntu.com/ubuntu|https://mirror.kku.ac.th/ubuntu|g' /etc/apt/sources.list; \
    fi

RUN apt-get update && \
    apt-get install -y fonts-thai-tlwg && \
    rm -rf /var/lib/apt/lists/*

LABEL maintainer="teeradet phondetparinya"
LABEL description="Custom ONLYOFFICE Document Server (AGPL-3.0 compliant build)"

# Copy patched C++ core: libBinDocument.so (Thai Distributed alignment fix) + x2t + all dependent .so
# These replace the binaries from onlyoffice/documentserver:9.3.1 base image
COPY --from=builder /build/core/build/bin/linux_64/x2t /var/www/onlyoffice/documentserver/server/FileConverter/bin/x2t
COPY --from=builder /build/core/build/lib/linux_64/ /var/www/onlyoffice/documentserver/server/FileConverter/bin/

# Copy patched sdkjs (word editor with Thai Distributed alignment)
COPY --from=builder /build/sdkjs/deploy/sdkjs/word/sdk-all-min.js /var/www/onlyoffice/documentserver/sdkjs/word/sdk-all-min.js
COPY --from=builder /build/sdkjs/deploy/sdkjs/word/sdk-all.js /var/www/onlyoffice/documentserver/sdkjs/word/sdk-all.js
# Delete pre-built V8 snapshots from base image so doctrenderer loads our patched .js instead
RUN rm -f /var/www/onlyoffice/documentserver/sdkjs/word/sdk-all.bin \
          /var/www/onlyoffice/documentserver/sdkjs/slide/sdk-all.bin \
          /var/www/onlyoffice/documentserver/sdkjs/cell/sdk-all.bin

# Copy patched web-apps
COPY --from=builder /build/web-apps/deploy/web-apps/ /var/www/onlyoffice/documentserver/web-apps/

# Copy Thai fonts
COPY fonts/ /usr/share/fonts/truetype/

# Copy Thai dictionary for server-side word segmentation (ThaiWordBreaker)
# Primary path (absolute, matches GetThaiBreaker() search list)
COPY config/dictionary/words_th.txt /var/www/onlyoffice/documentserver/dictionary/words_th.txt
# Secondary path: next to x2t binary so it is always found regardless of CWD
COPY config/dictionary/words_th.txt /var/www/onlyoffice/documentserver/server/FileConverter/bin/dictionary/words_th.txt
