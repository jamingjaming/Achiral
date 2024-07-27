

#!/bin/bash
###############this script is for deployment on centos based distros, and sets the controller as the primary storage node.
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

log "Updating the system"
yum update -y || error_exit "Failed to update system packages"
log "System update completed"

log "Installing EPEL repository"
yum install -y epel-release || error_exit "Failed to install EPEL repository"
log "EPEL repository installation completed"

log "Installing necessary packages"
yum install -y wget net-tools chrony nfs-utils || error_exit "Failed to install necessary packages"
log "Necessary packages installation completed"

log "Setting SELinux to permissive mode"
setenforce 0 || error_exit "Failed to set SELinux to permissive mode"
sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config || error_exit "Failed to update SELinux configuration"
log "SELinux set to permissive mode"

log "Configuring NFSv4 domain setting"
sed -i 's/^#Domain =.*/Domain = storage.dedi.cloud/' /etc/idmapd.conf || error_exit "Failed to set NFSv4 domain in /etc/idmapd.conf"
log "NFSv4 domain setting configured"

log "Configuring NFS shares"
cat <<EOF > /etc/exports
/export/secondary *(rw,async,no_root_squash,no_subtree_check)
/export/primary *(rw,async,no_root_squash,no_subtree_check)
EOF

mkdir -p /export/primary
mkdir /export/secondary
systemctl enable rpcbind || error_exit "Failed to enable RPC"
systemctl enable nfs-server || error_exit "Failed to enable NFS"
systemctl start rpcbind || error_exit "Failed to start RPC"
systemctl start nfs-server || error_exit "Failed to start NFS"

# Ensure NFS shares are accessible and mountable
log "Testing NFS shares"
showmount -e localhost || error_exit "Failed to show NFS shares"
mount -t nfs localhost:/export/primary /mnt || error_exit "Failed to mount NFS share"
umount /mnt
log "NFS shares are accessible and mountable"

log "NFS shares configured"

log "Configuring firewall"
systemctl start firewalld || error_exit "Failed to start firewalld"
systemctl enable firewalld || error_exit "Failed to enable firewalld"
firewall-cmd --permanent --add-service=nfs || error_exit "Failed to allow NFS service"
firewall-cmd --permanent --add-service=rpc-bind || error_exit "Failed to allow RPC-bind service"
firewall-cmd --permanent --add-port=3306/tcp || error_exit "Failed to open port 3306"
firewall-cmd --permanent --add-port=8080/tcp || error_exit "Failed to open port 8080"
firewall-cmd --permanent --add-port=8250/tcp || error_exit "Failed to open port 8250"
firewall-cmd --permanent --add-port=9090/tcp || error_exit "Failed to open port 9090"
firewall-cmd --permanent --add-port=8000/tcp || error_exit "Failed to open port 8000" # For agent communication
firewall-cmd --reload || error_exit "Failed to reload firewall rules"
log "Firewall configured"

log "Installing MySQL server"
yum install -y mysql-server || error_exit "Failed to install MySQL server"
log "MySQL server installation completed"

log "Starting MySQL service and enabling it to start on boot"
systemctl start mysqld || error_exit "Failed to start MySQL service"
systemctl enable mysqld || error_exit "Failed to enable MySQL service"
log "MySQL service started and enabled"

log "Securing MySQL installation"
mysql_secure_installation || error_exit "Failed to secure MySQL installation"
log "MySQL installation secured"

log "Adding CloudStack repository"
cat <<EOF > /etc/yum.repos.d/cloudstack.repo
[cloudstack]
name=cloudstack
baseurl=http://download.cloudstack.org/centos/\$releasever/4.19/
enabled=1
gpgcheck=0
EOF
log "CloudStack repository added"

log "Installing CloudStack management server"
yum install -y cloudstack-management || error_exit "Failed to install CloudStack management server"
log "CloudStack management server installation completed"

log "Initializing the CloudStack database"
usr/bin/cloudstack-setup-databases cloud:"$MYSQL_PASSWORD"@localhost --deploy-as=root:"CHANGE_ME_TO_ROOT_SQL" || error_exit "Failed to initialize CloudStack database"
log "CloudStack database initialized"

log "Configuring and starting CloudStack management server"
usr/bin/cloudstack-setup-management || error_exit "Failed to configure and start CloudStack management server"
log "CloudStack management server configured and started"

log "Enabling CloudStack management server to start on boot"
systemctl enable cloudstack-management || error_exit "Failed to enable CloudStack management server to start on boot"
log "CloudStack management server enabled to start on boot"

log "Apache CloudStack Management Server installation completed successfully"
log "You can access the CloudStack UI at http://<your_management_server_ip>:8080/client"


