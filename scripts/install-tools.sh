#!/usr/bin/env bash
# Pinned CLI tools for this project (linux/arm64 VM). Re-runnable.
#   OCI CLI   -> /opt/oci-cli venv (+ transitive pins in oci-cli-constraints.txt)
#   Terraform -> /usr/local/bin/terraform, checksum file verified with HashiCorp's GPG key
set -euo pipefail
OCI_CLI_VERSION=3.94.2
TERRAFORM_VERSION=1.16.5
# HashiCorp release signing key: https://www.hashicorp.com/trust/security
HASHICORP_KEY_FPR=C874011F0AB405110D02105534365D9472D7468F
HERE=$(cd "$(dirname "$0")" && pwd)

# ---- OCI CLI ----
sudo rm -rf /opt/oci-cli
sudo python3.12 -m venv /opt/oci-cli
sudo /opt/oci-cli/bin/pip install -q --disable-pip-version-check \
  "oci-cli==${OCI_CLI_VERSION}" -c "$HERE/oci-cli-constraints.txt"
/opt/oci-cli/bin/pip check
sudo ln -sf /opt/oci-cli/bin/oci /usr/local/bin/oci

# ---- Terraform ----
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
base=https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}
zip=terraform_${TERRAFORM_VERSION}_linux_arm64.zip
sums=terraform_${TERRAFORM_VERSION}_SHA256SUMS
curl -sSfL -o "$tmp/$zip" "$base/$zip"
curl -sSfL -o "$tmp/$sums" "$base/$sums"
curl -sSfL -o "$tmp/$sums.sig" "$base/$sums.sig"
curl -sSfL -o "$tmp/hashicorp.asc" https://www.hashicorp.com/.well-known/pgp-key.txt
export GNUPGHOME="$tmp/gnupg"; mkdir -m 700 "$GNUPGHOME"
gpg -q --import "$tmp/hashicorp.asc"
gpg --fingerprint --with-colons | grep -q "^fpr:::::::::${HASHICORP_KEY_FPR}:" \
  || { echo "unexpected HashiCorp key fingerprint" >&2; exit 1; }
gpg -q --verify "$tmp/$sums.sig" "$tmp/$sums"         # the checksum file is genuine
(cd "$tmp" && grep " ${zip}\$" "$sums" | sha256sum -c -)  # the zip matches it
python3 -c 'import sys,zipfile; zipfile.ZipFile(sys.argv[1]).extract("terraform", sys.argv[2])' "$tmp/$zip" "$tmp"
sudo install -m 0755 "$tmp/terraform" /usr/local/bin/terraform

oci --version
terraform version
