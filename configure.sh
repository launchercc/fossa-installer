#!/usr/bin/env bash

function configure_environment {
  echo "Configuring Fossa!"
  echo

  echo "Step 1: Server"
  echo
  configure_server

  echo
  echo "Step 2: Database"
  echo
  configure_database
  configure_rubygems_database

  echo
  echo "Step 3: Email"
  echo
  configure_email

  echo
  echo "Step 4: Integrations"
  echo
  configure_github
  configure_bitbucket
  configure_gitlab
  configure_jira

  echo
  echo "Step 5: Cocoapods API"
  echo
  configure_cocoapods_api

  echo
  echo "Step 6: Generating Secret Key"
  echo
  configure_secret_key

  echo
  echo "Finished configuring Fossa"
  echo
}

# Sections
function configure_server {
  read -p "Server hostname [localhost]: " app__hostname
  app__hostname=${app__hostname:-localhost}
  read -p "Server port [80]: " app__port
  app__port=${app__port:-80}
}

function configure_database {
  read -p "Database hostname [localhost]: " db__host
  db__host=${db__host:-localhost}
  read -p "Database port [5432]: " db__port
  db__port=${db__port:-5432}
  read -p "Database name [fossa]: " db__database
  db__database=${db__database:-fossa}
  read -p "Database username [fossa]: " db__username
  db__username=${db__username:-fossa}
  qpasswordretry "Database password: " "db__password" false
}

function configure_rubygems_database {
  local db_rubygems__enabled
  read -p "Configure rubygems (Y|N)? [N]: " db_rubygems__enabled
  case $db_rubygems__enabled in
    [Yy]* )
      db_rubygems__enabled=true
      read -p "Database hostname [localhost]: " db_rubygems__host
      db_rubygems__host=${db_rubygems__host:-localhost}
      read -p "Database port [5432]: " db_rubygems__port
      db_rubygems__port=${db_rubygems__port:-5432}
      read -p "Database name [rubygems]: " db_rubygems__database
      db_rubygems__database=${db_rubygems__database:-rubygems}
      read -p "Database username [fossa]: " db_rubygems__username
      db_rubygems__username=${db_rubygems__username:-fossa}
      qpasswordretry "Database password: " "db_rubygems__password" false
    ;;
    * )
      echo "Skipping Rubygems configuration"
      echo
    ;;
  esac
}

function configure_github {
  read -p "Configure github (Y|N)? [N]: " github__enabled
  case $github__enabled in
    [Yy]* )
      echo "Configuring Github!"
      echo
      github__enabled=true
      read -p "Github base URL [https://github.mycompany.com]: " github__base_url
      github__base_url=${github__base_url:-https://github.mycompany.com}
      qnotempty "Github client ID: " github__credentials__oauth2__client_id "Github client ID cannot be empty. Try again!"
      qpassword "Github client secret: " github__credentials__oauth2__client_secret false
      echo "Finished configuring Github!"
      echo
    ;;
    * )
      echo "Skipping Github configuration"
      echo
    ;;
  esac
}

function configure_bitbucket {
  local bitbucket__enabled
  read -p "Configure Bitbucket (Y|N)? [N]: " bitbucket__enabled
  case $bitbucket__enabled in
    [Yy]* )
      echo "Configuring Bitbucket!"
      echo
      bitbucket__enabled=true
      read -p "Bitbucket base URL [http://localhost:7990/]: " bitbucket__base_url
      bitbucket__base_url=${bitbucket__base_url:-http://localhost:7990/}
      read -p "Bitbucket oauth2 client id [fossa]: " bitbucket__oauth2_client_id
      bitbucket__oauth2_client_id=${bitbucket__oauth2_client_id:-fossa}
      qnotempty "Bitbucket username: " bitbucket__credentials__basic__username "Bitbucket username cannot be empty. Try again!"
      qpasswordretry "Bitbucket password: " "bitbucket__credentials__basic__password" false

      echo "Finished configuring Bitbucket!"
      echo
    ;;
    * )
      echo "Skipping Bitbucket configuration"
      echo
    ;;
  esac
}

function configure_gitlab {
  local gitlab__enabled
  read -p "Configure Gitlab (Y|N)? [N]: " gitlab__enabled
  case $gitlab__enabled in
    [Yy]* )
      echo "Configuring Gitlab!"
      echo
      gitlab__enabled=true
      read -p "Gitlab base URL [http://localhost:7990/]: " gitlab__base_url
      gitlab__base_url=${gitlab__base_url:-http://localhost:7990/}
      read -p "Gitlab oauth2 client id [fossa]: " gitlab__oauth2_client_id
      gitlab__oauth2_client_id=${gitlab__oauth2_client_id:-fossa}
      qnotempty "Gitlab username: " gitlab__credentials__basic__username "Gitlab username cannot be empty. Try again!"
      qpasswordretry "Gitlab password: " "gitlab__credentials__basic__password" false

      echo "Finished configuring Gitlab!"
      echo
    ;;
    * )
      echo "Skipping Gitlab configuration"
      echo
    ;;
  esac
}

function configure_jira {
  local enabled
  read -p "Configure jira (Y|N)? [N]: " enabled
  case $enabled in
    [Yy]* )
      echo "Configuring Jira!"
      echo

      read -p "Jira base URL [http://localhost:8080]: " jira__base_url
      jira__base_url=${jira__base_url:-http://localhost:8080}
      read -p "Jira resolved status [done]: " jira__resolved_status
      jira__resolved_status=${jira__resolved_status:-done}
      qnotempty "Jira username: " jira__credentials__username "Jira username cannot be empty. Try again!"
      qpasswordretry "Jira password: " "jira__credentials__password" false

      echo "Finished configuring Jira!"
      echo
    ;;
    * )
      echo "Skipping Jira configuration"
      echo
    ;;
  esac
}

function configure_cocoapods_api {
  read -p "Configure cocoapods_api (Y|N)? [N]: " cocoapods_api__enabled
  case $cocoapods_api__enabled in
    [Yy]* )
      echo "Configuring Cocoapods!"
      echo
      cocoapods_api__enabled=true
      read -p "api protocol [http]: " cocoapods_api__protocol
      cocoapods_api__protocol=${cocoapods_api__protocol:-http}
      read -p "api hostname [fossa-cocoapods-api]: " cocoapods_api__hostname
      cocoapods_api__hostname=${cocoapods_api__hostname:-fossa-cocoapods-api}
      read -p "api port [9292]: " cocoapods_api__port
      cocoapods_api__port=${cocoapods_api__port:-9292}
      
      echo "Finished configuring Cocoapods API!"
      echo
    ;;
    * )
      echo "Skipping Cocoapods API configuration"
      echo
    ;;
  esac
}

function configure_email {
  read -p "Email hostname [localhost]: " email__transport__options__host
  email__transport__options__host=${email__transport__options__host:-localhost}
  read -p "Email port [5432]: " email__transport__options__port
  email__transport__options__port=${email__transport__options__port:-5432}
  read -p "Email username: " email__transport__options__auth__user
  qpasswordretry "Email password: " "email__transport__options__auth__pass" true
}

function configure_secret_key {
  secret=$( cut -c 1-64 <( xxd -ps <<< $( dd if=/dev/urandom count=32 ibs=1 2> /dev/null ) | tr -d '\n' ) )
}


# Utility functions
function qnotempty {
  local prompt=$1
  local envvar=$2
  local emptymsg=$3

  read -p "$prompt" $envvar
  while [ "${!envvar}" == "" ];
  do
    echo "$emptymsg"
    echo
    read -p "$prompt" -s $envvar
    echo
  done
}

function qpassword {
  local prompt=$1
  local envvar=$2
  local allowempty=$3
  read -p "$prompt" -s $envvar
  echo

  if ! $allowempty ;
  then
    while [ "${!envvar}" == "" ];
    do
      echo "No password provided!"
      echo
      read -p "$prompt" -s $envvar
      echo
    done
  fi;
}

function qpasswordretry {
  local prompt=$1
  local envvar=$2
  local allowempty=$3
  local password2

  qpassword "$prompt" $envvar $allowempty
  qpassword "verify: " password2 $allowempty

  while [ "${!envvar}" != "$password2" ];
  do
    echo
    echo "Passwords do not match!"
    qpassword "$prompt" $envvar $allowempty
    qpassword "verify: " password2 $allowempty
  done
}
