# Reproducer: "Failed to JSON parse a line from worker stream"

## Root Cause

When AAP executes a job, it:
1. Copies the **entire project directory** (including collections) to a job runtime directory
2. Base64 encodes the runtime directory and sends it to receptor
3. Receptor writes this to `/tmp/receptor/<node>/<workunit>/stdin`
4. Job output is written to `/tmp/receptor/<node>/<workunit>/stdout`

If disk fills during transmission or execution, the stdout file gets truncated,
causing invalid JSON that triggers: `Failed to JSON parse a line from worker stream`

## Project Structure

```
disk-json-error/
├── collections/
│   └── requirements.yml    # Large collections (~200MB+ total)
├── site.yml                # Simple playbook using the collections
└── README.md
```

The collections specified in `requirements.yml` total ~200MB+:
- azure.azcollection (~50MB)
- amazon.aws (~30MB)
- google.cloud (~30MB)
- cisco.aci (~20MB)
- vmware.vmware_rest (~25MB)
- kubernetes.core (~15MB)
- community.vmware (~30MB)
- community.aws (~25MB)

## Reproduction Steps

### 1. Push to Git and Create Project in AAP

```bash
cd ~/repos/memory-receptor-conf
git add disk-json-error/
git commit -m "Add JSON parse error reproducer with large collections"
git push
```

In AAP:
1. Create Project pointing to this git repo
2. Set **Playbook Directory** to `disk-json-error` (or leave empty if using full repo)
3. Sync the project - this will install the collections

### 2. Create Job Template

1. Create Job Template
2. Project: (the project you created)
3. Playbook: `disk-json-error/site.yml` (or `site.yml` if using subdirectory)
4. Inventory: any inventory with hosts on the execution node

### 3. Pre-fill Execution Node Disk

SSH to execution node:
```bash
df -h /tmp

# Fill disk leaving ~200MB free (less than the collections size)
# Adjust size based on available space
sudo fallocate -l <size>M /tmp/fill-disk

df -h /tmp
```

### 4. Run the Job

Launch the job. The large collections (~200MB+) will be transmitted via receptor.
With insufficient disk space, the transmission should fail mid-write.

Expected error: `Failed to JSON parse a line from worker stream`

### 5. Check Logs

On execution node:
```bash
journalctl -u receptor -n 100 --no-pager | grep -i "space\|error\|json"
ls -la /tmp/receptor/
```

### Cleanup

```bash
sudo rm -f /tmp/fill-disk
```

## Alternative: Multiple Concurrent Jobs

Instead of pre-filling disk:
1. Create multiple job templates using this project
2. Launch 10+ jobs simultaneously
3. The concurrent collection transmissions may fill the disk
