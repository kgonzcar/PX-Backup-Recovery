#!/usr/bin/env bash
set -euo pipefail

# Load govc environment if present
[ -f "$HOME/.govc_env" ] && source "$HOME/.govc_env"

# --------------------------------------------------------------------
# CONFIG
# --------------------------------------------------------------------
DATASTORES=(
  PWX-PROD-FC-VMFS-003
)
THRESHOLD=3          # delete when count >= 3
KEEP=1               # keep newest 1 snapshot

timestamp() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

echo "[$(timestamp)] Checking CNS/FCD snapshots (threshold=${THRESHOLD}, keep=${KEEP})"
echo "[$(timestamp)] Datastores: ${DATASTORES[*]}"

total_deleted=0
total_candidates=0

for ds in "${DATASTORES[@]}"; do
  echo "[$(timestamp)] Scanning datastore: ${ds}"

  FCDS=$(govc disk.ls -ds="${ds}" 2>/dev/null || true)
  if [ -z "${FCDS}" ]; then
    echo "[$(timestamp)]   No FCDs found or govc error on ${ds}"
    continue
  fi

  while read -r line; do
    [ -z "${line}" ] && continue

    fcd_id=$(echo "${line}" | awk '{print $1}')
    pv_name=$(echo "${line}" | awk '{print $2}')

    snaps=$(govc disk.snapshot.ls -l "${fcd_id}" 2>/dev/null || true)
    [ -z "${snaps}" ] && continue

    count=$(echo "${snaps}" | wc -l | awk '{print $1}')

    if (( count >= THRESHOLD )); then
      total_candidates=$(( total_candidates + 1 ))
      echo "[$(timestamp)]   FCD ${fcd_id} (PV=${pv_name}, DS=${ds}) has ${count} snapshots:"

      # Show current snapshots
      echo "${snaps}"
      echo

      # Number to delete to leave KEEP newest
      to_delete=$(( count - KEEP ))
      if (( to_delete <= 0 )); then
        echo "[$(timestamp)]   Nothing to delete (count=${count}, keep=${KEEP})"
        continue
      fi

      echo "[$(timestamp)]   Deleting ${to_delete} oldest snapshot(s) for ${fcd_id}..."
      deleted_this_fcd=0

      # Sort by date/time and take oldest N
      delete_sids=$(echo "${snaps}" \
        | sort -k3,3M -k4,4n -k5,5 \
        | head -n "${to_delete}" \
        | awk '{print $1}')

      for sid in ${delete_sids}; do
        echo "[$(timestamp)]     govc disk.snapshot.rm ${fcd_id} ${sid}"
        if govc disk.snapshot.rm "${fcd_id}" "${sid}" 2>/dev/null; then
          deleted_this_fcd=$(( deleted_this_fcd + 1 ))
          total_deleted=$(( total_deleted + 1 ))
        else
          echo "[$(timestamp)]       WARN: failed to delete ${sid} on ${fcd_id}"
        fi
      done

      # Show remaining snapshots
      remaining=$(govc disk.snapshot.ls -l "${fcd_id}" 2>/dev/null || true)
      echo "[$(timestamp)]   Remaining snapshots for ${fcd_id}:"
      echo "${remaining:-<none>}"
      echo "[$(timestamp)]   Deleted ${deleted_this_fcd} snapshot(s) for ${fcd_id}"
      echo
    fi
  done <<< "${FCDS}"
done

echo "[$(timestamp)] Snapshot cleanup pass completed."
echo "[$(timestamp)] Summary: candidates=${total_candidates}, deleted=${total_deleted}"