#!/usr/bin/env bash
# Install the antonim nginx snippets on this VM and reload nginx. Re-runnable.
# Expects the apps.badita.com server block (anm-shortage-history repo) to contain
#   include /etc/nginx/apps.badita.com.d/*.conf;
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"

grep -q 'include /etc/nginx/apps.badita.com.d/\*.conf;' /etc/nginx/conf.d/apps.badita.com.conf \
  || { echo "apps.badita.com.conf lacks the apps.badita.com.d include" >&2; exit 1; }

sudo install -d -m 0755 /etc/nginx/apps.badita.com.d
sudo install -m 0644 "$root/deploy/nginx/antonim-zones.conf" /etc/nginx/conf.d/
sudo install -m 0644 "$root/deploy/nginx/antonim.conf" "$root/deploy/nginx/antonim-headers.inc" /etc/nginx/apps.badita.com.d/
sudo install -d -m 0700 -o nginx -g nginx /var/cache/nginx/antonim
sudo restorecon -R /etc/nginx /var/cache/nginx

# SELinux: nginx (httpd_t) may only connect to ports labelled http_port_t
# (httpd_can_network_relay is already on). Label the proxy's port once.
if ! sudo semanage port -l | grep -E '^http_port_t' | grep -qw 8091; then
  sudo semanage port -a -t http_port_t -p tcp 8091
fi

sudo nginx -t
sudo systemctl reload nginx
