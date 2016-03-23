#!/usr/bin/env bash
. config.env

trap "kill -- -$BASHPID" EXIT

TOP_DIR=`dirname $0`

SPINNER_PID=0
function startspinner {
  if [ $SPINNER_PID -eq 0 ]; then
    SPINNER_CMD=$( cat <<SPINNER
CHARS=('-' '/' '|' '\\');
i=0;
while [ 1 ]; do
  printf \${CHARS[\${i}]};
  printf " "
  sleep 0.1;
  printf "\r\r";
  (( i++ ));
  (( i%=4 ));
done;
SPINNER
)
    bash -c "$SPINNER_CMD" &
    SPINNER_PID=$!
  fi;
}

function stopspinner {
  kill $SPINNER_PID
  SPINNER_PID=0
}

function runninginstances {
  docker ps --filter='ancestor=fossa/fossa' -q
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
  docker login

  startspinner

  # Fetch latest image
  docker pull fossa/fossa:latest > /dev/null

  if [ $(docker images -f "dangling=true" -q) ]; then
    # Remove image entirely
    docker rmi $(docker images -f "dangling=true" -q)
  fi;

  stopspinner

  echo "Fossa Initialized"
}

function upgrade {
  echo "Upgrading Fossa";

  startspinner

  # Fetch latest image
  docker pull fossa/fossa:latest > /dev/null

  if [ $(docker images -f "dangling=true" -q) ]; then
    # Remove image entirely
    docker rmi $(docker images -f "dangling=true" -q)
  fi;

  stopspinner

  echo "Fossa Upgraded"
}

function start {
  echo "Starting Fossa!"
  NUMBER_OF_AGENTS=${1-4}

  # run agents
  while [ ${NUMBER_OF_AGENTS} -gt 0 ]; do
    docker run --env-file ${TOP_DIR}/config.env fossa/fossa:latest npm run start:agent 2>&1 > /dev/null &
    (( NUMBER_OF_AGENTS-- ))
  done;

  # run core server
  docker run --env-file ${TOP_DIR}/config.env -p 80:80 -p 443:443 fossa/fossa:latest npm run start 2>&1 > /dev/null &
}

function stop {
  echo "Stopping Fossa!"

  current=$( runninginstances )

  # Kill running image
  docker kill ${current} > /dev/null
  
  # Remove existing container
  docker rm -f ${current} > /dev/null
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
    init;
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

    *)
    echo "Usage: $0 {start|stop|restart|init}"
    exit 1
    ;;
esac

exit 0
