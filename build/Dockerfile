# XC PHP 7.4 (Remi Collet security backports) built on Ubuntu 14.04 so one binary runs on 14.04-22.04.
# Build:  docker build --target out --output type=local,dest=./out .
# Result: ./out/xc-php74.tar.gz and ./out/xc-php74.tar.gz.sha256

FROM ubuntu:22.04 AS fetch
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      ca-certificates curl git autoconf automake libtool pkg-config make \
 && rm -rf /var/lib/apt/lists/*
COPY fetch.sh /fetch.sh
RUN bash /fetch.sh /build/dl

FROM ubuntu:14.04 AS build
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      build-essential autoconf automake libtool pkg-config bison re2c perl \
      xz-utils bzip2 file patch m4 libbz2-dev libsqlite3-dev \
 && rm -rf /var/lib/apt/lists/*
COPY --from=fetch /build/dl /build/dl
COPY build.sh /build/build.sh
RUN bash /build/build.sh

FROM scratch AS out
COPY --from=build /build/out/xc-php74.tar.gz /build/out/xc-php74.tar.gz.sha256 /
