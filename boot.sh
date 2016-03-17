#!/usr/bin/env bash
source ./config.sh

docker pull fossa/fossa:latest
docker kill $(docker ps -aq)
docker rm $(docker ps -aq)
docker rmi $(docker images -f "dangling=true" -q)

# run agents
docker run

# run core server & tail
docker run