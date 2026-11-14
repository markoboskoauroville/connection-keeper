#!/bin/bash
# Installs the ckbond relay on chromium-vm (Ubuntu, linux/arm64). Run ON THE VM as root; the token comes on stdin,
# never as an argument (it would show in `ps` and the shell history), and is never printed:
#
#   sudo bash install.sh [path/to/ck-bond-server-linux-arm64] < token-on-stdin
#   sudo bash install.sh --keep-token [path]      an upgrade: the token in /etc/ckbond/token stays, nothing on stdin
#
# It copies the binary to /usr/local/bin/ck-bond-server and the unit to /etc/systemd/system/ckbond.service, writes
# /etc/ckbond/token (0600, root), enables and (re)starts the service, and opens 443/tcp in the VM's own iptables
# (Oracle's Ubuntu images REJECT everything but SSH there). Oracle's VCN security list must allow 443/tcp as well:
# that is in the cloud console / OCI API, not here.
set -euo pipefail
cd "$(dirname "$0")"
KEEP=no; if [ "${1:-}" = --keep-token ]; then KEEP=yes; shift; fi
BIN=${1:-./ck-bond-server-linux-arm64}
[ "$(id -u)" = 0 ] || { echo "run it as root (sudo)"; exit 1; }
[ -f "$BIN" ] || { echo "no binary at $BIN"; exit 1; }
[ -f ckbond.service ] || { echo "ckbond.service must be next to install.sh"; exit 1; }
if [ "$KEEP" = yes ]; then
  [ -s /etc/ckbond/token ] || { echo "--keep-token: there is no /etc/ckbond/token"; exit 1; }
else
  IFS= read -r TOKEN || true
  TOKEN=$(printf '%s' "$TOKEN" | tr -d '[:space:]')
  [[ "$TOKEN" =~ ^[0-9a-fA-F]{64}$ ]] || { echo "stdin must hold the 64-hex-character token from bond.json"; exit 1; }
  install -d -m 700 /etc/ckbond
  ( umask 077; printf '%s\n' "$TOKEN" > /etc/ckbond/token )
  chmod 600 /etc/ckbond/token
  unset TOKEN
fi
# v71: an upgrade without downtime when the running relay can hand over (v71 and later, Type=notify): the new binary is
# moved into place (the running process keeps its own), then `systemctl reload` = SIGHUP = the new binary takes over the
# same socket and the old one drains. A relay before v71 cannot: it is restarted (once), the Mac goes direct meanwhile.
# Drop-ins in /etc/systemd/system/ckbond.service.d/ (the VM's vmcore.slice settings) are never touched.
CAN_RELOAD=no
if systemctl is-active --quiet ckbond && grep -q '^Type=notify' /etc/systemd/system/ckbond.service 2>/dev/null; then CAN_RELOAD=yes; fi
install -m 755 "$BIN" /usr/local/bin/ck-bond-server.new
mv -f /usr/local/bin/ck-bond-server.new /usr/local/bin/ck-bond-server
install -m 644 ckbond.service /etc/systemd/system/ckbond.service
systemctl daemon-reload
systemctl enable ckbond >/dev/null
if [ "$CAN_RELOAD" = yes ]; then
  systemctl reload ckbond && echo "ckbond: handed over to the new binary (zero downtime)"
else
  systemctl restart ckbond && echo "ckbond: restarted (the running relay could not hand over; once)"
fi

# 443/tcp in front of the image's REJECT rule (idempotent)
if ! iptables -C INPUT -p tcp --dport 443 -m state --state NEW -j ACCEPT 2>/dev/null; then
  N=$(iptables -L INPUT --line-numbers -n | awk '$2 == "REJECT" { print $1; exit }')
  if [ -n "$N" ]; then iptables -I INPUT "$N" -p tcp --dport 443 -m state --state NEW -j ACCEPT
  else iptables -A INPUT -p tcp --dport 443 -m state --state NEW -j ACCEPT; fi
fi
if command -v netfilter-persistent >/dev/null; then netfilter-persistent save >/dev/null 2>&1 || true
elif [ -d /etc/iptables ]; then iptables-save > /etc/iptables/rules.v4; fi

sleep 1
systemctl is-active --quiet ckbond && echo "ckbond: active on :443" || { echo "ckbond: NOT active"; journalctl -u ckbond -n 20 --no-pager; exit 1; }
