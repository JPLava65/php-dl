#!/bin/bash
# Downloads and verifies every source used by build.sh. Usage: fetch.sh <dest-dir>
# Tarballs are checked against pinned SHA-256; git sources against pinned commits.
set -euo pipefail
DL=${1:-/build/dl}
mkdir -p "$DL"; cd "$DL"

tarball(){ # url file sha256
  [ -f "$2" ] || curl -fsSL --retry 3 -o "$2" "$1"
  echo "$3  $2" | sha256sum -c --quiet - || { echo "CHECKSUM MISMATCH: $2"; exit 1; }
  echo "ok  $2"
}
gitpin(){ # url dir commit
  rm -rf "$2"; mkdir "$2"
  git -C "$2" init -q; git -C "$2" remote add origin "$1"
  git -C "$2" fetch -q --depth 1 origin "$3"; git -C "$2" checkout -q FETCH_HEAD
  [ "$(git -C "$2" rev-parse HEAD)" = "$3" ] || { echo "COMMIT MISMATCH: $2"; exit 1; }
  echo "ok  $2 @ $3"
}

tarball https://github.com/madler/zlib/releases/download/v1.3.1/zlib-1.3.1.tar.gz \
  zlib-1.3.1.tar.gz 9a93b2b7dfdac77ceba5a558a580e74667dd6fede4585b91eefb60f03b72df23
tarball https://github.com/openssl/openssl/releases/download/OpenSSL_1_1_1w/openssl-1.1.1w.tar.gz \
  openssl-1.1.1w.tar.gz cf3098950cb4d853ad95c0841f1f9c6d3dc102dccfcacd521d93925208b76ac8
tarball https://github.com/curl/curl/releases/download/curl-8_10_1/curl-8.10.1.tar.gz \
  curl-8.10.1.tar.gz d15ebab765d793e2e96db090f0e172d127859d78ca6f6391d7eafecfd894bbc0
tarball https://github.com/kkos/oniguruma/releases/download/v6.9.9/onig-6.9.9.tar.gz \
  onig-6.9.9.tar.gz 60162bd3b9fc6f4886d4c7a07925ffd374167732f55dce8c491bfd9cd818a6cf
tarball https://github.com/nih-at/libzip/releases/download/v1.11.2/libzip-1.11.2.tar.gz \
  libzip-1.11.2.tar.gz 6b2a43837005e1c23fdfee532b78f806863e412d2089b9c42b49ab08cbcd7665
tarball https://github.com/maxmind/geoip-api-c/releases/download/v1.6.12/GeoIP-1.6.12.tar.gz \
  GeoIP-1.6.12.tar.gz 1dfb748003c5e4b7fd56ba8c4cd786633d5d6f409547584f6910398389636f80
tarball https://github.com/Kitware/CMake/releases/download/v3.20.6/cmake-3.20.6-linux-x86_64.tar.gz \
  cmake-3.20.6-linux-x86_64.tar.gz 458777097903b0f35a0452266b923f0a2f5b62fe331e636e2dcc4b636b768e36
tarball http://archive.ubuntu.com/ubuntu/pool/universe/libm/libmcrypt/libmcrypt_2.5.8.orig.tar.gz \
  libmcrypt_2.5.8.orig.tar.gz e4eb6c074bbab168ac47b947c195ff8cef9d51a211cdd18ca9c9ef34d27a373e
tarball http://archive.ubuntu.com/ubuntu/pool/universe/libm/libmcrypt/libmcrypt_2.5.8-3.1ubuntu1.diff.gz \
  libmcrypt_2.5.8-3.1ubuntu1.diff.gz c244480b3f84daa49ab40bfd52b410e32c0770d52cc4d213d9cec20275474cf9

# PHP 7.4.33 + Remi Collet security backports (includes CVE-2026-109618/109619 fix)
gitpin https://github.com/remicollet/php-src-security.git php 802c21075308066362aab4993478dcd0577993a6
gitpin https://github.com/GNOME/libxml2.git libxml2 02d577715e1951cf114ca4e9adaf5605156c4f4c   # v2.12.10
gitpin https://github.com/GNOME/libxslt.git libxslt 743ab691bed98ed11ac99bbd9d903d59fb814ab8   # v1.1.39
gitpin https://github.com/pnggroup/libpng.git libpng f5e92d76973a7a53f517579bc95d61483bf108c0  # v1.6.44
gitpin https://github.com/freetype/freetype.git freetype 42608f77f20749dd6ddc9e0536788eaad70ea4b5 # VER-2-13-3
gitpin https://github.com/nyorain/dlg.git freetype/subprojects/dlg 72dfcc858c040c54a6a0b88fcb7e70ee186d3167
gitpin https://github.com/php/pecl-encryption-mcrypt.git pecl-mcrypt 15949865d9d8eb3a2f06e846d667d55b0033bfa5 # 1.0.7
gitpin https://github.com/php/pecl-networking-geoip.git pecl-geoip e24c5e54098958a1acc65b8830bc245c7d0662e6

# Generate configure scripts that need automake >= 1.16 (Ubuntu 14.04 has 1.14).
( cd libxml2 && NOCONFIGURE=1 ./autogen.sh >/dev/null 2>&1 ) && echo "ok  libxml2 configure"
( cd libxslt && NOCONFIGURE=1 ./autogen.sh >/dev/null 2>&1 ) && echo "ok  libxslt configure"
( cd freetype && ./autogen.sh >/dev/null 2>&1 ) && echo "ok  freetype configure"
echo FETCH_OK
