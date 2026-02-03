# Reproducer: "Failed to JSON parse a line from worker stream"

## Root Cause

When AAP executes a job via receptor:
1. Job data is transmitted to the execution node
2. Receptor writes work unit data to `/tmp/receptor/<node>/<workunit>/`
3. Job output (JSON events) is written to the `stdout` file
4. If disk fills during execution, the stdout file gets truncated
5. The controller fails to parse the truncated JSON

## What Doesn't Work

We tested several approaches that did NOT trigger the error:

### Large files in role files/ directory
- Files referenced by `copy` module are transferred via scp/sftp during task execution
- They are NOT transmitted upfront with the job
- Ansible fails gracefully with "No space left on device"

### Collections in requirements.yml
- Collections are installed on the execution node during project sync
- They are NOT transmitted with each job
- Disk usage on exec node doesn't change during job execution

## What Works: Concurrent Jobs

The error is triggered when multiple concurrent jobs fill the disk with their work units.

## Project Structure

```
disk-json-error/
├── roles/
│   └── largefiles/
│       ├── files/
│       │   └── .gitkeep
│       └── tasks/
│           └── main.yml
├── site.yml          # Generates massive output
└── README.md
```

## Reproduction Steps

### 1. Set Up AAP Project

1. Create a Git project pointing to this repo
2. Or use Manual project and copy files to `/var/lib/awx/projects/`
3. Sync the project

### 2. Create Instance Group

1. Administration → Instance Groups → Add
2. Name: e.g., "exec-group"
3. Add your execution node to this instance group

### 3. Create Job Template

1. Resources → Templates → Add → Job Template
2. Name: "fill disk" (or similar)
3. Project: your project
4. Playbook: `disk-json-error/site.yml`
5. Inventory: any inventory with hosts reachable from exec node
6. Instance Groups: select the instance group with your exec node
7. **Enable "Concurrent jobs"** checkbox
8. Under Troubleshooting Settings:
   - Enable **"Keep receptor work on error"** (helps debugging)
9. Save

### 4. Pre-fill Execution Node Disk

SSH to execution node and fill disk leaving ~300-500MB free:

```bash
df -h /tmp

# Calculate how much to fill based on available space
# Example: if 10GB free, fill ~9.5GB
sudo fallocate -l <size>M /tmp/fill-disk

df -h /tmp
```

### 5. Launch Multiple Concurrent Jobs

1. Open the job template
2. Click Launch multiple times quickly (10-15 jobs)
3. Or open multiple browser tabs and launch simultaneously

The concurrent work units will fill the remaining disk space.

### 6. Monitor Execution Node

While jobs run, monitor on exec node:

```bash
watch -n 0.5 'df -h /tmp; sudo ls -la /tmp/receptor/<exec-node>/ 2>/dev/null; sudo du -sh /tmp/receptor/<exec-node>/*/* 2>/dev/null'
```

### Expected Result

When disk fills during job execution, you should see:
```
Failed to JSON parse a line from worker stream
```

### Cleanup

```bash
# On execution node
sudo rm -f /tmp/fill-disk /tmp/fill-disk2 /tmp/fill-disk3

# Clear stuck receptor work units if needed
sudo rm -rf /tmp/receptor/<exec-node>/aapcontrollocal*
```

## Troubleshooting

### Jobs stuck at "Running" with no progress
- Disk is 100% full - free some space with `sudo rm -f /tmp/fill-disk*`
- Jobs need some space to make progress before filling disk

### Jobs queue instead of running concurrently
- Edit job template and enable **"Concurrent jobs"** checkbox
- Ensure instance group has capacity for multiple jobs

### Receptor logs
```bash
sudo journalctl -u receptor -f
```

### Work unit contents
```bash
sudo ls -la /tmp/receptor/<exec-node>/*/
sudo cat /tmp/receptor/<exec-node>/*/status
```
