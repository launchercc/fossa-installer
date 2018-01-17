#!/usr/bin/env bash
TOP_DIR=${TOP_DIR-"$(dirname "$(readlink -f "$0")")"}
DOCKER_IMAGE=${DOCKER_IMAGE-"quay.io/fossa/fossa:release"}
COCOAPODS_DOCKER_IMAGE=${COCOAPODS_DOCKER_IMAGE-"quay.io/fossa/fossa-cocoapods-api:release"}
PRE_040=${PRE_040-}
PRE_050=${PRE_050-}
DATADIR=${DATADIR-"/var/data/fossa"}

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

function appendHeaderToSupportBundle {
  echo "--------------------------------------------------------------" >> $SUPPORT_BUNDLE
  echo "$1" >> $SUPPORT_BUNDLE
  echo "--------------------------------------------------------------" >> $SUPPORT_BUNDLE
}

function supportbundle {
  local SUPPORT_BUNDLE="$DATADIR/$(date +%s)-fossa.bundle"

  # run pre flight first
  appendHeaderToSupportBundle "PRE-FLIGHT CHECK"
  preflight >> $SUPPORT_BUNDLE 2>&1

  # append current config to file
  appendHeaderToSupportBundle "CURRENT CONFIG.ENV"
  cat ${TOP_DIR}/config.env >> $SUPPORT_BUNDLE 2>&1

  # Check contents of /var/data/fossa
  appendHeaderToSupportBundle "contents of /fossa/public/data"
  ls -al /var/data/fossa >> $SUPPORT_BUNDLE 2>&1
  
  # Check size of /var/data/fossa/.gitrepos
  appendHeaderToSupportBundle "size of /fossa/public/data/.gitrepos"
  du -sh /var/data/fossa/.gitrepos/ >> $SUPPORT_BUNDLE 2>&1

  # Check cocoapods cache
  appendHeaderToSupportBundle "Cocoapods cache"
  ls -al /var/data/fossa/.cocoapods/ >> $SUPPORT_BUNDLE 2>&1

  # Check rubygems cache
  appendHeaderToSupportBundle "Rubygems cache"
  ls -al /var/data/fossa/.rubygems/ >> $SUPPORT_BUNDLE 2>&1

  # POSTGRES info for support bundle
  appendHeaderToSupportBundle "POSTGRES NOW()"
  sudo -u postgres PGPASSWORD=$db__password psql -h $db__host -d $db__database -p $db__port -U $db__username -w -c "SELECT now();" >> $SUPPORT_BUNDLE 2>&1

  appendHeaderToSupportBundle "POSTGRES DB USERS"
  sudo -u postgres PGPASSWORD=$db__password psql -h $db__host -d $db__database -p $db__port -U $db__username -w -c "\du" >> $SUPPORT_BUNDLE 2>&1

  appendHeaderToSupportBundle "POSTGRES FOSSA VERSION"
  sudo -u postgres PGPASSWORD=$db__password psql -h $db__host -d $db__database -p $db__port -U $db__username -w -c "SELECT fossa_version();" >> $SUPPORT_BUNDLE 2>&1

  appendHeaderToSupportBundle "POSTGRES available extensions"
  sudo -u postgres PGPASSWORD=$db__password psql -h $db__host -d $db__database -p $db__port -U $db__username -w -c "SELECT name, default_version, installed_version, comment FROM pg_available_extensions ORDER BY name" >> $SUPPORT_BUNDLE 2>&1

  appendHeaderToSupportBundle "POSTGRES table collation info"
  sudo -u postgres PGPASSWORD=$db__password psql -h $db__host -d $db__database -p $db__port -U $db__username -w -c "SELECT datname, datcollate, datctype FROM pg_database" >> $SUPPORT_BUNDLE 2>&1
  
  appendHeaderToSupportBundle "POSTGRES running queries"
  sudo -u postgres PGPASSWORD=$db__password psql -h $db__host -d $db__database -p $db__port -U $db__username -w -c "SELECT query_start, query from pg_stat_activity WHERE state='active'" >> $SUPPORT_BUNDLE 2>&1

  appendHeaderToSupportBundle "POSTGRES All Indexes"
  sudo -u postgres PGPASSWORD=$db__password psql -h $db__host -d $db__database -p $db__port -U $db__username -w -c "SELECT tablename, indexname, indexdef FROM pg_indexes ORDER BY tablename" >> $SUPPORT_BUNDLE 2>&1

  appendHeaderToSupportBundle "POSTGRES All Migrations"
  sudo -u postgres PGPASSWORD=$db__password psql -h $db__host -d $db__database -p $db__port -U $db__username -w -c "SELECT name from \"SequelizeMeta\"" >> $SUPPORT_BUNDLE 2>&1

  appendHeaderToSupportBundle "POSTGRES All Users"
  sudo -u postgres PGPASSWORD=$db__password psql -h $db__host -d $db__database -p $db__port -U $db__username -w -c "SELECT username, email from \"Users\"" >> $SUPPORT_BUNDLE 2>&1

  appendHeaderToSupportBundle "POSTGRES All Organizations"
  sudo -u postgres PGPASSWORD=$db__password psql -h $db__host -d $db__database -p $db__port -U $db__username -w -c "SELECT id, title from \"Organizations\"" >> $SUPPORT_BUNDLE 2>&1

  appendHeaderToSupportBundle "POSTGRES All Policies & Rules"
  sudo -u postgres PGPASSWORD=$db__password psql -h $db__host -d $db__database -p $db__port -U $db__username -w -c "SELECT \"Policies\".title, \"Policies\".\"organizationId\", count(\"Rules\".*) as rule_count FROM \"Policies\" INNER JOIN \"Rules\" ON \"Rules\".\"policyId\" = \"Policies\".id GROUP BY \"Policies\".id" >> $SUPPORT_BUNDLE 2>&1

  appendHeaderToSupportBundle "POSTGRES All Licenses"
  sudo -u postgres PGPASSWORD=$db__password psql -h $db__host -d $db__database -p $db__port -U $db__username -w -c "SELECT count(title) as license_count from \"Licenses\"" >> $SUPPORT_BUNDLE 2>&1

  appendHeaderToSupportBundle "POSTGRES DependencyLocks Count"
  sudo -u postgres PGPASSWORD=$db__password psql -h $db__host -d $db__database -p $db__port -U $db__username -w -c "SELECT count(*) as dep_lock_count from \"DependencyLocks\"" >> $SUPPORT_BUNDLE 2>&1

  appendHeaderToSupportBundle "POSTGRES Projects Count"
  sudo -u postgres PGPASSWORD=$db__password psql -h $db__host -d $db__database -p $db__port -U $db__username -w -c "SELECT count(*) as projects_count from \"Projects\"" >> $SUPPORT_BUNDLE 2>&1

  # DOCKER info
  appendHeaderToSupportBundle "DOCKER INFO"
  docker info >> $SUPPORT_BUNDLE 2>&1
  # append docker stats to file
  appendHeaderToSupportBundle "DOCKER STATS"
  docker stats --no-stream >> $SUPPORT_BUNDLE 2>&1
  # DOCKER images (to check last updated)
  appendHeaderToSupportBundle "DOCKER IMAGES"
  docker images >> $SUPPORT_BUNDLE 2>&1

  # append all docker logs to file
  for i in $( allinstances ); do
    appendHeaderToSupportBundle "DOCKER INSPECTION & LOGS"
    docker logs $i >> $SUPPORT_BUNDLE 2>&1
    echo "" >> $SUPPORT_BUNDLE
    docker inspect $i >> $SUPPORT_BUNDLE 2>&1
    echo "" >> $SUPPORT_BUNDLE
  done
  
  appendHeaderToSupportBundle "END OF SUPPORT BUNDLE" 
  
  echo "******************************************************************************************"
  echo "Support bundle generated at:"
  echo ""
  echo "    \`$SUPPORT_BUNDLE\`"
  echo ""
  echo "Attach this file and email to support@fossa.io"
  echo "******************************************************************************************"
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

    supportbundle)
      supportbundle
    ;;

    status)
    if isrunning; then
      echo "Fossa is running"
    else
      echo "Fossa is not running"
    fi;
    ;;

    *)
    echo "Usage: $0 {start|stop|restart|init|upgrade|preflight|supportbundle}"
    exit 1
    ;;
esac

exit 0
