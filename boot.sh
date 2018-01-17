#!/usr/bin/env bash
TOP_DIR=${TOP_DIR-"$(dirname "$(readlink -f "$0")")"}
DOCKER_IMAGE=${DOCKER_IMAGE-"quay.io/fossa/fossa:release"}
DB_DOCKER_IMAGE=${DB_DOCKER_IMAGE-"quay.io/fossa/db:release"}
COCOAPODS_DOCKER_IMAGE=${COCOAPODS_DOCKER_IMAGE-"quay.io/fossa/fossa-cocoapods-api:release"}
PRE_040=${PRE_040-}
PRE_050=${PRE_050-}
DATADIR=${DATADIR-"/var/data/fossa"}
DB_DATADIR=${DB_DATADIR-"/var/data/pg"}
PREFLIGHTLOG=${PREFLIGHTLOG-"$DATADIR/fossa-preflight.log"}
MIGRATIONLOG=${MIGRATIONLOG-"$DATADIR/fossa-migration.log"}
SERVERLOG=${SERVERLOG-"$DATADIR/fossa-server.log"}
AGENTLOG=${AGENTLOG-"$DATADIR/fossa-agent.log"}

. $TOP_DIR/config.env
. $TOP_DIR/configure.sh

function allinstances {
  docker ps --filter="ancestor=$DOCKER_IMAGE" -aq
  if [ "$db__builtin" = true ]; then
    docker ps --filter="ancestor=$DB_DOCKER_IMAGE" -aq
  fi;
  if [ "$cocoapods_api__enabled" = true ]; then
    docker ps --filter="ancestor=$COCOAPODS_DOCKER_IMAGE" -aq
  fi
}

function runninginstances {
  docker ps --filter="ancestor=$DOCKER_IMAGE" -q
  # do not include db as we want to boot separately
  if [ "$cocoapods_api__enabled" = true ]; then
    docker ps --filter="ancestor=$COCOAPODS_DOCKER_IMAGE" -q
  fi
}

function isrunning {
  [ "$( runninginstances )" ]
}

function isdbrunning {
  [ "$( docker ps --filter="ancestor=$DB_DOCKER_IMAGE" -q )" ]
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
  echo "---------------------------"
  # run and return stdout or stderr state of this (and write to log file)
  docker run `if [ "$db__builtin" = true ]; then echo "--link=fossadb:db"; fi`  --rm --env-file ${TOP_DIR}/config.env -v $DATADIR:/fossa/public/data $DOCKER_IMAGE yarn run preflight --silent  2>&1 | tee $PREFLIGHTLOG

  return "${PIPESTATUS[0]}" # return the exit code of the docker run `if [ "$db__builtin" = true ]; then echo "--link=fossadb:db"; fi`  command
}

function start {
  echo "Starting Fossa"
  NUMBER_OF_AGENTS=${1-4}

  if [ "$db__builtin" = true ] && ! isdbrunning; then
    # Using builtin db, so lets boot it first...
    echo "Booting built-in FOSSA db..."
    docker run --name fossadb --rm -d -v $DB_DATADIR:/var/lib/postgresql/data/fossa -p 5432:5432 $DB_DOCKER_IMAGE
    echo "Waiting for db..."

    RETRIES=60
    DB_IS_READY=false 
    until [ $DB_IS_READY = true ]; do 
      if docker logs fossadb 2>&1 | grep -q 'No such container' || [ $RETRIES -eq 0 ]; then
        # TODO: add some way of getting debug logs
        echo "Failed to boot built-in db."
        stop;
        exit 1;
      elif docker logs fossadb 2>&1 | grep -q 'ready to accept connections'; then 
        DB_IS_READY=true
        echo "Database is ready!"
      else 
        echo "Checking if ready; $((RETRIES--))s timeout..."
        sleep 1
      fi;
    done
  fi;

  if [ "$SKIP_PREFLIGHT" != true ]; then
    # preflight checks
    if preflight; then
      echo ""
      echo "Preflight checks passed, booting..."
    else
      echo ""
      echo "Preflight checks failed. Fix your configuration or force boot with by setting the SKIP_PREFLIGHT env variable to true."
      stop;
      echo "To generate a support bundle, run \`fossa supportbundle\`"
      exit 1;
    fi
  else
    echo "Skipping preflight checks..."
  fi;

  # Migrate database
  if [[ ${PRE_040} ]]; then
    docker run `if [ "$db__builtin" = true ]; then echo "--link=fossadb:db"; fi`  --rm --env-file ${TOP_DIR}/config.env -v $DATADIR:/fossa/public/data $DOCKER_IMAGE yarn run migrate:pre-0.4.0 2>&1 | tee $MIGRATIONLOG
  elif [[ ${PRE_050} ]]; then
    docker run `if [ "$db__builtin" = true ]; then echo "--link=fossadb:db"; fi`  --rm --env-file ${TOP_DIR}/config.env -v $DATADIR:/fossa/public/data $DOCKER_IMAGE yarn run migrate:pre-0.5.0 2>&1 | tee $MIGRATIONLOG
  else
    docker run `if [ "$db__builtin" = true ]; then echo "--link=fossadb:db"; fi`  --rm --env-file ${TOP_DIR}/config.env -v $DATADIR:/fossa/public/data $DOCKER_IMAGE yarn run migrate 2>&1 | tee $MIGRATIONLOG
  fi;

  if [ "${PIPESTATUS[0]}" -ne 0 ]; then # if the migration failed
    echo ""
    echo "Migration has failed. Make sure that your config is correct before trying again."
    echo "To generate a support bundle, run \`fossa supportbundle\`"
    exit 1;
  fi

  if [ "$cocoapods_api__enabled" = true ]; then
    # Migrate Cocoapods API
    docker run `if [ "$db__builtin" = true ]; then echo "--link=fossadb:db"; fi`  --rm --env-file ${TOP_DIR}/config.env -p 9292:9292 -v $DATADIR:/fossa/public/data -v /etc/fossa/.ssh:/root/.ssh $COCOAPODS_DOCKER_IMAGE ruby /app/scripts/cocoapods_setup
    
    # Run Cocoapods API
    docker run `if [ "$db__builtin" = true ]; then echo "--link=fossadb:db"; fi`  --rm -d --env-file ${TOP_DIR}/config.env -p 9292:9292 -v $DATADIR:/fossa/public/data -v /etc/fossa/.ssh:/root/.ssh $COCOAPODS_DOCKER_IMAGE bundle exec puma -C /app/config/production.rb
  fi;

  # run core server
  docker run `if [ "$db__builtin" = true ]; then echo "--link=fossadb:db"; fi`  --name fossacore --rm -di --env-file ${TOP_DIR}/config.env -p 80:80 -p 443:443 -v $DATADIR:/fossa/public/data $DOCKER_IMAGE yarn run start

  # run watchdogs
  docker run `if [ "$db__builtin" = true ]; then echo "--link=fossadb:db"; fi`  --rm -d --env-file ${TOP_DIR}/config.env -v $DATADIR:/fossa/public/data $DOCKER_IMAGE yarn run start:watchdogs:task
  docker run `if [ "$db__builtin" = true ]; then echo "--link=fossadb:db"; fi`  --rm -d --env-file ${TOP_DIR}/config.env -v $DATADIR:/fossa/public/data $DOCKER_IMAGE yarn run start:watchdogs:revision
  docker run `if [ "$db__builtin" = true ]; then echo "--link=fossadb:db"; fi`  --rm -d --env-file ${TOP_DIR}/config.env -v $DATADIR:/fossa/public/data $DOCKER_IMAGE yarn run start:watchdogs:updateHook
  docker run `if [ "$db__builtin" = true ]; then echo "--link=fossadb:db"; fi`  --rm -d --env-file ${TOP_DIR}/config.env -v $DATADIR:/fossa/public/data $DOCKER_IMAGE yarn run start:watchdogs:dependencyLock

  current=$( runninginstances )

  # run agents
  while [ ${NUMBER_OF_AGENTS} -gt 0 ]; do
    docker run `if [ "$db__builtin" = true ]; then echo "--link=fossadb:db"; fi`  --rm -d --env-file ${TOP_DIR}/config.env -v $DATADIR:/fossa/public/data $DOCKER_IMAGE yarn run start:agent
    (( NUMBER_OF_AGENTS-- ))
  done;

  docker logs fossacore --follow
}

function stop {
  echo "Stopping Fossa"

  # Kill running images
  docker kill $( runninginstances ) 2>&1 > /dev/null
  
  # Remove existing container
  # docker rm -f $( allinstances ) 2>&1 > /dev/null
}

function appendHeaderToSupportBundle {
  echo "--------------------------------------------------------------" >> $SUPPORT_BUNDLE
  echo "$1" >> $SUPPORT_BUNDLE
  echo "--------------------------------------------------------------" >> $SUPPORT_BUNDLE
}

function supportbundle {
  echo "Creating support bundle..."
  local SUPPORT_BUNDLE="$DATADIR/$(date +%s)-fossa.bundle"

  # run pre flight first
  appendHeaderToSupportBundle "PRE-FLIGHT CHECK"
  preflight >/dev/null 2>&1 
  cat $PREFLIGHTLOG >> $SUPPORT_BUNDLE 2>&1 # get result from logs

  # get migration log
  appendHeaderToSupportBundle "MIGRATION LOGS"
  cat $MIGRATIONLOG >> $SUPPORT_BUNDLE 2>&1

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
    supportbundle;
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
