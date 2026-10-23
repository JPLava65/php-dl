#!/bin/bash
# Builds XC-compatible PHP 7.4 (Remi Collet security backports) inside Ubuntu 14.04.
# Runs inside the build container. Expects sources in /build/dl (see fetch.sh).
# Output: /build/out/home/xtreamcodes/iptv_xtream_codes/php/...  +  /build/out/xc-php74.tar.gz
set -euo pipefail

DL=/build/dl
WORK=/build/work
DEPS=/opt/xcdeps
PREFIX=/home/xtreamcodes/iptv_xtream_codes/php
OUT=/build/out
JOBS=$(nproc)

export CFLAGS="-O2 -fPIC -fstack-protector -D_FORTIFY_SOURCE=2"
export CXXFLAGS="$CFLAGS"
export CPPFLAGS="-I$DEPS/include"
export LDFLAGS="-L$DEPS/lib -L$DEPS/lib64"
export PKG_CONFIG_PATH="$DEPS/lib/pkgconfig:$DEPS/lib64/pkgconfig"
export PKG_CONFIG="pkg-config --static"
export PATH="$DEPS/bin:$PATH"

log(){ echo; echo "########## $* ##########"; }
# done NAME -> true if stage already finished; mark NAME -> record success
done_(){ [ -f "$DEPS/.done-$1" ]; }
mark(){ touch "$DEPS/.done-$1"; }
fresh(){ rm -rf "$WORK/$1"; mkdir -p "$WORK"; }
untar(){ fresh "$2"; tar -xf "$DL/$1" -C "$WORK"; }
copy(){ fresh "$1"; cp -a "$DL/$1" "$WORK/$1"; }

mkdir -p "$DEPS/lib" "$DEPS/include"

if done_ zlib; then echo "skip zlib"; else
log "zlib 1.3.1"
untar zlib-1.3.1.tar.gz zlib-1.3.1; cd "$WORK/zlib-1.3.1"
./configure --prefix="$DEPS" --static >/dev/null && make -j"$JOBS" >/dev/null && make install >/dev/null
mark zlib; fi

if done_ openssl; then echo "skip openssl"; else
log "OpenSSL 1.1.1w"
untar openssl-1.1.1w.tar.gz openssl-1.1.1w; cd "$WORK/openssl-1.1.1w"
# Private OPENSSLDIR so the 1.1.1 library never reads a host's OpenSSL 3 openssl.cnf.
# certs/ and cert.pem inside it are symlinked to the host CA store at install time.
./config --prefix="$DEPS" --openssldir="$PREFIX/ssl" no-shared no-tests no-ssl3 no-weak-ssl-ciphers -fPIC >/dev/null
make -j"$JOBS" >/dev/null && make install_sw >/dev/null
mark openssl; fi

if done_ curl; then echo "skip curl"; else
log "curl 8.10.1"
untar curl-8.10.1.tar.gz curl-8.10.1; cd "$WORK/curl-8.10.1"
./configure --prefix="$DEPS" --disable-shared --enable-static \
  --with-openssl="$DEPS" --with-zlib="$DEPS" \
  --with-ca-bundle=/etc/ssl/certs/ca-certificates.crt --with-ca-path=/etc/ssl/certs \
  --without-libpsl --without-libidn2 --without-nghttp2 --without-brotli --without-zstd \
  --without-libssh2 --without-librtmp --without-gssapi --disable-ldap --disable-ldaps \
  --disable-docs --disable-manual >/dev/null
make -j"$JOBS" >/dev/null && make install >/dev/null
mark curl; fi

if done_ libxml2; then echo "skip libxml2"; else
log "libxml2 2.12.10"
copy libxml2; cd "$WORK/libxml2"
./configure --prefix="$DEPS" --disable-shared --enable-static --without-python \
  --without-lzma --without-icu --with-zlib="$DEPS" >/dev/null
make -j"$JOBS" >/dev/null && make install >/dev/null
mark libxml2; fi

if done_ libxslt; then echo "skip libxslt"; else
log "libxslt 1.1.39"
copy libxslt; cd "$WORK/libxslt"
./configure --prefix="$DEPS" --disable-shared --enable-static --without-python \
  --without-crypto --with-libxml-prefix="$DEPS" >/dev/null
make -j"$JOBS" >/dev/null && make install >/dev/null
mark libxslt; fi

if done_ libpng; then echo "skip libpng"; else
log "libpng 1.6.44"
copy libpng; cd "$WORK/libpng"
./configure --prefix="$DEPS" --disable-shared --enable-static >/dev/null
make -j"$JOBS" >/dev/null && make install >/dev/null
mark libpng; fi

if done_ freetype; then echo "skip freetype"; else
log "freetype 2.13.3"
copy freetype; cd "$WORK/freetype"
./configure --prefix="$DEPS" --disable-shared --enable-static --with-zlib=yes \
  --with-png=no --with-bzip2=no --with-harfbuzz=no --with-brotli=no >/dev/null
make -j"$JOBS" >/dev/null && make install >/dev/null
mark freetype; fi

if done_ onig; then echo "skip onig"; else
log "oniguruma 6.9.9"
untar onig-6.9.9.tar.gz onig-6.9.9; cd "$WORK/onig-6.9.9"
./configure --prefix="$DEPS" --disable-shared --enable-static >/dev/null
make -j"$JOBS" >/dev/null && make install >/dev/null
mark onig; fi

if done_ libzip; then echo "skip libzip"; else
log "libzip 1.11.2"
untar cmake-3.20.6-linux-x86_64.tar.gz cmake-3.20.6-linux-x86_64
untar libzip-1.11.2.tar.gz libzip-1.11.2; mkdir -p "$WORK/libzip-1.11.2/b"; cd "$WORK/libzip-1.11.2/b"
"$WORK/cmake-3.20.6-linux-x86_64/bin/cmake" .. -DCMAKE_INSTALL_PREFIX="$DEPS" -DCMAKE_INSTALL_LIBDIR=lib \
  -DBUILD_SHARED_LIBS=OFF -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DCMAKE_POLICY_DEFAULT_CMP0074=NEW -DZLIB_ROOT="$DEPS" \
  -DENABLE_BZIP2=OFF -DENABLE_LZMA=OFF -DENABLE_ZSTD=OFF -DENABLE_OPENSSL=OFF -DENABLE_GNUTLS=OFF \
  -DENABLE_MBEDTLS=OFF -DENABLE_COMMONCRYPTO=OFF -DENABLE_WINDOWS_CRYPTO=OFF \
  -DBUILD_TOOLS=OFF -DBUILD_REGRESS=OFF -DBUILD_OSSFUZZ=OFF -DBUILD_EXAMPLES=OFF -DBUILD_DOC=OFF >/dev/null
make -j"$JOBS" >/dev/null && make install >/dev/null
mark libzip; fi

if done_ libmcrypt; then echo "skip libmcrypt"; else
log "libmcrypt 2.5.8"
# Ubuntu's source package (official 2.5.8 tarball + Ubuntu patch). A git mirror of
# 2.5.8 was tried first and its build crashed in rijndael encryption: do not use it.
untar libmcrypt_2.5.8.orig.tar.gz libmcrypt-2.5.8; cd "$WORK/libmcrypt-2.5.8"
zcat "$DL/libmcrypt_2.5.8-3.1ubuntu1.diff.gz" | patch -p1 -s
./configure --prefix="$DEPS" --disable-shared --enable-static --disable-posix-threads >/dev/null
make -j"$JOBS" >/dev/null && make install >/dev/null
mark libmcrypt; fi

if done_ geoip; then echo "skip geoip"; else
log "GeoIP C 1.6.12"
untar GeoIP-1.6.12.tar.gz GeoIP-1.6.12; cd "$WORK/GeoIP-1.6.12"
./configure --prefix="$DEPS" --disable-shared --enable-static >/dev/null
make -j"$JOBS" >/dev/null && make install >/dev/null
mark geoip; fi

log "bzip2 + sqlite3 (Ubuntu 14.04 static libraries)"
cp /usr/lib/x86_64-linux-gnu/libbz2.a /usr/lib/x86_64-linux-gnu/libsqlite3.a "$DEPS/lib/"
cp /usr/include/bzlib.h "$DEPS/include/"

log "PHP 7.4 (Remi security backports) + PECL mcrypt + geoip, built in"
copy php; cd "$WORK/php"
cp -a "$DL/pecl-mcrypt" ext/mcrypt
cp -a "$DL/pecl-geoip"  ext/geoip
./buildconf --force >/dev/null 2>&1
# XC's 7.2.3 configure line, translated to 7.4 option names.
# Removed in 7.4 (no replacement needed): --with-pcre-regex --enable-gd-native-ttf
#   --enable-inline-optimization --with-mysql --with-libdir --with-zlib-dir --with-freetype-dir
./configure --prefix="$PREFIX" \
  --disable-rpath --enable-static --disable-shared \
  --enable-fpm --with-fpm-user=xtreamcodes --with-fpm-group=xtreamcodes \
  --enable-opcache \
  --with-zlib --with-bz2="$DEPS" --with-zip \
  --enable-mbstring --enable-mbregex \
  --enable-calendar --enable-exif --enable-bcmath --with-mhash \
  --with-curl --with-openssl \
  --enable-gd --with-freetype \
  --enable-sockets --enable-sysvsem --enable-sysvshm --enable-pcntl \
  --with-mysqli=mysqlnd --with-pdo-mysql=mysqlnd \
  --with-gettext --with-xmlrpc --with-xsl \
  --with-mcrypt="$DEPS" --with-geoip="$DEPS" \
  LIBS="-lpthread -ldl" > "$WORK/php-configure.log" 2>&1 \
  || { tail -40 "$WORK/php-configure.log"; exit 1; }
make -j"$JOBS" > "$WORK/php-make.log" 2>&1 || { tail -60 "$WORK/php-make.log"; exit 1; }

rm -rf "$OUT/home"; mkdir -p "$OUT"
make install INSTALL_ROOT="$OUT" > "$WORK/php-install.log" 2>&1 || { tail -40 "$WORK/php-install.log"; exit 1; }

log "Package"
cd "$OUT"
rm -rf "./$PREFIX/php/man" "./$PREFIX/include" "./$PREFIX/lib/php/build" "./$PREFIX/bin/phpize" "./$PREFIX/bin/php-config" \
       "./$PREFIX/bin/phpdbg" "./$PREFIX/lib/php/extensions/no-debug-non-zts-20190902/opcache.a"
mkdir -p "./$PREFIX/ssl"
printf '# Intentionally empty: XC PHP 7.4 bundled OpenSSL 1.1.1 config\n' > "./$PREFIX/ssl/openssl.cnf"
ln -sfn /etc/ssl/certs "./$PREFIX/ssl/certs"
ln -sfn /etc/ssl/certs/ca-certificates.crt "./$PREFIX/ssl/cert.pem"
strip "./$PREFIX/bin/php" "./$PREFIX/sbin/php-fpm" || true
find "./$PREFIX/lib/php/extensions" -name '*.so' -exec strip --strip-unneeded {} + || true
tar -czf "$OUT/xc-php74.tar.gz" "./${PREFIX#/}"
( cd "$OUT"; sha256sum xc-php74.tar.gz > xc-php74.tar.gz.sha256 )

log "Result"
"./$PREFIX/bin/php" -v
ls -l "./$PREFIX/bin/php" "./$PREFIX/sbin/php-fpm" "$OUT/xc-php74.tar.gz"
cat "$OUT/xc-php74.tar.gz.sha256"
echo BUILD_OK
