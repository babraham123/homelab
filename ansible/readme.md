I've set up a complete Ansible project for automating your homelab deployment. Here's what was
created:

Project Structure

- ansible.cfg - Main Ansible configuration
- ansible/inventories/production - Inventory file with your 5 hosts
- ansible/playbooks/deploy.yml - Main deployment playbook
- ansible/group_vars/homelab.yml - Common variables
- docs/ansible-usage.md - Comprehensive documentation

Key Features

- Uses your existing tools/render_src.sh script unchanged
- Handles your templating system (all files rendered via Jinja2, .j2 files get second pass at
runtime)
- Deploys to all hosts from vars.yml (secsvcs, websvcs, homesvcs, gaming, devtop)
- Includes validation, cleanup, and proper file ownership
- Supports selective deployment with --limit option

Quick Start

# Install Ansible
brew install ansible  # macOS

# Deploy to all hosts
ansible-playbook ansible/playbooks/deploy.yml

# Deploy to specific host
ansible-playbook ansible/playbooks/deploy.yml --limit secsvcs

# Test without changes
ansible-playbook ansible/playbooks/deploy.yml --check

The setup preserves your existing workflow while automating the manual steps. Check
docs/ansible-usage.md for detailed usage instructions and troubleshooting.