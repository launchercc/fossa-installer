#!/usr/bin/env bash
TOP_DIR=${TOP_DIR-"$(dirname "$(readlink -f "$0")")"}
DOCKER_IMAGE=${DOCKER_IMAGE-"quay.io/fossa/fossa:release"}
DB_DOCKER_IMAGE=${DOCKER_IMAGE-"quay.io/fossa/db:release"}
COCOAPODS_DOCKER_IMAGE=${COCOAPODS_DOCKER_IMAGE-"quay.io/fossa/fossa-cocoapods-api:release"}
PRE_040=${PRE_040-}
PRE_050=${PRE_050-}
DATADIR=${DATADIR-"/var/data/fossa"}
DB_DATADIR=${DATADIR-"/var/data/pg"}

. $TOP_DIR/config.env
. $TOP_DIR/configure.sh

function allinstances {
  docker ps --filter="ancestor=$DOCKER_IMAGE" -aq
  if [ "$cocoapods_api__enabled" = true ]; then
    docker ps --filter="ancestor=$COCOAPODS_DOCKER_IMAGE" -aq
  fi
}

function runninginstances {
  docker ps --filter="ancestor=$DOCKER_IMAGE" -q
  if [ "$cocoapods_api__enabled" = true ]; then
    docker ps --filter="ancestor=$COCOAPODS_DOCKER_IMAGE" -q
  fi
}

function isrunning {
  [ "$( runninginstances )" ]
}

function init {
  echo "Initializing Fossa";

  # Create directories
  if [ ! -d $DATADIR ]; then
    sudo mkdir -p $DATADIR
  fi;
  
  echo "Please provide docker login credentials."
  # Login to fetch latest docker image
  docker login quay.io

  # Fetch latest image
  docker pull $DOCKER_IMAGE

  if [ "$db__builtin" = true ]; then
    # Fetch latest db api image
    docker pull $DB_DOCKER_IMAGE
  fi;

  if [ "$cocoapods_api__enabled" = true ]; then
    # Fetch latest cocoapods api image
    docker pull $COCOAPODS_DOCKER_IMAGE
  fi

  if [ $(docker images -f "dangling=true" -q) ]; then
    # Remove image entirely
    docker rmi $(docker images -f "dangling=true" -q)
  fi;

  echo "Fossa Initialized"
}

function upgrade {
  echo "Upgrading Fossa";

  # Fetch latest image
  docker pull $DOCKER_IMAGE

  if [ "$db__builtin" = true ]; then
    # Fetch latest db api image
    docker pull $DB_DOCKER_IMAGE
  fi;

  if [ "$cocoapods_api__enabled" = true ]; then
    # Fetch latest cocoapods api image
    docker pull $COCOAPODS_DOCKER_IMAGE
  fi;


  if [ $(docker images -f "dangling=true" -q) ]; then
    # Remove image entirely
    docker rmi $(docker images -f "dangling=true" -q)
  fi;

  echo "Fossa Upgraded"
}

function preflight {
  echo "Running preflight checks..."
  echo "================================"
  # run and return stdout or stderr state of this
  docker run --env-file ${TOP_DIR}/config.env -v $DATADIR:/fossa/public/data $DOCKER_IMAGE yarn run preflight --silent
}

function start {
  echo "Starting Fossa"
  NUMBER_OF_AGENTS=${1-4}

  if [ "$SKIP_PREFLIGHT" != true ]; then
    # preflight checks
    if preflight; then
      echo "Preflight checks passed, booting..."
    else
      echo "Preflight checks failed. Fix your configuration or force boot with by setting the SKIP_PREFLIGHT env variable to true."
      exit 1;
    fi
  else
    echo "Skipping preflight checks..."
  fi;

  if [ "$db__builtin" = true ]; then
    # Using builtin db, so lets boot it first...
    echo "Booting built-in FOSSA db..."
    docker run -v $DB_DATADIR:/var/lib/postgresql/data/fossa -p 5432:5432 $DB_DOCKER_IMAGE
  fi;
  

  # Migrate database
  if [[ ${PRE_040} ]]; then
    docker run --env-file ${TOP_DIR}/config.env -v $DATADIR:/fossa/public/data $DOCKER_IMAGE yarn run migrate:pre-0.4.0
  elif [[ ${PRE_050} ]]; then
    docker run --env-file ${TOP_DIR}/config.env -v $DATADIR:/fossa/public/data $DOCKER_IMAGE yarn run migrate:pre-0.5.0
  else
    docker run --env-file ${TOP_DIR}/config.env -v $DATADIR:/fossa/public/data $DOCKER_IMAGE yarn run migrate
  fi;

  if [ "$cocoapods_api__enabled" = true ]; then
    # Migrate Cocoapods API
    docker run --env-file ${TOP_DIR}/config.env -p 9292:9292 -v $DATADIR:/fossa/public/data -v /etc/fossa/.ssh:/root/.ssh $COCOAPODS_DOCKER_IMAGE ruby /app/scripts/cocoapods_setup
    
    # Run Cocoapods API
    docker run -d --env-file ${TOP_DIR}/config.env -p 9292:9292 -v $DATADIR:/fossa/public/data -v /etc/fossa/.ssh:/root/.ssh $COCOAPODS_DOCKER_IMAGE bundle exec puma -C /app/config/production.rb
  fi;

  # run core server
  docker run -d --env-file ${TOP_DIR}/config.env -p 80:80 -p 443:443 -v $DATADIR:/fossa/public/data $DOCKER_IMAGE yarn run start

  # run watchdogs
  docker run -d --env-file ${TOP_DIR}/config.env -v $DATADIR:/fossa/public/data $DOCKER_IMAGE yarn run start:watchdogs:task
  docker run -d --env-file ${TOP_DIR}/config.env -v $DATADIR:/fossa/public/data $DOCKER_IMAGE yarn run start:watchdogs:revision
  docker run -d --env-file ${TOP_DIR}/config.env -v $DATADIR:/fossa/public/data $DOCKER_IMAGE yarn run start:watchdogs:updateHook
  docker run -d --env-file ${TOP_DIR}/config.env -v $DATADIR:/fossa/public/data $DOCKER_IMAGE yarn run start:watchdogs:dependencyLock

  current=$( runninginstances )

  # run agents
  while [ ${NUMBER_OF_AGENTS} -gt 0 ]; do
    docker run -d --env-file ${TOP_DIR}/config.env -v $DATADIR:/fossa/public/data $DOCKER_IMAGE yarn run start:agent
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

    preflight)
    if isrunning; then
      stop;
    fi;
    preflight;
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
