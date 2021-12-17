# router_config
This script helps configure DDW router.

## Usage
### Configuration file
Create a configuration file like the following
```
#!/bin/sh

NAME=routername
DOMAINNAME=domainname
TIMEZONE=America/New_York

WAN="dhcp"

# define subnets by names Main/Guest/IoT
SUBNETS="
Main    192.168.1   br0
Guest   192.168.2   wl1.1
IoT     192.168.3   wl0.1
"

# define blocks for IPs by name
SUBNET_DISTRIBUTION="
Static      00  50
Dynamic     51  150
Blocked     151 200
AllowedIoT  201 250
"

DHCP_LEASE=1440 # minutes
DNS_SERVER= # define local DNS server, if any
DMZ_SERVER= # define local DMZ server, if any
WORKSTATIONS= # define any workstations that should have access to Guest and IoT subnets

# static leases in format - MachineName   MacAddress  Subnet/Auto   IPAddress
STATIC_LEASES="
MachineName     00:11:22:33:44:55   Auto    10
"

# port forwarding in format - Name  SrcPort  MachineName(fromStaticLeases)  DestPort
PORT_FORWARDS="
Forward20   20  MachineName     20
"

# additional custom firewall rules - format - SubnetName    from/to     MachineName(fromStaticLeases)   IPBlockName/All     Ports
# ports can be 0 for all, or comma separated port numbers or port range (start:end)
FIREWALL_RULES="
IoT     from    MachineName AllowedIoT  0
"

SSH_PORT=22
SSH_KEY= # ssh key to add to authorized keys
```
### Run
* Take a backup of your settings by running `sh /path/to/router_config.sh -cf /path/to/configuration_file -b`. It will save /tmp/nvram_backup.tar.gz.
* Test configuring basic settings by running `sh /path/to/router_config.sh -cf /path/to/configuration_file -sb`. This will print nvram variables that script would set.
* If everything looks good in previous step, actually configure basic settings by running `sh /path/to/router_config.sh -cf /path/to/configuration_file -sb -y`. This will make necessary nvram changes but not auto commit. Run `nvram commit` to commit changes.
* The script does not yet configure Wireless Settings, instead it prints messages asking the user to configure those manually using the UI.
* Test configuring networking settings by running `sh /path/to/router_config.sh -cf /path/to/configuration_file -sn`. This will print nvram variables that script would set.
* If everything looks good in previous step, actually configure networking settings by running `sh /path/to/router_config.sh -cf /path/to/configuration_file -sn -y`. This will make necessary nvram changes but not auto commit. Run `nvram commit` to commot changes.
