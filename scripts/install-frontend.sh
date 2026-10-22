#!/usr/bin/env bash
# Install the pull-based page deployer on this VM. Re-runnable.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"

id antonime-web >/dev/null 2>&1 || sudo useradd --system --no-create-home --shell /usr/sbin/nologin antonime-web
sudo install -d -m 0755 -o antonime-web -g antonime-web /srv/antonim
# SELinux: nginx (httpd_t) may read httpd_sys_content_t; new files inherit it.
if ! sudo semanage fcontext -l | grep -q '^/srv/antonim(/.\*)?'; then
  sudo semanage fcontext -a -t httpd_sys_content_t '/srv/antonim(/.*)?'
fi
sudo restorecon -R /srv/antonim

sudo install -m 0755 "$root/scripts/frontend-sync.sh" /usr/local/libexec/antonime-frontend-sync
sudo install -m 0644 "$root/deploy/systemd/antonime-frontend-sync.service" \
  "$root/deploy/systemd/antonime-frontend-sync.timer" /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable -q --now antonime-frontend-sync.timer
sudo systemctl start antonime-frontend-sync.service   # first sync now
sudo journalctl -u antonime-frontend-sync -n 1 --no-pager -o cat
