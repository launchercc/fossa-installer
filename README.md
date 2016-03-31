# Welcome to the FOSSA Installer

## Prerequisites

View `PREINSTALL.md` on a full guide on how to set up the box.

- Linux Box with:
    - Ubuntu 14.04 LTS
    - Static IP address (accessible to users in your organization)
    - >16 GB RAM
    - >30 GB HDD
    - Docker 1.3+ (config'd to use `devicemapper` over AUFS), Bash 3.2+, curl & tar 
    - Port 80 (or whatever configured) exposed in firewall

- SMTP server 

- Postgres 9.3+ on a machine with >16 GB RAM, >30 GB HDD


**Prepare the following:**

- External IP (accessible to your users) of the box running FOSSA
- SMTP server host/port
- Postgres host, port, username & password
- Database in Postgres named "fossa", accessible to the user

Make sure all of these endpoints are accessible from the machine running FOSSA.

## Installing FOSSA

As part of the installer, you will be prompted for a `username, password and email`.  Contact `support@fossa.io` if you haven't already been given those credentials.

```bash
# Download and run the installer
mkdir -p ~/fossa && curl -L https://github.com/fossas/fossa-installer/archive/v0.0.4.tar.gz | tar -zxv -C ~/fossa --strip-components=1 && chmod a+x ~/fossa/boot.sh && ln -sf ~/fossa/boot.sh /usr/local/bin/fossa && fossa init

# Configure FOSSA first-time
vi ~/fossa/config.env

# Run FOSSA 
fossa start 4

# Note: '4' refers to the number of analysis agents to launch with FOSSA.  
# The more agents you run, the faster & greater your analysis load.
# Reccomended max agents = GB Avail. Mem/2, rounded down (i.e. 32GB RAM/2 = 16 agents)
```

## Updating FOSSA

Updating is as simple as running:

```bash
sudo fossa upgrade
```