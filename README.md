# php-dl: patched PHP 7.4 for Xtream Codes nodes

**What it is:** a drop-in replacement for XC's bundled PHP 7.2 or 7.3, at `/home/xtreamcodes/iptv_xtream_codes/php`.

- **Release r2 (2026-10-31).** PHP 7.4.33 with Remi Collet's security backports at commit `575c10c4` (branch head 2026-10-25): adds GHSA-m8rr-4c36-8gq4 (CLI/CGI/FPM `-d` check) and a DatePeriod fix on top of r1 (`802c2107`, which carried the CVE-2026-109618/109619 fix and about 95 earlier CVE fixes).
- **Built on:** Ubuntu 14.04. The only external dependency is the system C library, so one binary runs on Ubuntu 14.04 through 24.04.
- **Bundled libraries:** OpenSSL 1.1.1w, curl 8.17.0, libxml2 2.13.9, libxslt 1.1.43, libpng 1.6.59, freetype 2.14.3, zlib 1.3.2, libzip 1.11.4, oniguruma 6.9.10, GeoIP 1.6.12, libmcrypt 2.5.8.
  - curl 8.17.0 is the last curl that builds with OpenSSL 1.1.1 (8.18+ require OpenSSL 3); libxslt 1.1.43 is the last that works with libxml2 2.13 (1.1.44+ require libxml2 2.15).
  - OpenSSL 1.1.1 is end-of-life. An OpenSSL 3.5 build of PHP 7.4 compiled with a one-line patch but failed 43 more of PHP's own OpenSSL tests (TLS stream wrappers, SAN matching, decrypt), so OpenSSL 3 waits for the PHP 8.5 build.
- **Extensions:** identical to XC's 7.2.3. `mcrypt` and `geoip` are compiled in; ionCube needs the official 7.4 loader.

## Release file

| File | sha256 |
|---|---|
| `xc-php74.tar.gz` (in this repo, r2) | `dd2f24e939d16b6971a23a3805ab0a3597795570700223b268fee4ca1b632ef0` |
| previous r1 (2026-10-23) | `44994e0d2f715dcf571da69ecf93d952e491aa59aa517b9e1f08868019e38dfa` |

Nodes already on r1 update with the same steps below: the script tells the builds apart by their build stamp
(`php -v` → `built: Oct 31 2026 20:57:05`) and keeps this release's backups in `/root/php74deploy-r2`, so `rollback`
returns a node to exactly what it ran before (r1, or 7.2/7.3).

## Deploying to a node

```
cd /root && wget -q -O xc-php74.sh https://raw.githubusercontent.com/JPLava65/php-dl/main/xc-php74.sh
bash xc-php74.sh check      # read-only
bash xc-php74.sh stage      # download, verify, test, back up; no live change
bash xc-php74.sh swap       # crons move to 7.4
bash xc-php74.sh canary     # one php-fpm pool -> 7.4 (cuts that pool's viewers; apps reconnect)
bash xc-php74.sh finish     # remaining pools + pipe_reader / signal_receiver / other tools, then verify
bash xc-php74.sh perms      # optional: remove world-write permission under /home/xtreamcodes
bash xc-php74.sh rollback   # back to the previous PHP at any point
```

**Run one step at a time and read its output before the next.** Never use `start_services.sh` to restart PHP: it kills nginx and every ffmpeg stream.

If a node can't reach `downloads.ioncube.com`, copy the loader over and point the script at it:
`IONCUBE_SO=/root/ioncube_loader_lin_7.4.so bash xc-php74.sh stage`

`XC_TEST=1` is only for the test rehearsal; never set it on a real node.

## Rebuilding the package

The build kit is in `build/`. Run this on any Linux machine or Docker Desktop:
```
cd build && docker build --target out --output type=local,dest=./out .
```
`fetch.sh` checks every source against pinned SHA-256 hashes and git commits. To pick up newer Remi fixes, update the `php` commit in `fetch.sh`, rebuild, replace `xc-php74.tar.gz` in this repo and update `PKG_SHA`, `NEWBUILT` and the deploy folder name `D` in `xc-php74.sh`.
r2 was built with `build.sh` in a debootstrap'd Ubuntu 14.04 root (same steps as the Dockerfile).

See `RUNBOOK.md` for the verification results and the main-server deployment record.
