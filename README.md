# PX-Backup Restore Ansible Project

This project automates:

- **PX-Backup configuration** (BackupLocations + SchedulePolicy + ApplicationBackupSchedule)
- **PX-Backup restore** to a secondary cluster from an existing `ApplicationBackup`
- **Optional vSphere FCD snapshot cleanup** using `govc`
- **Cleanup** of the above PX-Backup objects

## Prerequisites

1. (Recommended) Create/activate a Python virtual environment for Ansible.
```shell
python3 -m venv ~/.venvs/ansible-px
source ~/.venvs/ansible-px/bin/activate
```
2. Stork Installed on both clusters

3. Bootstrap Ansible Kubernetes dependencies (once per env). From the project root, run the Kubernetes bootstrap playbook **once** to install the required collection and Python libraries:
```shell
ansible-playbook bootstrap_k8s.yaml
```
This is equivalent to:
- `ansible-galaxy collection install kubernetes.core`
- `pip install kubernetes openshift`

4. Configure **PX-Backup backend settings**:
   - Edit non-secret settings in:
     `vars/pxb_recovery.yaml`

     This file defines:

       - Cluster access (`kubeconfig_primary`, `kubeconfig_secondary`)
       - Backend selection (`pxb_recovery_configuration_backup_location_type: azure|s3|nfs`)
       - Non-secret structure for Azure / S3 / NFS BackupLocations
       - Application backup/restore names and namespaces

   - Store all **sensitive** backend details in a vaulted file. Start from the
     committed example template and encrypt the copy:
     ```shell
     cp vars/pxb_recovery.secrets.yaml.example vars/pxb_recovery.secrets.yaml
     # edit vars/pxb_recovery.secrets.yaml with real values
     ansible-vault encrypt vars/pxb_recovery.secrets.yaml
     ```
     Only populate the block matching your `pxb_recovery_configuration_backup_location_type` (Azure, S3, or NFS).
     The plaintext copy is excluded by `.gitignore`; the `.example` template is committed.
     The non-secret file (`pxb_recovery.yaml`) references these vaulted vars via `pxb_*` names, and will only use the ones that pertain to your backup location.

You must complete these steps before running any playbooks that use `kubernetes.core.k8s` and the PX Backup roles.

## How to Run Recovery Configuration (Initial configuration)

This phase creates/maintains:

- `BackupLocation` (Azure / S3 / NFS) on **both** clusters
- `SchedulePolicy` for PX-Backup 
- `ApplicationBackupSchedule` for PX-Backup on the `primary` cluster (cluster where PX Backup is installed)

1. Edit `vars/pxb_recovery.yaml`:
- Set `kubeconfig_primary` and `kubeconfig_secondary` filepath location
- Choose a backend with: `pxb_recovery_configuration_backup_location_type: azure|s3|nfs`
- Ensure the matching block is correct:
  - `pxb_recovery_configuration_backup_location_azure` for Azure
  - `pxb_recovery_configuration_backup_location_s3` for S3 (FlashBlade or AWS)
  - `pxb_recovery_configuration_backup_location_nfs` for NFS (FlashArray or generic NFS)
- Set namespaces and backup/restore names as needed (e.g. `pxb_recovery_configuration_namespace`, `pxb_recovery_configuration_app_namespace`, `pxb_recovery_configuration_app_backup_schedule_name`, `pxb_restore_name`, `pxb_restore_backup_name`).

2. Create or edit `vars/pxb_recovery.secrets.yaml` (via `ansible-vault create` or `ansible-vault edit`) to ensure all backend secrets (paths, endpoints, keys, NFS server/export) are correct.

3. From the project root, run the PX-Backup workflow:
```shell
ansible-playbook px_backup_recovery_configuration_runbook.yaml --ask-vault-pass
```
This will:

- Create the appropriate `BackupLocation` (Azure/S3/NFS) on both clusters using manifest templates under: `roles/pxb_recovery_configuration/templates/`.
- Create the `Schedule-Policy` for the `ApplicationBackupSchedule` on primary cluster.
- Create the `ApplicationBackupSchedule` for PX Backup on primary cluster.

## How to Run PX Backup Restore 

This phase restores PX-Backup onto the **secondary** cluster from a chosen existing `ApplicationBackup` CR.

1. Ensure the configuration phase has been run successfully (BackupLocation + SchedulePolicy + ApplicationBackupSchedule exist and backups are being taken).

2. Confirm/override the backup to restore from:

- Default in `vars/pxb_recovery.yaml`: 
```shell
pxb_restore_backup_name: backup-px-backup   # ApplicationBackup CR name
```
- You can override this at runtime:
```shell
ansible-playbook px_backup_restore_runbook.yaml \
  --ask-vault-pass \
  -e pxb_restore_backup_name=<ApplicationBackup_CR_name>
```

3. From the project root, run the PX-Backup restore workflow:
```shell
ansible-playbook px_backup_restore_runbook.yaml --ask-vault-pass
```
This will:

- Verify connectivity to the secondary cluster.
- Verify Stork is present on the secondary.
- Create an `ApplicationRestore` on the secondary cluster using the template under: 
`roles/pxb_restore/templates/application_restore.yaml`


## How to Run PX Backup Cleanup (Teardown)

This phase removes the objects created by the configuration/restore phases:

- `ApplicationRestore` (secondary)
- `ApplicationBackupSchedule` (primary)
- `SchedulePolicy` (primary)
- `BackupLocation(s)` on both clusters for the selected backend

Run:
```shell
ansible-playbook px_backup_cleanup_runbook.yaml --ask-vault-pass
```
This is safe to re-run; tasks are written to be idempotent and tolerant of already-absent objects.

> **Note:** Cleanup only removes Stork objects from the clusters. The underlying
> bucket / NFS share is **not** wiped. Because the BackupLocation manifests are
> created with `sync: true`, a Stork instance pointed at the same bucket may
> re-import a `BackupLocation` after deletion. To fully decommission, delete or
> rotate credentials on the backend storage as well.


## vSphere Snapshot Cleanup (optional)

This project includes an optional runbook to check and clean up CNS/FCD snapshots in vSphere using `govc`.

### Prerequisites

1. Ensure `govc` is installed on the machine where you run Ansible, e.g.:
- brew install govmomi/tap/govc

  or
- which govc

  Update `vsphere_fcd_cleanup_govc_binary_path` in `vars/vsphere_fcd_cleanup.yaml` if needed (default: `/opt/homebrew/bin/govc`).

2. Configure non-secret settings in:
- `vars/vsphere_fcd_cleanup.yaml`
  - Datastores, thresholds (`vsphere_fcd_cleanup_datastores`, `vsphere_fcd_cleanup_threshold`, `vsphere_fcd_cleanup_keep`)
  - Script directory (`vsphere_fcd_cleanup_script_dir`, default `/tmp/fcd_cleanup`)
  - Run mode (`vsphere_fcd_cleanup_run_mode`: `check`, `cleanup`, or `both`)
  - Cron behavior: (`vsphere_fcd_cleanup_install_cron: false`)

3. Store vSphere credentials securely. Start from the committed example
   template and encrypt the copy:
   ```shell
   cp vars/vsphere_fcd_cleanup.secrets.yaml.example vars/vsphere_fcd_cleanup.secrets.yaml
   # edit vars/vsphere_fcd_cleanup.secrets.yaml with real vCenter credentials
   ansible-vault encrypt vars/vsphere_fcd_cleanup.secrets.yaml
   ```
   The plaintext copy is excluded by `.gitignore`; the `.example` template is committed.

### How to run the FCD Cleanup Runbook

Use the provided playbook (name: `fcd_cleanup_runbook.yaml`)

```yaml
---
- name: Deploy and run vSphere FCD snapshot cleanup
  hosts: localhost
  gather_facts: true
  vars_files:
    - vars/vsphere_fcd_cleanup.yaml
    - vars/vsphere_fcd_cleanup.secrets.yaml
  roles:
    - vsphere_fcd_cleanup
```

Run it:
```shell
ansible-playbook fcd_cleanup_runbook.yaml --ask-vault-pass
```

Control behavior via `vsphere_fcd_cleanup_run_mode` in `vars/vsphere_fcd_cleanup.yaml`:

- `check`   – only list/count snapshots
- `cleanup` – only delete oldest snapshots above threshold
- `both`    – run check, then cleanup

By default, no cron is installed (`vsphere_fcd_cleanup_install_cron: false`). If you enable cron, it will run the cleanup script from `/tmp/fcd_cleanup` and log to `/tmp/px_fcd_cleanup.log`.
