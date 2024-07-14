Usage

    Clone this repository or download the script.

    Make the script executable:

    bash

chmod +x install_cloudstack.sh

Run the script:

bash

    ./install_cloudstack.sh

Script Breakdown

The script performs the following steps:

    System Update: Updates the system packages.
    EPEL Repository Installation: Installs the EPEL repository.
    Necessary Packages Installation: Installs wget, net-tools, and chrony.
    SELinux Configuration: Sets SELinux to permissive mode.
    Firewall Configuration: Configures firewalld to allow necessary ports for CloudStack.
    MySQL Installation: Installs MySQL server, starts the service, and enables it to start on boot.
    MySQL Secure Installation: Secures the MySQL installation.
    CloudStack Database and User Creation: Creates the cloud database and user.
    CloudStack Repository Addition: Adds the CloudStack repository.
    CloudStack Management Server Installation: Installs the CloudStack management server.
    Database Initialization: Initializes the CloudStack database.
    CloudStack Management Server Configuration: Configures and starts the CloudStack management server.
    Network Configuration: Creates a cloud bridge network and restarts network services.
    Service Enablement: Enables the CloudStack management server to start on boot.
