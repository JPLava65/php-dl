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

tarball https://github.com/madler/zlib/releases/download/v1.3.2/zlib-1.3.2.tar.gz \
  zlib-1.3.2.tar.gz bb329a0a2cd0274d05519d61c667c062e06990d72e125ee2dfa8de64f0119d16
tarball https://github.com/openssl/openssl/releases/download/OpenSSL_1_1_1w/openssl-1.1.1w.tar.gz \
  openssl-1.1.1w.tar.gz cf3098950cb4d853ad95c0841f1f9c6d3dc102dccfcacd521d93925208b76ac8
tarball https://github.com/curl/curl/releases/download/curl-8_17_0/curl-8.17.0.tar.gz \
  curl-8.17.0.tar.gz e8e74cdeefe5fb78b3ae6e90cd542babf788fa9480029cfcee6fd9ced42b7910  # last curl that builds with OpenSSL 1.1.1 (8.18+ need OpenSSL 3)
tarball https://github.com/kkos/oniguruma/releases/download/v6.9.10/onig-6.9.10.tar.gz \
  onig-6.9.10.tar.gz 2a5cfc5ae259e4e97f86b68dfffc152cdaffe94e2060b770cb827238d769fc05
tarball https://github.com/nih-at/libzip/releases/download/v1.11.4/libzip-1.11.4.tar.gz \
  libzip-1.11.4.tar.gz 82e9f2f2421f9d7c2466bbc3173cd09595a88ea37db0d559a9d0a2dc60dc722e
tarball https://github.com/maxmind/geoip-api-c/releases/download/v1.6.12/GeoIP-1.6.12.tar.gz \
  GeoIP-1.6.12.tar.gz 1dfb748003c5e4b7fd56ba8c4cd786633d5d6f409547584f6910398389636f80
tarball https://github.com/Kitware/CMake/releases/download/v3.20.6/cmake-3.20.6-linux-x86_64.tar.gz \
  cmake-3.20.6-linux-x86_64.tar.gz 458777097903b0f35a0452266b923f0a2f5b62fe331e636e2dcc4b636b768e36
tarball https://archive.ubuntu.com/ubuntu/pool/universe/libm/libmcrypt/libmcrypt_2.5.8.orig.tar.gz \
  libmcrypt_2.5.8.orig.tar.gz e4eb6c074bbab168ac47b947c195ff8cef9d51a211cdd18ca9c9ef34d27a373e
tarball https://archive.ubuntu.com/ubuntu/pool/universe/libm/libmcrypt/libmcrypt_2.5.8-3.1ubuntu1.diff.gz \
  libmcrypt_2.5.8-3.1ubuntu1.diff.gz c244480b3f84daa49ab40bfd52b410e32c0770d52cc4d213d9cec20275474cf9

# PHP 7.4.33 + Remi Collet security backports, branch head 2026-10-25 (adds GHSA-m8rr-4c36-8gq4, GHSA-hrwm-9436-5mv3)
gitpin https://github.com/remicollet/php-src-security.git php 575c10c4e0c9da6555557bc26fd93e52edeaf1fd
gitpin https://github.com/GNOME/libxml2.git libxml2 04af2cabb9f859c198b8a553c028a87481199410   # v2.13.9
gitpin https://github.com/GNOME/libxslt.git libxslt 71be7a32637760d769b193d95e0c745ecb86b679   # v1.1.43 (1.1.44+ need libxml2 2.15)
gitpin https://github.com/pnggroup/libpng.git libpng cd952f49f95bb27154ae77dbb103032d95f6e580  # v1.6.59
gitpin https://github.com/freetype/freetype.git freetype 0a0221a1347e2f1e07c395263540026e9a0aa7c7 # VER-2-14-3
gitpin https://github.com/nyorain/dlg.git freetype/subprojects/dlg 395ccad2c1e0daae535c4d20bb0a3f2424648e17
gitpin https://github.com/php/pecl-encryption-mcrypt.git pecl-mcrypt 15949865d9d8eb3a2f06e846d667d55b0033bfa5 # 1.0.7
gitpin https://github.com/php/pecl-networking-geoip.git pecl-geoip e24c5e54098958a1acc65b8830bc245c7d0662e6

# Generate configure scripts that need automake >= 1.16 (Ubuntu 14.04 has 1.14).
( cd libxml2 && NOCONFIGURE=1 ./autogen.sh >/dev/null 2>&1 ) && echo "ok  libxml2 configure"
( cd libxslt && NOCONFIGURE=1 ./autogen.sh >/dev/null 2>&1 ) && echo "ok  libxslt configure"
( cd freetype && ./autogen.sh >/dev/null 2>&1 ) && echo "ok  freetype configure"
echo FETCH_OK
