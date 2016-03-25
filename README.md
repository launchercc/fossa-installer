# Welcome to the FOSSA Installer

## Prerequisites

- Linux Box with:
    - Ubuntu 14.04
    - Static IP address (accessible to users in your organization)
    - >16 GB RAM
    - >30 GB HDD
    - Docker 1.3+
    - Bash 3.2+

- SMTP server 

- Postgres 9.5+ on a machine with >16 GB RAM, >30 GB HDD


**Prepare the following:**

- External IP (accessible to your users) of the box running FOSSA
- SMTP server host/port
- Postgres host, port, username & password
- Database in Postgres named "fossa", accessible to the user

Make sure all of these endpoints are accessible from the machine running FOSSA.

