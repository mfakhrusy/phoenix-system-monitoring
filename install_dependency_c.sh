sudo apt -y update && \
sudo apt -y upgrade && \
sudo apt -y install \
    build-essential \
    qemu-kvm \
    uvtool \
    libvirt-dev \
    libvirt-daemon-system \
    virt-manager \
    virt-top

sudo usermod -aG libvirt $USER
sudo usermod -aG kvm $USER

# Install noble uvtool
sudo uvt-simplestreams-libvirt --verbose sync release=noble arch=amd64

# add ssh for vms

# Create SSH key only if missing
if [ ! -f "$HOME/.ssh/id_rsa.pub" ]; then
  ssh-keygen -t rsa -b 4096 -f "$HOME/.ssh/id_rsa" -N ""
fi

# Append relaxed SSH config (without overwriting existing)
SSH_CFG="$HOME/.ssh/config"
if ! grep -q "Host 192.168.*" "$SSH_CFG" 2>/dev/null; then
  cat <<EOF >> "$SSH_CFG"

# Auto-accept for local libvirt/uvtool VMs
Host 192.168.*
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
  LogLevel ERROR
EOF
fi
chmod 600 "$SSH_CFG"

echo "Make sure to restart the current shell for the groups to be refreshed before creating any vm with uvt-kvm"
