# Ansible Automation for Homelab

This Ansible setup automates the rendering and deployment of your templated homelab configuration files to remote servers.

## Prerequisites

1. **Install Ansible**:
   ```bash
   # On macOS
   brew install ansible
   
   # On Ubuntu/Debian
   sudo apt update && sudo apt install ansible
   
   # Using pip
   pip install ansible
   ```

2. **SSH Access**: Ensure you have SSH key access to all target hosts. The default configuration expects:
   - SSH key at `~/.ssh/id_rsa`
   - Root access to target hosts
   - Host key checking is disabled in the config

## Project Structure

```
homelab/
├── ansible.cfg                          # Ansible configuration
├── ansible/
│   ├── inventories/
│   │   └── production                   # Inventory file with host definitions
│   ├── playbooks/
│   │   └── deploy.yml                   # Main deployment playbook
│   ├── group_vars/
│   │   └── homelab.yml                  # Variables for all homelab hosts
│   └── host_vars/                       # Host-specific variables (optional)
├── vars.yml                             # Your existing template variables
└── tools/render_src.sh                  # Your existing render script
```

## Usage

### Deploy to All Hosts

Deploy rendered configuration to all hosts defined in the inventory:

```bash
ansible-playbook ansible/playbooks/deploy.yml
```

### Deploy to Specific Hosts

Deploy only to specific hosts or groups:

```bash
# Deploy to single host
ansible-playbook ansible/playbooks/deploy.yml --limit secsvcs

# Deploy to multiple specific hosts  
ansible-playbook ansible/playbooks/deploy.yml --limit "secsvcs,homesvcs"

# Deploy to a group (if you create groups in inventory)
ansible-playbook ansible/playbooks/deploy.yml --limit production
```

### Check What Would Be Deployed

Use check mode to see what would change without actually deploying:

```bash
ansible-playbook ansible/playbooks/deploy.yml --check
```

### Verbose Output

For troubleshooting, use verbose mode:

```bash
ansible-playbook ansible/playbooks/deploy.yml -v   # Basic verbose
ansible-playbook ansible/playbooks/deploy.yml -vv  # More verbose
ansible-playbook ansible/playbooks/deploy.yml -vvv # Debug level
```

## Configuration

### Inventory File

Edit `ansible/inventories/production` to:
- Add/remove hosts
- Change IP addresses
- Modify SSH connection settings
- Set host-specific variables

Example inventory entry:
```ini
hostname ansible_host=192.168.1.100 remote_config_path=/custom/path
```

### Variables

**Global variables** in `ansible/group_vars/homelab.yml`:
- `cleanup_rendered`: Whether to clean up local rendered files (default: true)
- `ansible_ssh_common_args`: Common SSH arguments

**Host-specific variables** can be set in:
- Inventory file (inline)
- `ansible/host_vars/hostname.yml` files

**Available variables**:
- `remote_config_path`: Target directory on remote host (default: `/opt/homelab`)
- `remote_user`: Owner of deployed files (default: `root`)
- `remote_group`: Group of deployed files (default: `root`)

### SSH Configuration

The setup assumes SSH key authentication. To customize:

1. **Change SSH key**: Edit `ansible_ssh_private_key_file` in inventory
2. **Change SSH user**: Edit `ansible_user` in inventory  
3. **SSH options**: Modify `ansible_ssh_common_args` in group_vars

## How It Works

The deployment process:

1. **Loads variables** from your existing `vars.yml` file
2. **Renders configuration** using your existing `tools/render_src.sh` script  
3. **Validates** the rendered files (YAML, JSON, IP uniqueness)
4. **Synchronizes** files to each target host using rsync
5. **Sets proper ownership** and permissions
6. **Cleans up** temporary rendered files

**Important Note**: Your render script processes ALL files through Jinja2 templating, not just those with `.j2` extensions. Files that do have `.j2` extensions undergo a second rendering pass at service startup time (as handled by your services like `src/podman/render_secrets.sh`).

## Troubleshooting

### Common Issues

**SSH connection failures**:
```bash
# Test SSH connectivity
ansible all -m ping

# Test with specific user
ansible all -m ping -u your-username --ask-pass
```

**Permission denied**:
- Ensure your SSH key is added to target hosts
- Check that the ansible user has sudo privileges
- Verify file permissions on SSH keys

**Render script failures**:
- Run `tools/render_src.sh /tmp/test` manually to debug
- Check that all required tools (jinjanate, yamllint, jq, fdfind) are installed locally

### Debug Commands

```bash
# List all hosts
ansible-inventory --list

# Test connectivity
ansible all -m ping

# Check variables for a host
ansible-inventory --host secsvcs

# Run a command on all hosts
ansible all -m shell -a "ls -la /opt/homelab"
```

## Migration from Manual Process

To replace your current manual workflow:

1. **Test first**: Run with `--check` mode
2. **Deploy to one host**: Use `--limit hostname` 
3. **Verify deployment**: Check files on target host
4. **Deploy to all**: Remove `--limit` when confident

Your original `tools/render_src.sh` script continues to work unchanged - Ansible simply automates calling it and uploading the results.