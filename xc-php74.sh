#!/bin/bash
# xc-php74.sh - move an XC node from its bundled PHP 7.2/7.3 to the patched PHP 7.4 build.
# Repo: https://github.com/JPLava65/php-dl
#
# Run the stages in order, checking the output of each before the next:
#   check     read-only: OS, PHP, php.ini, pools, viewers per pool, permissions
#   stage     download + verify package and ionCube loader, build php.ini, test, back up,
#             place new files as *.new                                   (no live change)
#   swap      atomic swap of php, php-cgi, php-fpm, php.ini at second :05  (crons -> 7.4)
#   canary    restart ONE php-fpm pool on 7.4 and test the API          (cuts its viewers)
#   finish    restart the other pools + pipe_reader.php, then verify    (cuts their viewers)
#   verify    read-only: confirm everything runs 7.4
#   rollback  restore the 7.2/7.3 files and restart all pools
#   perms     remove world-write permission under /home/xtreamcodes (saves an undo list)
#
# Never runs start_services.sh, never touches nginx or ffmpeg processes.
set -uo pipefail

X=/home/xtreamcodes/iptv_xtream_codes
P=$X/php
D=/root/php74deploy
PKG_URL=${PKG_URL:-https://raw.githubusercontent.com/JPLava65/php-dl/main/xc-php74.tar.gz}
PKG_SHA=44994e0d2f715dcf571da69ecf93d952e491aa59aa517b9e1f08868019e38dfa
IC_URL=${IC_URL:-https://downloads.ioncube.com/loader_downloads/ioncube_loaders_lin_x86-64.tar.gz}
IONCUBE_SO=${IONCUBE_SO:-}          # optional: path to an ioncube_loader_lin_7.4.so already on this node
EXT74=no-debug-non-zts-20190902
NEWVER=7.4.33
TEST=${XC_TEST:-0}                  # test harness only: skips ionCube assertions

say(){ printf '%s\n' "$*"; }
ok(){ printf '  [ok]   %s\n' "$*"; }
warn(){ printf '  [warn] %s\n' "$*"; }
die(){ printf '  [STOP] %s\n' "$*"; exit 1; }
need_root(){ [ "$(id -u)" = 0 ] || die "run as root"; }

# Pool names, taken from the start-stop-daemon lines XC itself uses at boot.
pools(){
  local p
  p=$(grep -oE 'fpm-config [^ ]*/etc/[A-Za-z0-9_]+\.conf' "$X/start_services.sh" 2>/dev/null | sed -E 's#.*/etc/##; s#\.conf$##')
  [ -n "$p" ] || p=$(ls "$P"/etc/*.conf 2>/dev/null | sed -E 's#.*/##; s#\.conf$##' | grep -v '^php-fpm$')
  printf '%s\n' $p
}
master(){ local m; m=$(cat "$P/$1.pid" 2>/dev/null); [ -n "$m" ] && kill -0 "$m" 2>/dev/null && echo "$m"; }   # live pid only
is_old(){ readlink "/proc/$1/exe" 2>/dev/null | grep -q '(deleted)'; }   # running a replaced binary
cur_ver(){ "$P/bin/php" -n -r 'echo PHP_VERSION;' 2>/dev/null; }

nginx_ports(){ grep -oE 'listen +[0-9]+' "$X/nginx/conf/nginx.conf" 2>/dev/null | grep -oE '[0-9]+' | sort -u; }
api_test(){ # main server: player_api.php answers JSON. Load balancer: a stream URL with a fake login gets 401/403 from XC's PHP.
  local port out code
  for port in $(nginx_ports); do
    out=$(wget -q -T 5 -O- "http://127.0.0.1:$port/player_api.php?username=test&password=test" 2>/dev/null)
    if printf '%s' "$out" | grep -q '"user_info"'; then echo "$port player_api: $out"; return 0; fi
  done
  for port in $(nginx_ports); do
    code=$(timeout 8 wget -S -T 5 -O /dev/null "http://127.0.0.1:$port/live/test/test/1.ts" 2>&1 | grep -m1 -oE 'HTTP/[0-9.]+ [0-9]{3}' | grep -oE '[0-9]{3}$')
    case "$code" in 401|403) echo "$port stream test: HTTP $code from XC's PHP (fake login rejected, as expected)"; return 0;; esac
  done
  return 1
}
old_cli_pids(){ # PHP command-line processes still running a replaced (old) bin/php
  ls -l /proc/*/exe 2>/dev/null | grep -E 'iptv_xtream_codes/php/bin/php(-cgi)? \(deleted\)' | grep -oE '/proc/[0-9]+' | cut -d/ -f3
}
restart_old_tools(){ # any long-running tools/*.php still on the old PHP: stop it, let XC respawn it, else start it as before
  local p args t new i
  for p in $(old_cli_pids); do
    args=$(tr '\0' ' ' < /proc/$p/cmdline 2>/dev/null); t=$(printf '%s' "$args" | grep -oE 'tools/[A-Za-z0-9_]+\.php' | head -1)
    [ -n "$t" ] || { say "  pid $p: ${args:0:90} - not a tool, left to finish on its own"; continue; }
    say "  $t (pid $p) is still on the old PHP - stopping it, waiting up to 70s for XC to restart it"
    kill "$p"; for i in $(seq 70); do sleep 1; new=$(pgrep -u xtreamcodes -f "php/bin/php .*$t" | head -1); [ -n "$new" ] && ! is_old "$new" && break; new=""; done
    if [ -z "$new" ]; then
      setsid sudo -u xtreamcodes "$P/bin/php" ${args#* } >/dev/null 2>&1 < /dev/null &
      sleep 3; new=$(pgrep -u xtreamcodes -f "php/bin/php .*$t" | head -1)
      [ -n "$new" ] && ok "$t started by script (pid $new)" || warn "$t did not start - check it"
    else ok "$t restarted by XC (pid $new, $(readlink /proc/$new/exe))"; fi
  done
}

viewers(){ # workers that sent >100 KB in 5 s = active streams
  local c m p a b n
  for c in $(pools); do
    m=$(master "$c"); [ -n "$m" ] || { echo "  $c: not running"; continue; }
    for p in $(ps -o pid= --ppid "$m"); do echo "$p $(awk '/wchar/{print $2}' /proc/$p/io 2>/dev/null)"; done > "$D/.w.$c"
  done
  sleep 5
  for c in $(pools); do
    [ -f "$D/.w.$c" ] || continue; n=0
    while read -r p a; do b=$(awk '/wchar/{print $2}' /proc/$p/io 2>/dev/null)
      [ -n "$a" ] && [ -n "$b" ] && [ $(( (b-a)/1024 )) -gt 100 ] && n=$((n+1)); done < "$D/.w.$c"
    echo "  $c: $(pgrep -c -P "$(master "$c")") workers, $n streaming now"; rm -f "$D/.w.$c"
  done
}

restart_pool(){ # $1 = pool name; starts it if it is down
  local c=$1 old new i
  old=$(master "$c")
  if [ -n "$old" ]; then
    kill -TERM "$old" || die "$c: could not signal master $old"
    for i in $(seq 300); do kill -0 "$old" 2>/dev/null || break; sleep 0.2; done
    kill -0 "$old" 2>/dev/null && die "$c: master $old did not exit within 60s - investigate before continuing"
  else warn "$c was not running - starting it"; old="none"; fi
  start-stop-daemon --start --quiet --pidfile "$P/$c.pid" --exec "$P/sbin/php-fpm" -- --daemonize --fpm-config "$P/etc/$c.conf" \
    || die "$c: php-fpm failed to start - run: $0 rollback"
  for i in $(seq 25); do [ -S "$P/$c.sock" ] && [ -n "$(master "$c")" ] && break; sleep 0.2; done
  new=$(master "$c")
  [ -S "$P/$c.sock" ] || die "$c: socket missing after start - run: $0 rollback"
  is_old "$new" && die "$c: new master $new still runs the old binary"
  ok "$c restarted: master $old -> $new ($(readlink /proc/$new/exe))"
}

restart_tool(){ # $1 = tools/<name>.php ; only if it is currently running
  local t=$1 pid
  pid=$(pgrep -u xtreamcodes -f "php/bin/php .*tools/$t" | head -1)
  [ -n "$pid" ] || { say "  $t not running - left alone"; return; }
  kill "$pid"; for i in $(seq 50); do kill -0 "$pid" 2>/dev/null || break; sleep 0.2; done
  setsid sudo -u xtreamcodes "$P/bin/php" "$X/tools/$t" >/dev/null 2>&1 < /dev/null &
  sleep 2; pid=$(pgrep -u xtreamcodes -f "php/bin/php .*tools/$t" | head -1)
  [ -n "$pid" ] && ok "$t restarted (pid $pid, $(readlink /proc/$pid/exe))" || warn "$t did not come back - check it"
}

fpmlog_errors(){ grep -E "ERROR|ALERT" "$P/var/log/php-fpm.log" 2>/dev/null | tail -${1:-5}; }

cmd_check(){
  say "== node"; say "  $(lsb_release -ds 2>/dev/null || grep PRETTY /etc/os-release | cut -d'"' -f2)"
  say "  PHP now: $(cur_ver)   php-fpm md5: $(md5sum "$P/sbin/php-fpm" | cut -c1-32)"
  say "== php.ini extension lines"; grep -nE '^\s*(extension_dir|zend_extension|extension)\s*=' "$P/lib/php.ini" | sed 's/^/  /'
  grep -qE '^\s*extension_dir\s*=' "$P/lib/php.ini" && warn "php.ini sets extension_dir explicitly - stage will stop; tell Claude"
  say "== pools (from start_services.sh)"; viewers
  [ -f "$X/nginx/conf/balance.conf" ] && say "  balance.conf: $(grep -c 'server unix' "$X/nginx/conf/balance.conf") sockets, $(grep -oE 'least_conn|ip_hash' "$X/nginx/conf/balance.conf" | head -1)"
  say "== tools"; for t in signal_receiver.php pipe_reader.php; do say "  $t: $(pgrep -u xtreamcodes -f "tools/$t" >/dev/null && echo running || echo 'not running')"; done
  say "== permissions"; say "  world-writable under $X: $(find "$X" \( -type f -o -type d \) -perm -o+w 2>/dev/null | wc -l)"
  say "== disk"; df -h /root | tail -1 | sed 's/^/  /'
  [ -d "$D/rollback" ] && say "  (a previous stage exists in $D)"
}

cmd_stage(){
  need_root
  [ "$(cur_ver)" = "$NEWVER" ] && [ ! -d "$D/rollback" ] && die "this node already runs $NEWVER"
  grep -qE '^\s*extension_dir\s*=' "$P/lib/php.ini" && die "php.ini sets extension_dir explicitly - not handled automatically"
  mkdir -p "$D" && cd "$D" || die "cannot use $D"
  say "== package"
  [ -f xc-php74.tar.gz ] || wget -q -O xc-php74.tar.gz "$PKG_URL" || die "download failed: $PKG_URL"
  echo "$PKG_SHA  xc-php74.tar.gz" | sha256sum -c --quiet - || { rm -f xc-php74.tar.gz; die "package checksum mismatch - deleted, try again"; }
  ok "xc-php74.tar.gz sha256 verified"
  rm -rf stage && mkdir stage && tar -xzf xc-php74.tar.gz -C stage || die "extract failed"
  S=$D/stage$P; E=$S/lib/php/extensions/$EXT74
  say "== ionCube loader"
  if [ -n "$IONCUBE_SO" ]; then cp "$IONCUBE_SO" "$E/ioncube_loader_lin_7.4.so" || die "cannot copy $IONCUBE_SO"
  elif [ "$TEST" = 1 ]; then warn "XC_TEST=1: no ionCube loader"
  else
    [ -f ioncube_loaders_lin_x86-64.tar.gz ] || wget -q -O ioncube_loaders_lin_x86-64.tar.gz "$IC_URL" || die "ionCube download failed (set IONCUBE_SO=/path/to/ioncube_loader_lin_7.4.so)"
    tar -xzf ioncube_loaders_lin_x86-64.tar.gz ioncube/ioncube_loader_lin_7.4.so && cp ioncube/ioncube_loader_lin_7.4.so "$E/" || die "ionCube extract failed"
  fi
  [ "$TEST" = 1 ] || ok "ionCube loader 7.4 in place"
  say "== php.ini"
  cp "$P/lib/php.ini" php.ini.74
  sed -i -E 's/^(zend_extension=)ioncube_loader_lin_7\.[0-9]\.so\s*$/\1ioncube_loader_lin_7.4.so/;
             s/^(extension=(geoip|mcrypt)\.so)\s*$/;\1 ; built into PHP 7.4/' php.ini.74
  [ "$TEST" = 1 ] && sed -i -E 's/^(zend_extension=ioncube)/;\1/' php.ini.74
  diff "$P/lib/php.ini" php.ini.74 | sed 's/^/  /'
  say "== test new PHP with this node's php.ini"
  v=$("$S/bin/php" -c php.ini.74 -d extension_dir="$E" -v 2>&1); printf '%s\n' "$v" | sed 's/^/  /'
  printf '%s' "$v" | grep -q "PHP $NEWVER" || die "new php does not start"
  printf '%s' "$v" | grep -qiE 'warning|failed' && die "new php prints warnings at startup (see above)"
  [ "$TEST" = 1 ] || printf '%s' "$v" | grep -q 'ionCube PHP Loader' || die "ionCube loader not loaded"
  m=$("$S/bin/php" -c php.ini.74 -d extension_dir="$E" -m)
  for x in geoip mcrypt curl openssl mysqli pdo_mysql mbstring zip xsl; do printf '%s\n' "$m" | grep -qx "$x" || die "module $x missing"; done
  ok "modules present"
  for c in $(pools); do "$S/sbin/php-fpm" -t -c php.ini.74 -d extension_dir="$E" --fpm-config "$P/etc/$c.conf" 2>&1 | grep -q "test is successful" || die "php-fpm -t failed for $c"; done
  ok "php-fpm config test passed for: $(pools | tr '\n' ' ')"
  bad=$(cd "$X" && find admin wwwdir crons tools -name '*.php' -size -2M 2>/dev/null | while read -r f; do
          grep -q 'ionCube Loader' "$f" && continue; "$S/bin/php" -n -l "$f" >/dev/null 2>&1 || echo "$f"; done)
  [ -z "$bad" ] && ok "all non-encoded XC PHP files pass the 7.4 syntax check" || { say "$bad" | sed 's/^/  /'; die "files above fail PHP 7.4 syntax check"; }
  say "== backup"
  if [ ! -d rollback ]; then
    tar -czf php-old-backup.tgz -C "$X" --exclude='*.sock' --exclude='*.pid' php 2>/dev/null; [ -s php-old-backup.tgz ] || die "backup failed"
    mkdir rollback && cp -p "$P/bin/php" "$P/bin/php-cgi" "$P/sbin/php-fpm" "$P/lib/php.ini" rollback/ || die "rollback copy failed"
    ok "backup $(du -h php-old-backup.tgz | cut -f1), rollback copies of PHP $(cur_ver) saved"
  else ok "rollback copies already exist (kept)"; fi
  say "== place new files (inactive until swap)"
  cp -a "$E" "$P/lib/php/extensions/" && cp -a "$S/ssl" "$P/" || die "copy failed"
  install -o xtreamcodes -g xtreamcodes -m 755 "$S/bin/php" "$P/bin/php.new" && \
  install -o xtreamcodes -g xtreamcodes -m 755 "$S/bin/php-cgi" "$P/bin/php-cgi.new" && \
  install -o xtreamcodes -g xtreamcodes -m 755 "$S/sbin/php-fpm" "$P/sbin/php-fpm.new" && \
  install -o xtreamcodes -g xtreamcodes -m 644 php.ini.74 "$P/lib/php.ini.new" || die "install failed"
  chown -R xtreamcodes:xtreamcodes "$P/lib/php/extensions/$EXT74"; chown -h xtreamcodes:xtreamcodes "$P/ssl" "$P"/ssl/*
  say "  live PHP is still $(cur_ver)"; say "STAGED OK - next: $0 swap"
}

cmd_swap(){
  need_root
  for f in bin/php.new bin/php-cgi.new sbin/php-fpm.new lib/php.ini.new; do [ -f "$P/$f" ] || die "missing $P/$f - run stage first"; done
  say "  waiting for second :05 ..."; sleep $(( (65 - 10#$(date +%S)) % 60 ))
  mv -f "$P/lib/php.ini.new" "$P/lib/php.ini" && mv -f "$P/bin/php.new" "$P/bin/php" && \
  mv -f "$P/bin/php-cgi.new" "$P/bin/php-cgi" && mv -f "$P/sbin/php-fpm.new" "$P/sbin/php-fpm" || die "swap incomplete - run: $0 rollback"
  ok "swapped at $(date +%T)"
  "$P/bin/php" -v | sed 's/^/  /'
  [ "$(cur_ver)" = "$NEWVER" ] || die "php is not $NEWVER after swap"
  say "SWAPPED - crons use $NEWVER from the next minute; php-fpm still old until: $0 canary"
}

cmd_canary(){
  need_root; [ "$(cur_ver)" = "$NEWVER" ] || die "run swap first"
  local c=${1:-$(pools | head -1)}
  say "== viewers now"; viewers
  restart_pool "$c"
  sleep 3; say "== PHP through nginx"; r=$(api_test) && ok "port ${r%% *} ${r#* }" || warn "PHP did not answer through nginx - check before finish"
  say "== php-fpm log"; tail -3 "$P/var/log/php-fpm.log" | sed 's/^/  /'
  say "CANARY DONE - if OK: $0 finish   |   if not: $0 rollback"
}

cmd_finish(){
  need_root; [ "$(cur_ver)" = "$NEWVER" ] || die "run swap first"
  local c m
  for c in $(pools); do m=$(master "$c"); { [ -z "$m" ] || is_old "$m"; } && restart_pool "$c"; done
  restart_tool pipe_reader.php; restart_tool signal_receiver.php
  restart_old_tools
  sleep 2; cmd_verify
}

cmd_verify(){
  local c m bad=0 r
  say "== pools"
  for c in $(pools); do m=$(master "$c")
    if [ -z "$m" ]; then warn "$c not running"; bad=1
    elif is_old "$m"; then warn "$c still on the old binary"; bad=1
    else ok "$c master $m, $(pgrep -c -P "$m") workers"; fi; done
  n=$(ls -l /proc/*/exe 2>/dev/null | grep -c 'iptv_xtream_codes/php/.*(deleted)')
  if [ "$n" = 0 ]; then ok "no old PHP processes left"; else warn "$n processes still on the old PHP:"; bad=1
    for p in $(ls -l /proc/*/exe 2>/dev/null | grep 'iptv_xtream_codes/php/.*(deleted)' | grep -oE '/proc/[0-9]+' | cut -d/ -f3); do
      say "    $(ps -o pid=,etime=,args= -p "$p" | cut -c1-120)"; done
    say "    (a crons/*.php entry just finishes on its own; a tools/*.php entry: run '$0 finish' again)"; fi
  r=$(api_test) && ok "port ${r%% *} ${r#* }" || { warn "PHP did not answer through nginx (player_api.php or stream URL)"; bad=1; }
  e=$(fpmlog_errors 3); [ -z "$e" ] && ok "php-fpm.log: no errors" || { warn "php-fpm.log errors:"; say "$e" | sed 's/^/    /'; }
  [ $bad = 0 ] && say "VERIFY OK - PHP $(cur_ver)" || say "VERIFY: see warnings above"
}

cmd_rollback(){
  need_root; [ -d "$D/rollback" ] || die "no $D/rollback"
  for f in bin/php bin/php-cgi sbin/php-fpm lib/php.ini; do
    cp -p "$D/rollback/$(basename "$f")" "$P/$f.rb" && mv -f "$P/$f.rb" "$P/$f" || die "restore of $f failed"; done
  rm -f "$P/bin/php.new" "$P/bin/php-cgi.new" "$P/sbin/php-fpm.new" "$P/lib/php.ini.new"
  ok "files restored: PHP $(cur_ver)"
  for c in $(pools); do m=$(master "$c"); { [ -z "$m" ] || is_old "$m"; } && restart_pool "$c"; done
  restart_tool pipe_reader.php; restart_tool signal_receiver.php
  restart_old_tools
  say "ROLLED BACK to PHP $(cur_ver)"
}

cmd_perms(){
  need_root; mkdir -p "$D"
  local list=$D/oplusw_before_$(date +%F_%H%M).txt
  find /home/xtreamcodes \( -type f -o -type d \) -perm -o+w > "$list" 2>/dev/null
  say "  $(wc -l < "$list") world-writable entries saved to $list"
  find /home/xtreamcodes \( -type f -o -type d \) -perm -o+w -exec chmod o-w {} + 2>&1 | grep -v 'Operation not permitted' | sed 's/^/  /'
  left=$(find /home/xtreamcodes \( -type f -o -type d \) -perm -o+w 2>/dev/null)
  [ -z "$left" ] && ok "none left" || { say "$left" | while read -r f; do warn "still world-writable: $f $(lsattr -d "$f" 2>/dev/null | cut -c1-20 | grep -q i && echo '(immutable - fine)')"; done; }
  ps_=$X/permissions.sh
  local re='^(sudo )?chmod -R 0?777 /home/xtreamcodes( 2>/dev/null)?$'
  if grep -qE "$re" "$ps_" 2>/dev/null; then
    cp -p "$ps_" "$ps_.bak_$(date +%Y%m%d)" && sed -i -E "s#$re#\\1chmod -R u+rwX,g+rwX,o-w /home/xtreamcodes\\2#" "$ps_"
    grep -qE "$re" "$ps_" && warn "permissions.sh still contains chmod 777 - fix by hand" \
      || ok "permissions.sh: 'chmod -R 777' replaced (backup $ps_.bak_$(date +%Y%m%d))"
  else ok "permissions.sh has no 'chmod -R 777 /home/xtreamcodes' line"; fi
  say "  undo: xargs -d '\\n' chmod o+w < $list"
}

case "${1:-}" in
  check) cmd_check ;; stage) cmd_stage ;; swap) cmd_swap ;; canary) shift; cmd_canary "$@" ;;
  finish) cmd_finish ;; verify) cmd_verify ;; rollback) cmd_rollback ;; perms) cmd_perms ;;
  *) sed -n '2,17p' "$0"; exit 1 ;;
esac
