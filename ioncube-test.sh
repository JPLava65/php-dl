#!/bin/bash
# Runs XC's 16 ionCube-encoded files on the new PHP 7.4 build, inside Docker with NO network.
# Run on the VPS (Linux + Docker), in a folder containing:
#   xc-php74.tar.gz                         (the new build)
#   xc_encoded_16.tgz                       (made on the main server, see runbook)
#   ioncube_loaders_lin_x86-64.tar.gz       (official, from downloads.ioncube.com)
set -euo pipefail
cd "$(dirname "$0")"
for f in xc-php74.tar.gz xc_encoded_16.tgz ioncube_loaders_lin_x86-64.tar.gz; do
  [ -f "$f" ] || { echo "missing $f"; exit 1; }
done
rm -rf ic && mkdir -p ic/x && tar -xzf ioncube_loaders_lin_x86-64.tar.gz -C ic && tar -xzf xc_encoded_16.tgz -C ic/x
echo "ionCube loader: $(ls ic/ioncube/ioncube_loader_lin_7.4.so)"

docker run --rm --network none -v "$PWD":/t:ro ubuntu:18.04 bash -c '
  set -e
  tar -xzf /t/xc-php74.tar.gz -C /
  PHP=/home/xtreamcodes/iptv_xtream_codes/php/bin/php
  L=/t/ic/ioncube/ioncube_loader_lin_7.4.so
  $PHP -n -d zend_extension=$L -v
  echo
  for f in $(cd /t/ic/x && find . -name "*.php" | sort); do
    echo "== $f"
    ( cd /t/ic/x && timeout 15 $PHP -n -d zend_extension=$L -d display_errors=1 "$f" 2>&1 | head -4 ) || true
  done
' > ioncube_test.txt 2>&1 || true

echo "files tested : $(grep -c '^== ' ioncube_test.txt) (expect 16)"
echo "ionCube refusals (expect 0): $(grep -ciE 'encoded .*(cannot|can.t) be (run|used)|incompatible|requires the ionCube' ioncube_test.txt || true)"
echo "Full output in ioncube_test.txt"
