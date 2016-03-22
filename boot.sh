#!/usr/bin/env bash
source ./config.sh

# Fetch latest image
docker pull fossa/fossa:latest

if [ $( docker ps -aq ) ]; then
  # Kill running image
  docker kill $(docker ps -aq);
  
  # Remove existing container
  docker rm $(docker ps -aq)
fi;

if [ $(docker images -f "dangling=true" -q) ]; then
  # Remove image entirely
  docker rmi $(docker images -f "dangling=true" -q)
fi;

# run agents
docker run

# run core server & tail
docker run
