#!/bin/bash

set -e

# Function to print a message with a timestamp
log() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') - $1"
}

# Function to handle errors
error_exit() {
    log "ERROR: $1"
    exit 1
}

# Ensure the script is being run as root
if [ "$EUID" -ne 0 ]; then
    error_exit "This script must be run as root"
fi

log "Starting Apache CloudStack Agent and Apache installation on CentOS 7"

# Get user inputs
read -p "Enter agent zone: " agent_zone
read -p "Enter agent pod: " agent_pod
read -p "Enter agent cluster: " agent_cluster
read -p "Enter agent host IP: " agent_host_ip
read -p "Enter agent private IP: " agent_private_ip
read -p "Enter agent public interface: " agent_public_interface
read -p "Enter agent public IP: " agent_public_ip
read -p "Enter management server IP: " management_server_ip

# Update the system
log "Updating system packages"
yum update -y || error_exit "Failed to update system packages"

# Install EPEL repository
log "Installing EPEL repository"
yum install -y epel-release || error_exit "Failed to install EPEL repository"

# Install necessary packages
log "Installing necessary packages"
yum install -y wget net-tools chrony || error_exit "Failed to install necessary packages"

# Set SELinux to permissive mode
log "Setting SELinux to permissive mode"
setenforce 0 || error_exit "Failed to set SELinux to permissive mode"
sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config || error_exit "Failed to update SELinux configuration"

# Configure firewall
log "Configuring firewall"
systemctl start firewalld || error_exit "Failed to start firewalld"
systemctl enable firewalld || error_exit "Failed to enable firewalld"
firewall-cmd --permanent --add-port=3306/tcp || error_exit "Failed to open port 3306"
firewall-cmd --permanent --add-port=8080/tcp || error_exit "Failed to open port 8080"
firewall-cmd --permanent --add-port=8250/tcp || error_exit "Failed to open port 8250"
firewall-cmd --permanent --add-port=9090/tcp || error_exit "Failed to open port 9090"
firewall-cmd --permanent --add-port=8000/tcp || error_exit "Failed to open port 8000"
firewall-cmd --reload || error_exit "Failed to reload firewall rules"

# Install Apache Agent
log "Installing Apache Agent"
yum install -y httpd || error_exit "Failed to install Apache Agent"
systemctl start httpd || error_exit "Failed to start Apache Agent"
systemctl enable httpd || error_exit "Failed to enable Apache Agent to start on boot"

# Add CloudStack repository
cat <<EOF > /etc/yum.repos.d/cloudstack.repo
[cloudstack]
name=cloudstack
baseurl=http://download.cloudstack.org/centos/\$releasever/4.19/
enabled=1
gpgcheck=0
EOF

# Install CloudStack agent
log "Installing CloudStack agent"
yum install -y cloudstack-agent || error_exit "Failed to install CloudStack agent"

# Configure CloudStack agent
log "Configuring CloudStack agent"
cat <<EOF > /etc/cloudstack/agent/agent.properties
agent.libvirt.host=localhost
agent.libvirt.type=kvm
agent.libvirt.port=16509
agent.libvirt.conn.protocol=qemu+tcp
agent.libvirt.conn.uri=qemu+tcp://localhost/system
agent.direct.host=true
agent.zone=$agent_zone
agent.pod=$agent_pod
agent.cluster=$agent_cluster
agent.host.ip=$agent_host_ip
agent.private.interface=cloudbr0
agent.private.ip=$agent_private_ip
agent.public.interface=$agent_public_interface
agent.public.ip=$agent_public_ip
management.server.ip=$management_server_ip
EOF

# Restart CloudStack agent
log "Restarting CloudStack agent"
systemctl restart cloudstack-agent || error_exit "Failed to restart CloudStack agent"

# Enable CloudStack agent to start on boot
log "Enabling CloudStack agent to start on boot"
systemctl enable cloudstack-agent || error_exit "Failed to enable CloudStack agent to start on boot"

# Create cloud bridge network
log "Creating cloud bridge network"
nmcli connection add type bridge autoconnect yes con-name cloudbr0 ifname cloudbr0 || error_exit "Failed to create cloud bridge network"
nmcli connection modify cloudbr0 bridge.stp no || error_exit "Failed to modify cloud bridge network"

# Restart network services
log "Restarting network services"
systemctl restart network || error_exit "Failed to restart network services"

log "Apache CloudStack Agent and Apache installation completed successfully"
log "Agent server should now communicate with the management server at $management_server_ip"
