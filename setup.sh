#!/usr/bin/env bash

set -e

TOP_DIR="$(dirname "$(readlink -f "$0")")"

. $TOP_DIR/config.env
. $TOP_DIR/configure.sh

function setup {
  configure_environment
  save_configuration
  setup_database
}

function save_configuration {
  set | egrep '^(app|db|github|jira|bitbucket)__.*=' > $TOP_DIR/config.env
}

function setup_database {
  # See http://www.postgresql.org/docs/9.0/static/libpq-pgpass.html
  # hostname:port:database:username:password
  # TODO: Grok tmp dir of system (not always /tmp)
  PGPASSFILE=/tmp/.fossapgpass
  cat <<< "$db__hostname:$db__port:$db__database:$db__username:$db__password" > $PGPASSFILE
  psql -h $db__hostname -p $db__port -U $db__username $db__database -c "CREATE EXTENSION IF NOT EXISTS pg_trgm"
  rm $PGPASSFILE
}

setup