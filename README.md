# PX-Backup Restore Ansible Project

## Prerequisites

1. (Recommended) Create/activate a Python virtual environment for Ansible.
2. Stork Installed on both clusters

3. From the project root, run the Kubernetes bootstrap playbook **once** to install the required collection and Python libraries:
```shell
ansible-playbook bootstrap_k8s.yaml
```
This is equivalent to:
- ansible-galaxy collection install kubernetes.core
- pip install kubernetes openshift

4. Configure **PX-Backup backend settings**:
   - Edit non-secret settings in:
     `vars/pxb_recovery.yml`

     This file defines:

       - Cluster access (`kubeconfig_primary`, `kubeconfig_secondary`)
       - Backend selection (`backup_location_type: azure|s3|nfs`)
       - Non-secret structure for Azure / S3 / NFS BackupLocations
       - Application backup/restore names and namespaces

   - Store all **sensitive** backend details in a vaulted file:
     `ansible-vault create vars/pxb_recovery.secrets.yaml`
   
     ```yaml
     pxb_azure_path: "YOUR_AZURE_PATH"
     pxb_azure_storage_account_name: "AZURE_ACCOUNT_NAME"
     pxb_azure_storage_account_key: "AZURE_STORAGE_KEY_HERE"
     
     # S3 BackupLocation secrets
     pxb_s3_path: "pxbackup-bucket/prefix"
     pxb_s3_endpoint: "https://fb-s3.example.com"       # or AWS endpoint
     pxb_s3_access_key: "S3_ACCESS_KEY_HERE"
     pxb_s3_secret_key: "S3_SECRET_KEY_HERE"
     
     # NFS BackupLocation secrets
     pxb_nfs_server: "10.0.0.50"
     pxb_nfs_export_path: "/pxbackup"
     pxb_nfs_path: "pxbackup-data"   
     ```
     The non-secret file (`pxb_recovery.yml`) references these vaulted vars via `pxb_*` names.

You must complete these steps before running any playbooks that use kubernetes.core.k8s and the pxb_recovery role.

## How to Run (PX-Backup Cross-Cluster Recovery)

1. Edit vars/pxb_recovery.yml:
- Set kubeconfig_primary and kubeconfig_secondary
- Choose a backend with backup_location_type: azure|s3|nfs
- Ensure the matching block is correct:
  - backup_location_azure for Azure
  - backup_location_s3 for S3 (FlashBlade or AWS)
  - backup_location_nfs for NFS (FlashArray or generic NFS)
- Set namespaces and backup/restore names as needed.

2. Edit vars/pxb_recovery.secrets.yaml (via ansible-vault edit) to ensure all backend secrets (paths, endpoints, keys, NFS server/export) are correct.

3. From the project root, run the PX-Backup workflow:
```shell
ansible-playbook px_backup_recovery.yaml --ask-vault-pass
```
This will:

- Create the appropriate `BackupLocation` (Azure/S3/NFS) on both clusters using manifest templates under `roles/pxb_recovery/files/`.
- Create a custom `Schedule-Policy` for the `ApplicationBackupSchedule`
- Create the `ApplicationBackupSchedule` for PX-Backup.
- Create the `ApplicationRestore` on the secondary cluster using the specified backup.


## vSphere Snapshot Cleanup (optional)

This project includes an optional runbook to check and clean up CNS/FCD snapshots in vSphere using `govc`.

### Prerequisites

1. Ensure `govc` is installed on the machine where you run Ansible, e.g.:
- brew install govmomi/tap/govc 

or
- which govc

Update `govc_binary_path` in `vars/vsphere_fcd_cleanup.yaml` if needed (default: `/opt/homebrew/bin/govc`).

2. Configure non-secret settings in:
- vars/vsphere_fcd_cleanup.yaml
  - Datastores, thresholds (`fcd_datastores`, `fcd_threshold`, `fcd_keep`)
  - Script directory (`fcd_script_dir`, default `/tmp/fcd_cleanup`)
  - Run mode (`fcd_run_mode`: `check`, `cleanup`, or `both`)

3. Store vSphere credentials securely in an Ansible Vault file:
   - ansible-vault create vars/vsphere_fcd_cleanup.secrets.yaml
     Example contents:
     govc_url: "YOUR_VCENTER_URL"
     govc_username: "YOUR_VCENTER_USERNAME"
     govc_password: "YOUR_REAL_PASSWORD_HERE"

### How to run the FCD Cleanup Runbook

Use the provided playbook (name: `fcd_cleanup_runbook.yaml`)

```yaml
---
- name: Deploy and run vSphere FCD snapshot cleanup
  hosts: local
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

Control behavior via `fcd_run_mode` in `vars/vsphere_fcd_cleanup.yaml`:

- `check`   – only list/count snapshots
- `cleanup` – only delete oldest snapshots above threshold
- `both`    – run check, then cleanup

By default, no cron is installed (`fcd_install_cron: false`). If you enable cron, it will run the cleanup script from `/tmp/fcd_cleanup` and log to `/tmp/px_fcd_cleanup.log`.
