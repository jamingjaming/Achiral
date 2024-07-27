#!/bin/bash

# Function to handle errors
handle_error() {
    echo "Error occurred in script at line: $1" | tee -a openstack_install.log
    exit 1
}

# Trap any error and call handle_error
trap 'handle_error $LINENO' ERR

# Function to extract admin token from keystone.conf
get_admin_token() {
    grep "^admin_token" /etc/keystone/keystone.conf | awk -F "= " '{print $2}'
}

# Log function to capture output
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a openstack_install.log
}

# Step 1: Add OpenStack Ussuri repository and update system
log "Adding OpenStack repository and updating system..."
sudo dnf install -y epel-release | tee -a openstack_install.log
sudo dnf install -y https://repos.fedorapeople.org/repos/openstack/openstack-ussuri/rdo-release-ussuri-1.el8.noarch.rpm | tee -a openstack_install.log
sudo dnf update -y | tee -a openstack_install.log

# Step 2: Install Prerequisites
log "Installing prerequisites..."
sudo dnf install -y centos-release-openstack-ussuri | tee -a openstack_install.log
sudo dnf upgrade -y | tee -a openstack_install.log
sudo dnf install -y python3-openstackclient mariadb mariadb-server python3-PyMySQL \
    rabbitmq-server memcached libmemcached python3-memcached | tee -a openstack_install.log

# Step 3: Enable and Start Services
log "Enabling and starting services..."
sudo systemctl enable mariadb.service | tee -a openstack_install.log
sudo systemctl start mariadb.service | tee -a openstack_install.log
sudo systemctl enable rabbitmq-server.service | tee -a openstack_install.log
sudo systemctl start rabbitmq-server.service | tee -a openstack_install.log
sudo systemctl enable memcached.service | tee -a openstack_install.log
sudo systemctl start memcached.service | tee -a openstack_install.log

# Step 4: Configure MariaDB
log "Configuring MariaDB..."
sudo mysql_secure_installation <<EOF | tee -a openstack_install.log
y
password
password
y
y
y
y
EOF

# Create Keystone database
log "Creating Keystone database..."
mysql -u root -ppassword <<EOF | tee -a openstack_install.log
CREATE DATABASE keystone;
GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost' IDENTIFIED BY 'KEYSTONE_DBPASS';
GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' IDENTIFIED BY 'KEYSTONE_DBPASS';
FLUSH PRIVILEGES;
EOF

# Step 5: Install and Configure Keystone
log "Installing and configuring Keystone..."
sudo dnf install -y openstack-keystone httpd mod_wsgi | tee -a openstack_install.log

# Configure Keystone
sudo cp /etc/keystone/keystone.conf /etc/keystone/keystone.conf.bak | tee -a openstack_install.log
sudo sed -i "s/#admin_token = <None>/admin_token = ADMIN_TOKEN/" /etc/keystone/keystone.conf | tee -a openstack_install.log
sudo sed -i "s/sqlite:\/\/\/\/var\/lib\/keystone\/keystone.db/mysql+pymysql:\/\/keystone:KEYSTONE_DBPASS@controller\/keystone/" /etc/keystone/keystone.conf | tee -a openstack_install.log
sudo keystone-manage db_sync | tee -a openstack_install.log

# Bootstrap Keystone
log "Bootstrapping Keystone..."
sudo keystone-manage bootstrap --bootstrap-password ADMIN_PASS \
  --bootstrap-admin-url http://controller:5000/v3/ \
  --bootstrap-internal-url http://controller:5000/v3/ \
  --bootstrap-public-url http://controller:5000/v3/ \
  --bootstrap-region-id RegionOne | tee -a openstack_install.log

# Configure Apache HTTP Server
log "Configuring Apache HTTP Server..."
sudo cp /etc/httpd/conf/httpd.conf /etc/httpd/conf/httpd.conf.bak | tee -a openstack_install.log
echo "ServerName controller" | sudo tee -a /etc/httpd/conf/httpd.conf | tee -a openstack_install.log
sudo ln -s /usr/share/keystone/wsgi-keystone.conf /etc/httpd/conf.d/ | tee -a openstack_install.log
sudo systemctl enable httpd.service | tee -a openstack_install.log
sudo systemctl start httpd.service | tee -a openstack_install.log

# Retrieve the admin token
ADMIN_TOKEN=$(get_admin_token)

# Create Keystone service and endpoints
log "Creating Keystone service and endpoints..."
export OS_TOKEN=$ADMIN_TOKEN
export OS_URL=http://controller:5000/v3
export OS_IDENTITY_API_VERSION=3

openstack service create --name keystone --description "OpenStack Identity" identity | tee -a openstack_install.log
openstack endpoint create --region RegionOne identity public http://controller:5000/v3 | tee -a openstack_install.log
openstack endpoint create --region RegionOne identity internal http://controller:5000/v3 | tee -a openstack_install.log
openstack endpoint create --region RegionOne identity admin http://controller:5000/v3 | tee -a openstack_install.log

# Step 6: Install and Configure Glance
log "Installing and configuring Glance..."
sudo dnf install -y openstack-glance | tee -a openstack_install.log

# Configure Glance
sudo cp /etc/glance/glance-api.conf /etc/glance/glance-api.conf.bak | tee -a openstack_install.log
sudo sed -i "s/sqlite:\/\/\/\/var\/lib\/glance\/glance.sqlite/mysql+pymysql:\/\/glance:GLANCE_DBPASS@controller\/glance/" /etc/glance/glance-api.conf | tee -a openstack_install.log
sudo glance-manage db_sync | tee -a openstack_install.log

# Create Glance service and endpoints
log "Creating Glance service and endpoints..."
openstack user create --domain default --password GLANCE_PASS glance | tee -a openstack_install.log
openstack role add --project service --user glance admin | tee -a openstack_install.log
openstack service create --name glance --description "OpenStack Image" image | tee -a openstack_install.log
openstack endpoint create --region RegionOne image public http://controller:9292 | tee -a openstack_install.log
openstack endpoint create --region RegionOne image internal http://controller:9292 | tee -a openstack_install.log
openstack endpoint create --region RegionOne image admin http://controller:9292 | tee -a openstack_install.log

# Step 7: Install and Configure Placement
log "Installing and configuring Placement..."
sudo dnf install -y openstack-placement-api | tee -a openstack_install.log

# Configure Placement
sudo cp /etc/placement/placement.conf /etc/placement/placement.conf.bak | tee -a openstack_install.log
sudo sed -i "s/connection = <None>/connection = mysql+pymysql:\/\/placement:PLACEMENT_DBPASS@controller\/placement/" /etc/placement/placement.conf | tee -a openstack_install.log
sudo placement-manage db sync | tee -a openstack_install.log

# Create Placement service and endpoints
log "Creating Placement service and endpoints..."
openstack user create --domain default --password PLACEMENT_PASS placement | tee -a openstack_install.log
openstack role add --project service --user placement admin | tee -a openstack_install.log
openstack service create --name placement --description "OpenStack Placement" placement | tee -a openstack_install.log
openstack endpoint create --region RegionOne placement public http://controller:8778 | tee -a openstack_install.log
openstack endpoint create --region RegionOne placement internal http://controller:8778 | tee -a openstack_install.log
openstack endpoint create --region RegionOne placement admin http://controller:8778 | tee -a openstack_install.log

# Step 8: Install and Configure Horizon
log "Installing and configuring Horizon..."
sudo dnf install -y openstack-dashboard | tee -a openstack_install.log

# Configure Horizon
sudo cp /etc/openstack-dashboard/local_settings /etc/openstack-dashboard/local_settings.bak | tee -a openstack_install.log
sudo sed -i "s/OPENSTACK_HOST = \"127.0.0.1\"/OPENSTACK_HOST = \"controller\"/" /etc/openstack-dashboard/local_settings | tee -a openstack_install.log
sudo systemctl restart httpd.service | tee -a openstack_install.log

# Final Steps: Restart services and verify installation
log "Restarting services and verifying installation..."
sudo systemctl restart httpd.service | tee -a openstack_install.log
sudo systemctl restart openstack-glance-api.service | tee -a openstack_install.log
sudo systemctl restart openstack-placement-api.service | tee -a openstack_install.log

log "Installation and configuration of Keystone, Glance, Placement, and Horizon for OpenStack 2023.2 (Bobcat) on Rocky Linux is complete!"
