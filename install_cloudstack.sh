#!/bin/bash

set -e

# Function to print a message with a timestamp
function log() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') - $1"
}

# Function to handle errors
function error_exit() {
    log "ERROR: $1"
    exit 1
}

# Load MySQL credentials from config file
if [ ! -f ./mysql_config.cnf ]; then
    error_exit "MySQL configuration file (mysql_config.cnf) not found!"
fi

source ./mysql_config.cnf

log "Starting Apache CloudStack installation on CentOS 7"

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

# Disable firewalld
log "Disabling firewalld"
systemctl stop firewalld || error_exit "Failed to stop firewalld"
systemctl disable firewalld || error_exit "Failed to disable firewalld"

# Install MySQL server
log "Installing MySQL server"
yum install -y mysql-server || error_exit "Failed to install MySQL server"

# Start MySQL service and enable it to start on boot
log "Starting and enabling MySQL service"
systemctl start mysqld || error_exit "Failed to start MySQL service"
systemctl enable mysqld || error_exit "Failed to enable MySQL service"

# Secure MySQL installation
log "Securing MySQL installation"
mysql_secure_installation || error_exit "Failed to secure MySQL installation"

# Create CloudStack database and user
log "Creating CloudStack database and user"
mysql -u root -p <<EOF || error_exit "Failed to create CloudStack database and user"
CREATE DATABASE cloud;
CREATE USER 'cloud'@'localhost' IDENTIFIED BY '$MYSQL_PASSWORD';
GRANT ALL PRIVILEGES ON cloud.* TO 'cloud'@'localhost';
FLUSH PRIVILEGES;
EOF

# Add CloudStack repository
log "Adding CloudStack repository"
cat <<EOF > /etc/yum.repos.d/cloudstack.repo
[cloudstack]
name=cloudstack
baseurl=http://download.cloudstack.org/centos/\$releasever/4.19/
enabled=1
gpgcheck=0
EOF

# Install CloudStack management server
log "Installing CloudStack management server"
yum install -y cloudstack-management || error_exit "Failed to install CloudStack management server"

# Initialize the database
log "Initializing CloudStack database"
/usr/bin/cloudstack-setup-databases cloud:$MYSQL_PASSWORD@localhost --deploy-as=root || error_exit "Failed to initialize CloudStack database"

# Configure and start CloudStack management server
log "Configuring and starting CloudStack management server"
/usr/bin/cloudstack-setup-management || error_exit "Failed to configure and start CloudStack management server"

# Create cloud bridge network
log "Creating cloud bridge network"
nmcli connection add type bridge autoconnect yes con-name cloudbr0 ifname cloudbr0 || error_exit "Failed to create cloud bridge network"
nmcli connection modify cloudbr0 bridge.stp no || error_exit "Failed to modify cloud bridge network"

# Restart network services
log "Restarting network services"
systemctl restart network || error_exit "Failed to restart network services"

# Enable CloudStack management server to start on boot
log "Enabling CloudStack management server to start on boot"
systemctl enable cloudstack-management || error_exit "Failed to enable CloudStack management server to start on boot"

log "Apache CloudStack installation completed successfully"
log "You can access the CloudStack UI at http://<your_server_ip>:8080/client"
