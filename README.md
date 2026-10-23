# php-dl: patched PHP 7.4 for Xtream Codes nodes

**What it is:** a drop-in replacement for XC's bundled PHP 7.2 or 7.3, at `/home/xtreamcodes/iptv_xtream_codes/php`.

- **PHP:** 7.4.33 with Remi Collet's security backports, commit `802c2107`. That includes the CVE-2026-109618 and CVE-2026-109619 fix (2026-10-21) plus about 95 earlier CVE fixes.
- **Built on:** Ubuntu 14.04. The only external dependency is the system C library, so one binary runs on Ubuntu 14.04 through 24.04.
- **Bundled libraries:** OpenSSL 1.1.1w, curl 8.10.1, libxml2 2.12.10 and others.
- **Extensions:** identical to XC's 7.2.3. `mcrypt` and `geoip` are compiled in; ionCube needs the official 7.4 loader.

## Release file

| File | sha256 |
|---|---|
| `xc-php74.tar.gz` (release `v7.4.33-remi802c210`) | `44994e0d2f715dcf571da69ecf93d952e491aa59aa517b9e1f08868019e38dfa` |

## Deploying to a node

```
cd /root && wget -q -O xc-php74.sh https://raw.githubusercontent.com/JPLava65/php-dl/main/xc-php74.sh
bash xc-php74.sh check      # read-only
bash xc-php74.sh stage      # download, verify, test, back up; no live change
bash xc-php74.sh swap       # crons move to 7.4
bash xc-php74.sh canary     # one php-fpm pool -> 7.4 (cuts that pool's viewers; apps reconnect)
bash xc-php74.sh finish     # remaining pools + pipe_reader.php, then verify
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
`fetch.sh` checks every source against pinned SHA-256 hashes and git commits. To pick up newer Remi fixes, update the `php` commit in `fetch.sh` and `PKG_SHA` / `PKG_URL` in `xc-php74.sh`, then rebuild and publish a new release.

See `RUNBOOK.md` for the verification results and the main-server deployment record.
