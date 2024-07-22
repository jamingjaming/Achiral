#!/bin/bash

# Function to handle errors
handle_error() {
    echo "Error occurred in script at line: $1"
    exit 1
}

# Trap any error and call handle_error
trap 'handle_error $LINENO' ERR

# Function to extract admin token from keystone.conf
get_admin_token() {
    grep "^admin_token" /etc/keystone/keystone.conf | awk -F "= " '{print $2}'
}

# Step 1: Update System and Install Prerequisites
echo "Updating system and installing prerequisites..."
sudo dnf update -y
sudo dnf install -y epel-release
sudo dnf install -y centos-release-openstack-ussuri
sudo dnf upgrade -y
sudo dnf install -y python3-openstackclient mariadb mariadb-server python3-PyMySQL \
    rabbitmq-server memcached libmemcached python3-memcached

# Step 2: Enable and Start Services
echo "Enabling and starting services..."
sudo systemctl enable mariadb.service
sudo systemctl start mariadb.service
sudo systemctl enable rabbitmq-server.service
sudo systemctl start rabbitmq-server.service
sudo systemctl enable memcached.service
sudo systemctl start memcached.service

# Step 3: Configure MariaDB
echo "Configuring MariaDB..."
sudo mysql_secure_installation <<EOF

y
password
password
y
y
y
y
EOF

# Create Keystone database
mysql -u root -ppassword <<EOF
CREATE DATABASE keystone;
GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost' IDENTIFIED BY 'KEYSTONE_DBPASS';
GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' IDENTIFIED BY 'KEYSTONE_DBPASS';
FLUSH PRIVILEGES;
EOF

# Step 4: Install and Configure Keystone
echo "Installing and configuring Keystone..."
sudo dnf install -y openstack-keystone httpd mod_wsgi

# Configure Keystone
sudo cp /etc/keystone/keystone.conf /etc/keystone/keystone.conf.bak
sudo sed -i "s/#admin_token = <None>/admin_token = ADMIN_TOKEN/" /etc/keystone/keystone.conf
sudo sed -i "s/sqlite:\/\/\/\/var\/lib\/keystone\/keystone.db/mysql+pymysql:\/\/keystone:KEYSTONE_DBPASS@controller\/keystone/" /etc/keystone/keystone.conf
sudo keystone-manage db_sync

# Bootstrap Keystone
sudo keystone-manage bootstrap --bootstrap-password ADMIN_PASS \
  --bootstrap-admin-url http://controller:5000/v3/ \
  --bootstrap-internal-url http://controller:5000/v3/ \
  --bootstrap-public-url http://controller:5000/v3/ \
  --bootstrap-region-id RegionOne

# Configure Apache HTTP Server
sudo cp /etc/httpd/conf/httpd.conf /etc/httpd/conf/httpd.conf.bak
echo "ServerName controller" | sudo tee -a /etc/httpd/conf/httpd.conf
sudo ln -s /usr/share/keystone/wsgi-keystone.conf /etc/httpd/conf.d/
sudo systemctl enable httpd.service
sudo systemctl start httpd.service

# Retrieve the admin token
ADMIN_TOKEN=$(get_admin_token)

# Create Keystone service and endpoints
export OS_TOKEN=$ADMIN_TOKEN
export OS_URL=http://controller:5000/v3
export OS_IDENTITY_API_VERSION=3

openstack service create --name keystone --description "OpenStack Identity" identity
openstack endpoint create --region RegionOne identity public http://controller:5000/v3
openstack endpoint create --region RegionOne identity internal http://controller:5000/v3
openstack endpoint create --region RegionOne identity admin http://controller:5000/v3

# Step 5: Install and Configure Glance
echo "Installing and configuring Glance..."
sudo dnf install -y openstack-glance

# Configure Glance
sudo cp /etc/glance/glance-api.conf /etc/glance/glance-api.conf.bak
sudo sed -i "s/sqlite:\/\/\/\/var\/lib\/glance\/glance.sqlite/mysql+pymysql:\/\/glance:GLANCE_DBPASS@controller\/glance/" /etc/glance/glance-api.conf
sudo glance-manage db_sync

# Create Glance service and endpoints
openstack user create --domain default --password GLANCE_PASS glance
openstack role add --project service --user glance admin
openstack service create --name glance --description "OpenStack Image" image
openstack endpoint create --region RegionOne image public http://controller:9292
openstack endpoint create --region RegionOne image internal http://controller:9292
openstack endpoint create --region RegionOne image admin http://controller:9292

# Step 6: Install and Configure Placement
echo "Installing and configuring Placement..."
sudo dnf install -y openstack-placement-api

# Configure Placement
sudo cp /etc/placement/placement.conf /etc/placement/placement.conf.bak
sudo sed -i "s/connection = <None>/connection = mysql+pymysql:\/\/placement:PLACEMENT_DBPASS@controller\/placement/" /etc/placement/placement.conf
sudo placement-manage db sync

# Create Placement service and endpoints
openstack user create --domain default --password PLACEMENT_PASS placement
openstack role add --project service --user placement admin
openstack service create --name placement --description "OpenStack Placement" placement
openstack endpoint create --region RegionOne placement public http://controller:8778
openstack endpoint create --region RegionOne placement internal http://controller:8778
openstack endpoint create --region RegionOne placement admin http://controller:8778

# Step 7: Install and Configure Horizon
echo "Installing and configuring Horizon..."
sudo dnf install -y openstack-dashboard

# Configure Horizon
sudo cp /etc/openstack-dashboard/local_settings /etc/openstack-dashboard/local_settings.bak
sudo sed -i "s/OPENSTACK_HOST = \"127.0.0.1\"/OPENSTACK_HOST = \"controller\"/" /etc/openstack-dashboard/local_settings
sudo systemctl restart httpd.service

# Final Steps: Restart services and verify installation
echo "Restarting services and verifying installation..."
sudo systemctl restart httpd.service
sudo systemctl restart openstack-glance-api.service
sudo systemctl restart openstack-placement-api.service

echo "Installation and configuration of Keystone, Glance, Placement, and Horizon for OpenStack 2023.2 (Bobcat) on Rocky Linux is complete!"
