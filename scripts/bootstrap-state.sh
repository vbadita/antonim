#!/usr/bin/env bash
# One-time: the Object Storage bucket that holds Terraform state.
# Terraform cannot create the bucket its own backend lives in (chicken and egg),
# so this is the only resource created outside Terraform. Re-runnable.
set -euo pipefail
BUCKET=antonime-tfstate
COMPARTMENT_NAME=antonime
export SUPPRESS_LABEL_WARNING=True
tenancy=$(awk -F= '/^tenancy=/{print $2}' ~/.oci/config)
compartment=$(oci iam compartment list --compartment-id "$tenancy" --name "$COMPARTMENT_NAME" \
  --query 'data[0].id' --raw-output)
if oci os bucket get --bucket-name "$BUCKET" >/dev/null 2>&1; then
  echo "bucket $BUCKET exists"
else
  # NoPublicAccess: state contains resource details. Versioning: every state
  # write is kept, so a corrupted/deleted state can be restored.
  oci os bucket create --compartment-id "$compartment" --name "$BUCKET" \
    --public-access-type NoPublicAccess --versioning Enabled --storage-tier Standard >/dev/null
  echo "bucket $BUCKET created"
fi
oci os bucket get --bucket-name "$BUCKET" \
  --query 'data.{name:name,namespace:namespace,public:"public-access-type",versioning:versioning,tier:"storage-tier"}' \
  --output table
