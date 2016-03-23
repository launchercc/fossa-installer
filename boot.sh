#!/usr/bin/env bash
. config.env

TOP_DIR=`dirname $0`

function runninginstances {
  docker ps --filter='ancestor=fossa/fossa' -q
}

function isrunning {
  [ "$( runninginstances )" ]
}

function init {
  if isrunning; then
    echo "Fossa is already running";
    exit 1;
  fi;

  # Create directories
  if [ ! -d /var/data/fossa ]; then
    sudo mkdir -p /var/data/fossa
  fi;

  # Login to fetch latest docker image
  docker login

  # Fetch latest image
  docker pull fossa/fossa:latest

  if [ $(docker images -f "dangling=true" -q) ]; then
    # Remove image entirely
    docker rmi $(docker images -f "dangling=true" -q)
  fi;
}

function start {
  NUMBER_OF_AGENTS=${1-4}

  # run agents
  while [ ${NUMBER_OF_AGENTS} -gt 0 ]; do
    docker run --env-file ${TOP_DIR}/config.env fossa/fossa:latest npm run start:agent > /dev/null &
    (( NUMBER_OF_AGENTS-- ))
  done;

  # run core server
  docker run --env-file ${TOP_DIR}/config.env -p ${app__hostname}:80:80 -p ${app__hostname}:443:443 fossa/fossa:latest npm run start > /dev/null &
}

function stop {
  current=$( runninginstances )

  # Kill running image
  docker kill ${current}
  
  # Remove existing container
  docker rm -f ${current}
}

case "$1" in
    init)
    if isrunning; then
      echo "Fossa is already running";
      exit 1;
    fi;
    init;
    ;;

    start)
    if isrunning; then
      echo "Fossa is already running.";
      exit 1;
    fi;
    start;
    ;;

    stop)
    if ! isrunning; then
      echo "Fossa is not running";
      exit 1;
    fi;
    stop;
    ;;

    restart)
    if isrunning; then
      stop;
    fi;
    start;
    ;;

    *)
    echo "Usage: $0 {start|stop|restart|init}"
    exit 1
    ;;
esac

exit 0
