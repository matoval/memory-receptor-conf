#!/bin/bash
# Run this on the control node to create the large project

set -e

echo "Creating project directory..."
sudo mkdir -p /var/lib/awx/projects/large-project/files

echo "Creating large data files (4 x 512MB)..."
cd /var/lib/awx/projects/large-project/files
for i in 1 2 3 4; do
    echo "Creating file $i of 4..."
    sudo dd if=/dev/urandom of=data_$i.bin bs=1M count=512 status=progress
done

echo "Creating playbook..."
sudo tee /var/lib/awx/projects/large-project/site.yml > /dev/null <<'EOF'
---
- name: Simple test playbook
  hosts: all
  gather_facts: false
  tasks:
    - name: Echo test
      debug:
        msg: "This is a large playbook test"
EOF

echo "Setting ownership..."
sudo chown -R awx:awx /var/lib/awx/projects/large-project

echo "Done. Project size:"
sudo du -sh /var/lib/awx/projects/large-project

echo ""
echo "In AAP, create a Manual project with Playbook Directory: large-project"
