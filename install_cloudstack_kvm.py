import os
import subprocess
import sys

def run_command(command, ignore_error=False):
    try:
        result = subprocess.run(command, shell=True, text=True, check=True, capture_output=True)
        print(result.stdout)
    except subprocess.CalledProcessError as e:
        print(f"Error running command: {command}\n{e.stderr}", file=sys.stderr)
        if not ignore_error:
            sys.exit(1)

def install_packages():
    commands = [
        "yum install -y epel-release",
        "yum install -y chrony qemu-kvm libvirt",
        "systemctl enable chronyd",
        "systemctl start chronyd",
        "systemctl enable libvirtd",
        "systemctl start libvirtd"
    ]
    for command in commands:
        run_command(command)

def configure_cloudstack_repo():
    repo_content = """
[cloudstack]
name=CloudStack
baseurl=http://download.cloudstack.org/centos/\$releasever/4.19/
enabled=1
gpgcheck=0
"""
    with open("/etc/yum.repos.d/cloudstack.repo", "w") as repo_file:
        repo_file.write(repo_content)
    run_command("yum install -y cloudstack-agent")

def configure_network():
    eth0_config = """
DEVICE=eth0
HWADDR=00:04:xx:xx:xx:xx
ONBOOT=yes
HOTPLUG=no
BOOTPROTO=none
TYPE=Ethernet
BRIDGE=cloudbr0
"""
    cloudbr0_config = """
DEVICE=cloudbr0
TYPE=Bridge
ONBOOT=yes
BOOTPROTO=none
IPV6INIT=no
IPV6_AUTOCONF=no
DELAY=5
IPADDR=192.168.42.11
GATEWAY=192.168.42.1
NETMASK=255.255.255.0
STP=yes
"""
    with open("/etc/sysconfig/network-scripts/ifcfg-eth0", "w") as eth0_file:
        eth0_file.write(eth0_config)
    
    with open("/etc/sysconfig/network-scripts/ifcfg-cloudbr0", "w") as cloudbr0_file:
        cloudbr0_file.write(cloudbr0_config)

    run_command("systemctl restart network")

def configure_firewall():
    firewall_rules = [
        "iptables -I INPUT -p tcp -m tcp --dport 22 -j ACCEPT",
        "iptables -I INPUT -p tcp -m tcp --dport 1798 -j ACCEPT",
        "iptables -I INPUT -p tcp -m tcp --dport 16514 -j ACCEPT",
        "iptables -I INPUT -p tcp -m tcp --dport 5900:6100 -j ACCEPT",
        "iptables -I INPUT -p tcp -m tcp --dport 49152:49216 -j ACCEPT",
        "iptables-save > /etc/sysconfig/iptables"
    ]
    for rule in firewall_rules:
        run_command(rule)
    
    run_command("systemctl stop firewalld", ignore_error=True)
    run_command("systemctl disable firewalld", ignore_error=True)

def disable_selinux():
    run_command("setenforce 0", ignore_error=True)
    with open("/etc/selinux/config", "r") as selinux_file:
        selinux_config = selinux_file.read()
    selinux_config = selinux_config.replace("SELINUX=enforcing", "SELINUX=permissive")
    with open("/etc/selinux/config", "w") as selinux_file:
        selinux_file.write(selinux_config)

def main():
    print("Starting Apache CloudStack KVM host installation on Rocky Linux...")
    install_packages()
    configure_cloudstack_repo()
    configure_network()
    configure_firewall()
    disable_selinux()
    print("Installation completed successfully.")

if __name__ == "__main__":
    main()
