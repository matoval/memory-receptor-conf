# Reproducer: "Failed to JSON parse a line from worker stream"

## Root Cause

When AAP executes a job, it:
1. Copies the **entire project directory** (including role files/) to a job runtime directory
2. Base64 encodes the runtime directory and sends it to receptor
3. Receptor writes this to `/tmp/receptor/<node>/<workunit>/stdin`
4. Job output is written to `/tmp/receptor/<node>/<workunit>/stdout`

If disk fills during transmission or execution, the stdout file gets truncated,
causing invalid JSON that triggers: `Failed to JSON parse a line from worker stream`

## Project Structure

```
disk-json-error/
├── roles/
│   └── largefiles/
│       ├── files/
│       │   ├── data_1.bin   # 512MB - created on control node
│       │   ├── data_2.bin   # 512MB - created on control node
│       │   ├── data_3.bin   # 512MB - created on control node
│       │   └── data_4.bin   # 512MB - created on control node
│       └── tasks/
│           └── main.yml     # copy tasks that reference the files
├── site.yml                 # playbook using the largefiles role
└── README.md
```

## Reproduction Steps

### 1. Clone/Sync Project to Control Node

The project must be available in `/var/lib/awx/projects/`. Either:
- Use a Git project that syncs this repo
- Use a Manual project and copy files

### 2. Create Large Files on Control Node

SSH to control node and create the data files in the role's files/ directory:

```bash
PROJECT_DIR="/var/lib/awx/projects/<your-project-name>/disk-json-error"

cd "$PROJECT_DIR/roles/largefiles/files"

for i in 1 2 3 4; do
  echo "Creating file $i of 4 (512MB)..."
  sudo dd if=/dev/urandom of=data_$i.bin bs=1M count=512 status=progress
done

sudo chown -R awx:awx "$PROJECT_DIR"
sudo du -sh "$PROJECT_DIR"
```

### 3. Create Job Template in AAP

1. Project pointing to this repo (or manual project)
2. Playbook: `disk-json-error/site.yml`
3. Inventory with hosts on the execution node

### 4. Pre-fill Execution Node Disk

SSH to execution node:
```bash
df -h /tmp

# Fill disk leaving ~500MB free (less than the 2GB project)
sudo fallocate -l <size>M /tmp/fill-disk

df -h /tmp
```

### 5. Run the Job

Launch the job. The 2GB of files in the role will be transmitted via receptor.
With insufficient disk space, the transmission should fail mid-write.

Monitor on exec node during job:
```bash
watch -n 0.5 'df -h /tmp; du -sh /tmp/receptor/*/* 2>/dev/null | tail -5'
```

Expected error: `Failed to JSON parse a line from worker stream`

### Cleanup

```bash
# On execution node
sudo rm -f /tmp/fill-disk /tmp/data_*.bin

# On control node (optional)
sudo rm -f $PROJECT_DIR/roles/largefiles/files/data_*.bin
```
