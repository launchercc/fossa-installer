#!/usr/bin/env bash
source ./config.sh

# Fetch latest image
docker pull fossa/fossa:latest

# Kill running image
if [ $( docker ps -aq ) ]; then
	docker kill $(docker ps -aq);
fi;

# Remove existing container
docker rm $(docker ps -aq)

# Remove image entirely
docker rmi $(docker images -f "dangling=true" -q)

# run agents
docker run

# run core server & tail
docker run
