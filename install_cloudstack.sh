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

# Ensure the script is being run as root
if [ "$EUID" -ne 0 ]; then
    error_exit "This script must be run as root"
fi

# Load MySQL credentials from config file
if [ ! -f ./mysql_config.cnf ]; then
    error_exit "MySQL configuration file (mysql_config.cnf) not found!"
fi

source ./mysql_config.cnf

log "Starting Apache CloudStack Management Server installation on CentOS 7"

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
firewall-cmd --permanent --add-port=8000/tcp || error_exit "Failed to open port 8000" # For agent communication
firewall-cmd --reload || error_exit "Failed to reload firewall rules"

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
mysql -u root -p"$MYSQL_ROOT_PASSWORD" <<EOF || error_exit "Failed to create CloudStack database and user"
CREATE DATABASE cloud;
CREATE USER 'cloud'@'%' IDENTIFIED BY '$MYSQL_PASSWORD';
GRANT ALL PRIVILEGES ON cloud.* TO 'cloud'@'%';
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
/usr/bin/cloudstack-setup-databases cloud:"$MYSQL_PASSWORD"@localhost --deploy-as=root:"$MYSQL_ROOT_PASSWORD" || error_exit "Failed to initialize CloudStack database"

# Configure and start CloudStack management server
log "Configuring and starting CloudStack management server"
/usr/bin/cloudstack-setup-management || error_exit "Failed to configure and start CloudStack management server"

# Enable CloudStack management server to start on boot
log "Enabling CloudStack management server to start on boot"
systemctl enable cloudstack-management || error_exit "Failed to enable CloudStack management server to start on boot"

log "Apache CloudStack Management Server installation completed successfully"
log "You can access the CloudStack UI at http://<your_management_server_ip>:8080/client"
