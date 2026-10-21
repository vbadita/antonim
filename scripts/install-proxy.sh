#!/usr/bin/env bash
# Install/upgrade the signing proxy on this VM: venv from the lock file,
# code, env file from Terraform outputs, systemd unit. Re-runnable.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
export SUPPRESS_LABEL_WARNING=True
fn_id=$(terraform -chdir="$root/infra" output -raw function_id)
endpoint=$(terraform -chdir="$root/infra" output -raw function_invoke_endpoint)

sudo install -d -m 0755 /opt/antonime-proxy /opt/antonime-proxy/app
if [ ! -x /opt/antonime-proxy/venv/bin/python ]; then
  sudo python3.12 -m venv /opt/antonime-proxy/venv
fi
sudo /opt/antonime-proxy/venv/bin/pip install -q --disable-pip-version-check --no-deps \
  -r "$root/proxy/requirements.txt"
sudo /opt/antonime-proxy/venv/bin/pip check
sudo install -m 0644 "$root/proxy/antonime_proxy.py" /opt/antonime-proxy/app/
sudo /opt/antonime-proxy/venv/bin/python -m compileall -q /opt/antonime-proxy/app

printf 'ANTONIME_FUNCTION_ID=%s\nANTONIME_INVOKE_ENDPOINT=%s\nANTONIME_MAX_INVOCATIONS_PER_MINUTE=6\n' \
  "$fn_id" "$endpoint" | sudo tee /etc/antonime-proxy.env >/dev/null
sudo chmod 0644 /etc/antonime-proxy.env
sudo install -m 0644 "$root/deploy/systemd/antonime-proxy.service" /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable -q antonime-proxy
sudo systemctl restart antonime-proxy
for _ in $(seq 1 20); do
  curl -sf http://127.0.0.1:8091/healthz && echo && exit 0
  sleep 0.5
done
echo "proxy did not become healthy" >&2
sudo journalctl -u antonime-proxy -n 20 --no-pager >&2
exit 1
