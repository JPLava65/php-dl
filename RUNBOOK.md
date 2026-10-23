# XC PHP 7.4 — build, test and deploy runbook

**Package:** `xc-php74.tar.gz`
sha256 `44994e0d2f715dcf571da69ecf93d952e491aa59aa517b9e1f08868019e38dfa`
**Built:** 2026-10-23, Ubuntu 14.04 clean room, from `Dockerfile` + `fetch.sh` + `build.sh` in this folder.

## What it is

- **PHP:** 7.4.33 with Remi Collet's security backports, commit `802c2107`. That includes the CVE-2026-109618/109619 fix and about 95 earlier CVE fixes.
- **Bundled libraries:** OpenSSL 1.1.1w, curl 8.10.1, libxml2 2.12.10, libxslt 1.1.39, libpng 1.6.44, freetype 2.13.3, zlib 1.3.1, libzip 1.11.2, oniguruma 6.9.9, GeoIP 1.6.12, libmcrypt 2.5.8 (Ubuntu source).
- **External dependencies:** none besides the system C library, so one binary serves Ubuntu 14.04 to 24.04.
- **Extensions:** identical to the main server's 7.2.3 `php -m`. `mcrypt` and `geoip` are compiled in; `opcache.so` stays a separate file.
- **Install prefix:** `/home/xtreamcodes/iptv_xtream_codes/php`. FPM user and group are `xtreamcodes`.

## Verified before release

| Check | Result |
|---|---|
| Module list vs 7.2.3 | Identical, on Ubuntu 14.04, 16.04, 18.04, 20.04, 22.04 and 24.04 |
| Functional test of every extension (mcrypt, openssl, curl, zip, gd+freetype, xsl, mbstring, sqlite, bz2, xmlrpc…) | Pass on all six releases |
| HTTPS certificate checking (curl and PHP streams) | Uses the system's `/etc/ssl/certs`. Rejects untrusted certificates and wrong hostnames |
| php-fpm with XC-style pool | Runs as `xtreamcodes`, opcache on. GET, form POST and file upload work. 200/200 sequential requests OK |
| CVE fix | Compiled in (`zend_mm_safe_error_ex`). 50 rounds of out-of-memory request then normal request on one worker: 50/50 normal requests OK, no crashes |
| Official 8.2.35 CVE tests | 8 pass. 18 differ only in PHP 8 features or output format; none show a crash |
| Package permissions | No world-writable files |

## Behaviour changes to know about

1. **A request that runs out of memory now ends its php-fpm worker** (log: `child N exited with code 1`) and php-fpm starts a fresh one. This is how the CVE fix works on 7.4. A burst of these lines means either `memory_limit` is too low or someone is sending oversized requests.
2. **`php.ini` needs 3 line changes:** the ionCube loader for 7.4, and removing `extension=geoip.so` and `extension=mcrypt.so` (now built in).
3. PHP 7.4 may log deprecation notices for old XC code. These are not errors.

## Phase 1: ionCube gate (VPS with Docker; touches nothing live)

**Main server:**
```
cd /home/xtreamcodes/iptv_xtream_codes
grep -rl "ionCube Loader" . --include=*.php | tar -czf /root/xc_encoded_16.tgz -T -
tar -tzf /root/xc_encoded_16.tgz | wc -l          # expect 16
```
Copy `/root/xc_encoded_16.tgz` to the VPS.

**VPS:** put `xc-php74.tar.gz`, `ioncube-test.sh` and `xc_encoded_16.tgz` in one folder, then:
```
wget https://downloads.ioncube.com/loader_downloads/ioncube_loaders_lin_x86-64.tar.gz
bash ioncube-test.sh
```
**Pass:** `files tested : 16` and `ionCube refusals (expect 0): 0`. Each file should fail only on ordinary things (missing config or database), which proves ionCube decoded it.
**Fail:** any "encoded … cannot be run" line. Stop: 7.4 is not usable with these files.

## Phase 2: main server read-only checks (send output back before Phase 3)

```
P=/home/xtreamcodes/iptv_xtream_codes
grep -nE "^\s*(extension_dir|zend_extension|extension)\s*=" $P/php/lib/php.ini
ls -la $P/php/bin $P/php/sbin
cat $P/start_services.sh
df -h /home /root
```

## Phase 3: deploy. Done on the main server, 2026-10-23 04:14–04:18

**Never use `start_services.sh` for this.** It kills every process whose `ps` line contains `xtreamcodes`, which includes XC's nginx and every ffmpeg stream.

**Streams pass through php-fpm** (`/live/`, `/movie/`, `/series/`, `/hls/` and `/timeshift/` are rewritten to `streaming/*.php`). Restarting a pool cuts the viewers on it, and their apps reconnect. nginx spreads PHP requests across the 3 pools (`nginx/conf/balance.conf`, `least_conn`), so restart one pool first as a canary.

On the main server, the client API is on port **8080** (the `wwwdir` block); port 80 is a different server block.

Steps used (`X=/home/xtreamcodes/iptv_xtream_codes; P=$X/php; D=/root/php74deploy; S=$D/stage$P`):
1. **Stage** in `$D`:
   - verify the sha256 and extract to `stage/`;
   - add `ioncube_loader_lin_7.4.so` to the stage extension folder;
   - create `php.ini.74` (line 1901 → `ioncube_loader_lin_7.4.so`; comment out `extension=geoip.so` and `extension=mcrypt.so`);
   - test with `$S/bin/php -c php.ini.74 -d extension_dir=… -v` and `php-fpm -t` against each real pool config;
   - run `php -l` on all non-encoded XC PHP files (expect no output).
2. **Backup and prepare:**
   - `tar` of `php/` into `$D/php-7.2-backup.tgz`;
   - `$D/rollback/` holds `php`, `php-cgi`, `php-fpm` and `php.ini`;
   - copy the 20190902 extension folder and `ssl/` into `$P`;
   - `install` the new binaries and `php.ini` as `*.new` (owner `xtreamcodes`).
3. **Swap at second :05** so the crons never see a half-swapped state:
   `mv -f` on `php.ini.new`, `bin/php.new`, `bin/php-cgi.new` and `sbin/php-fpm.new`.
4. **Canary pool:**
   `kill -TERM $(cat $P/$c.pid)`, wait for it to exit, then run the same `start-stop-daemon` line as `start_services.sh`. Check:
   - `/proc/<pid>/exe` without `(deleted)`;
   - the socket exists;
   - `wget http://127.0.0.1:8080/player_api.php?username=test&password=test` returns `{"user_info":{"auth":0}}`.
5. **The remaining pools,** back to back.
6. **`pipe_reader.php`:** stop it, then
   `setsid sudo -u xtreamcodes $P/bin/php $X/tools/pipe_reader.php >/dev/null 2>&1 </dev/null &`.
7. **Verify:** `ls -l /proc/*/exe | grep -c 'iptv_xtream_codes/php/.*(deleted)'` must show `0`, meaning no 7.2 PHP process is left. `php-fpm.log` should show no `ERROR`.

**Rollback:**
`for f in bin/php bin/php-cgi sbin/php-fpm lib/php.ini; do cp -p $D/rollback/$(basename $f) $P/$f.rb && mv -f $P/$f.rb $P/$f; done`, then restart the pools as in step 4.

**Result on the main server:**
- all 3 pools and every PHP process on 7.4.33 with ionCube 15.5.1;
- the API answers correctly;
- the only nginx errors are inside the 04:18:04 pool-restart second.

## Rebuilding (Docker on VPS or PC)

```
docker build --target out --output type=local,dest=./out .
```
Fetch checks every download against pinned SHA-256 hashes and git commits. To pick up newer Remi fixes, change the `php` commit in `fetch.sh` and rebuild.
