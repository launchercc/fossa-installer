# FOSSA Pre-Install Instructions

This guide will help you set up your machine's environment to install FOSSA on `Ubuntu 14.04 LTS`.  

Make sure you run this guide as a superuser via `sudo -s`.

## 1. Set up the environment

```bash
# Update the registry
apt-get update
apt-get -y install apt-transport-https ca-certificates
apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys 58118E89F3A912897C070ADBF76221572C52609D

# Download and install docker, postgres
# NOTE: Do not use Docker 1.9.1 because of: https://github.com/docker/docker/issues/18180
echo deb https://apt.dockerproject.org/repo ubuntu-trusty main >> /etc/apt/sources.list.d/docker.list
apt-get update
apt-get purge lxc-docker
apt-get install -y docker-engine postgresql-9.3 curl tar

# Replace "ubuntu" with your username, if it's different
usermod -aG docker ubuntu

# Edit docker config to use "devicemapper" over "aufs" due to issues with aufs on Ubuntu
echo "DOCKER_OPTS=\"--storage-driver=devicemapper\"" >> /etc/default/docker

service docker restart
```
​
## 2. Set up the Postgres database

In the machine that's running postgres (could be the same), run the following:

```bash
sudo -u postgres psql -c "CREATE DATABASE fossa"

# replace the default '' password with what you have in config.env
sudo -u postgres psql -c "CREATE USER fossa WITH PASSWORD '';"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE fossa TO fossa;"

sudo service postgresql restart
```

If you have a separate postgres instance, make sure you add those connection details to `config.env`.

## 3. (Optional) Prepare Integrations

#### Bitbucket/Stash:

If you'd like FOSSA to integrate with Bitbucket Server/Stash, make sure you prepare the following:

1. Location of Bitbucket Server on your network
2. A bitbucket login for FOSSA (default username/password `fossabot`/`fossa123`) with...
  - **Global read access** (i.e. to clone repos behind your firewall) 
  - **Ability to create application links** via `Admin > Application Links` 

Once FOSSA is running, `{FOSSA_HOST}/docs/integrations/bitbucket-server-(stash)` will have futher instructions on setup.

#### Github: 

TBA

## 4. Run the FOSSA installer

As part of the installer, you will be prompted for a `username, password and email`.  Contact `support@fossa.io` if you haven't already been given those credentials.

```bash
# Download and run the installer
mkdir -p ~/fossa && curl -L https://github.com/fossas/fossa-installer/archive/v0.0.3.tar.gz | tar -zxv -C ~/fossa --strip-components=1 && chmod a+x ~/fossa/boot.sh && ln -sf ~/fossa/boot.sh /usr/local/bin/fossa && fossa init

# Configure FOSSA first-time
vi ~/fossa/config.env

# Run FOSSA 
fossa start 4

# Note: '4' refers to the number of analysis agents to launch with FOSSA.  
# The more agents you run, the faster & greater your analysis load.
# Reccomended max agents = GB Avail. Mem/2, rounded down (i.e. 32GB RAM/2 = 16 agents)
```


## Troubleshooting

If you are having trouble connecting to postgres, try this:

```bash
sudo ufw disable

sudo sysctl -p /etc/sysctl.conf

# In the file below, find the IPv4 host configuration and make sure it looks like this:
# host    all             all             0.0.0.0/0            md5
sudo -u postgres vi /etc/postgresql/9.3/main/pg_hba.conf

# In this file, find listen_addresses and set it to '0.0.0.0'
sudo -u postgres vi /etc/postgresql/9.3/main/postgresql.conf
```

If you're having trouble connecting to Fossa, try this:

```bash
# Find the line net.ipv6.conf.default.forwarding=1 and uncomment it in the file underneath:
vi /etc/sysctl.conf
```