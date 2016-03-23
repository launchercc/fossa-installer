#!/usr/bin/env bash
source ./config.list

# Find PG_CTL_BIN
if [ ! -f $PG_CTL_BIN ]; then
  PG_CTL_BIN=$( which pg_ctl || find /usr/lib/postgresql -name pg_ctl | head -1 | egrep '.*' )
fi;

if [ ! -f $PG_CTL_BIN ]; then
  echo "Could not find PG_CTL binary. Please set PG_CTL_BIN";
  exit 1;
fi;
