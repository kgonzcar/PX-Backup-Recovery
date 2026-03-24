#!/usr/bin/env bash
set -euo pipefail

# Load govc environment if present
[ -f "$HOME/.govc_env" ] && source "$HOME/.govc_env"

#--------------------------------------------------------------------
# CONFIG
# --------------------------------------------------------------------
# Datastores to scan (members of your PXW-ISCSI/FC datastore clusters)
DATASTORES=(
  PWX-PROD-FC-VMFS-003
)

# Snapshot count threshold
THRESHOLD=3

timestamp() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

echo "[$(timestamp)] Checking CNS/FCD snapshots (threshold=${THRESHOLD})"
echo "[$(timestamp)] Datastores: ${DATASTORES[*]}"

FOUND=0

for ds in "${DATASTORES[@]}"; do
  echo "[$(timestamp)] Scanning datastore: ${ds}"

  # List all FCDs on this datastore: "<FCD-ID>  <pv-name>"
  FCDS=$(govc disk.ls -ds="${ds}" 2>/dev/null || true)

  if [ -z "${FCDS}" ]; then
    echo "[$(timestamp)]   No FCDs found or govc error on ${ds}"
    continue
  fi

  while read -r line; do
    # Skip empty lines
    [ -z "${line}" ] && continue

    fcd_id=$(echo "${line}" | awk '{print $1}')
    pv_name=$(echo "${line}" | awk '{print $2}')

    # List snapshots for this FCD
    snaps=$(govc disk.snapshot.ls -l "${fcd_id}" 2>/dev/null || true)
    [ -z "${snaps}" ] && continue

    count=$(echo "${snaps}" | wc -l | awk '{print $1}')

    if (( count >= THRESHOLD )); then
      FOUND=1
      echo "[$(timestamp)]   FCD ${fcd_id} (PV=${pv_name}, DS=${ds}) has ${count} snapshots:"
      echo "${snaps}"
      echo
    fi
  done <<< "${FCDS}"
done

if (( FOUND == 0 )); then
  echo "[$(timestamp)] All FCDs are below snapshot threshold (${THRESHOLD})."
fi