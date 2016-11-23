#!/usr/bin/env bash
TOP_DIR="$(dirname "$(readlink -f "$0")")"

. $TOP_DIR/config.env
. $TOP_DIR/configure.sh

function allinstances {
  docker ps --filter='ancestor=quay.io/fossa/fossa:release' -aq
}

function runninginstances {
  docker ps --filter='ancestor=quay.io/fossa/fossa:release' -q
}

function isrunning {
  [ "$( runninginstances )" ]
}

function init {
  echo "Initializing Fossa";

  # Create directories
  if [ ! -d /var/data/fossa ]; then
    sudo mkdir -p /var/data/fossa
  fi;
  
  # Login to fetch latest docker image
  docker login quay.io

  # Fetch latest image
  docker pull quay.io/fossa/fossa:release

  if [ $(docker images -f "dangling=true" -q) ]; then
    # Remove image entirely
    docker rmi $(docker images -f "dangling=true" -q)
  fi;

  echo "Fossa Initialized"
}

function upgrade {
  echo "Upgrading Fossa";

  # Fetch latest image
  docker pull quay.io/fossa/fossa:release

  if [ $(docker images -f "dangling=true" -q) ]; then
    # Remove image entirely
    docker rmi $(docker images -f "dangling=true" -q)
  fi;

  echo "Fossa Upgraded"
}

function start {
  echo "Starting Fossa"
  NUMBER_OF_AGENTS=${1-4}

  # Migrate database
  docker run --env-file ${TOP_DIR}/config.env -v /var/data/fossa:/fossa/public/data quay.io/fossa/fossa:release npm run migrate

  # run core server
  docker run -d --env-file ${TOP_DIR}/config.env -p 80:80 -p 443:443 -v /var/data/fossa:/fossa/public/data quay.io/fossa/fossa:release npm run start

  # run watchdogs
  docker run -d --env-file ${TOP_DIR}/config.env -v /var/data/fossa:/fossa/public/data quay.io/fossa/fossa:release npm run start:watchdogs:build
  docker run -d --env-file ${TOP_DIR}/config.env -v /var/data/fossa:/fossa/public/data quay.io/fossa/fossa:release npm run start:watchdogs:revision

  current=$( runninginstances )

  # run agents
  while [ ${NUMBER_OF_AGENTS} -gt 0 ]; do
    docker run -d --env-file ${TOP_DIR}/config.env -v /var/data/fossa:/fossa/public/data quay.io/fossa/fossa:release npm run start:agent
    (( NUMBER_OF_AGENTS-- ))
  done;
}

function stop {
  echo "Stopping Fossa"

  current=$( runninginstances )

  # Kill running image
  docker kill $( runninginstances ) 2>&1 > /dev/null
  
  # Remove existing container
  docker rm -f $( allinstances ) 2>&1 > /dev/null
}

case "$1" in
    init)
    if isrunning; then
      echo "Fossa is already running";
      exit 1;
    fi;
    init;
    ;;

    upgrade)
    if isrunning; then
      echo "Fossa is already running";
      exit 1;
    fi;
    upgrade;
    ;;

    start)
    if isrunning; then
      echo "Fossa is already running.";
      exit 1;
    fi;
    start $2;
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

    status)
    if isrunning; then
      echo "Fossa is running"
    else
      echo "Fossa is not running"
    fi;
    ;;

    *)
    echo "Usage: $0 {start|stop|restart|init|upgrade}"
    exit 1
    ;;
esac

exit 0
