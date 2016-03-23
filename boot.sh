#!/usr/bin/env bash
source ./fossa_env.sh

function runninginstances {
  docker ps --filter='ancestor=fossa/fossa' -q
}

function isrunning {
  [ $( runninginstances; ) ];
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

function createdb {
  if [ ! -d /var/data/fossa/db ]; then
    sudo mkdir -p /var/data/fossa/db
    sudo chown postgres /var/data/fossa/db
  fi;

  sudo -u postgres -H $PG_CTL_BIN -D /var/data/fossa/db initdb
}

function start {
  # run agents
  docker run fossa/fossa:latest npm start:agent

  # run core server
  docker run fossa/fossa:latest npm start
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

    createdb)
    if isrunning; then
      echo "Fossa is already running";
      exit 1;
    fi;
    createdb;
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
    echo "Usage: $0 {start|stop|restart|init|createdb}"
    exit 1
    ;;
esac

exit 0

