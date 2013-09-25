#!/bin/bash
# Init script for further deployment

# Configuration :

# Live
LIVE_BRANCH='live'
LIVE_DIRECTORY='prod'

# Staging
STAGING_BRANCH='staging'
STAGING_DIRECTORY='beta'

# Deploy and WWW directories
DEPLOY_DIRECTORY='deploy'
WWW_DIRECTORY='www'

# Global colors
YELLOW='\033[01;33m'  # bold yellow
RED='\033[01;31m' # bold red
GREEN='\033[01;32m' # green
BLUE='\033[01;34m'  # blue
RESET='\033[00;00m' # normal white

# Load configuration file
CONFIG_FILE="$(dirname $0)/deploy.conf"

# Associative arrays only in bash > 4.0, check `bash -version`for help
unset projects
declare -A projects

if [[ -f $CONFIG_FILE ]]; then
        . $CONFIG_FILE
else

  echo ""
  echo -e ${GREEN}" Project initialisation script "${RESET}
  echo -e ${RED}" Missing deploy.conf configuration file!"${RESET}"."
  echo ""
  exit 1

fi

# Check if we have the correct number of arguments
# if [ $# -lt 2 ]
# then
#   echo ""
#   echo -e ${GREEN}" Project initialisation script "${RESET}
#   echo " Usage: $0 "
#   echo " Before using, update your deploy.conf file to add your projet name and type."
#   echo ""
#   exit 1
# fi


# Listing projects available
echo -e ${GREEN}" Projects available to init :"${RESET}
for project_slug in "${!projects[@]}"; do
  echo -e " - ${BLUE}$project_slug${RESET} (type: ${YELLOW}${command}${projects["$project_slug"]}${RESET})"
done

echo ""
echo -e " # "${GREEN}"What project do you want to init"${RESET}" ?\c"
read name

# What project, sir ?
project_found=false
for project_slug in "${!projects[@]}"; do
  if [ "$name" = "$project_slug" ]; then
    type=${command}${projects["$project_slug"]}
    project_found=true
  fi
done

# Naaaaay
if ! $project_found; then
  echo -e ${RED}"Bad application name ('"${name}"'')"${RESET}
  exit 1
fi

# We're good to go !
# We need an url to init
echo -e " # "${GREEN}"What is the url of your repository"${RESET}" ?\c"
read url

# Check if type is valid :
git ls-remote "$url" &>-
if [ "$?" -ne 0 ]; then
  echo ""
  echo -e ${GREEN}" Project initialisation script "${RESET}
  echo -e ${RED}" Error: "${RESET}"$url is not a valid GIT repository url"
  echo ""
  exit 1
fi

# Check if url is a valid one
git ls-remote "$url" &>-
if [ "$?" -ne 0 ]; then
  echo ""
  echo -e ${GREEN}" Project initialisation script "${RESET}
  echo -e ${RED}" Error: "${RESET}"'$url' is not a valid GIT repository url"
  echo ""
  exit 1
fi

# Initializing the repos

cd ${APP_BASE_PATH}/${DEPLOY_DIRECTORY}/
mkdir $name

# Check the existence of branches
HAS_STAGING=`git ls-remote $url | grep ${STAGING_BRANCH} | wc -l`
HAS_LIVE=`git ls-remote $url | grep ${LIVE_BRANCH} | wc -l`

if [ "$HAS_LIVE" -lt 1 ]; then
  echo -e ${RED}" ERROR : no ${LIVE_BRANCH} branch"${RESET}
  exit 1
fi

if [ "$HAS_STAGING" -lt 1 ]; then
  echo -e ${YELLOW}" INFO : no ${STAGING_BRANCH} branch"${RESET}
fi

# Installing STAGING environment
if [ "$HAS_STAGING" -gt 0 ]; then

  cd ${APP_BASE_PATH}/${DEPLOY_DIRECTORY}/${name}
  mkdir ${STAGING_DIRECTORY}

  cd ${APP_BASE_PATH}/${DEPLOY_DIRECTORY}/${name}/${STAGING_DIRECTORY}
  git init
  git remote add -t ${STAGING_BRANCH} -f origin $url

  git checkout ${STAGING_BRANCH}

  if [ "$type" = "symfony2" ] || [ "$type" = "silex" ]; then

    curl -S http://getcomposer.org/installer | php
    php composer.phar self-update
    php composer.phar install --prefer-dist

    # web/uploads for apache uploads
    if [ "$type" = "symfony2" ]; then
      cd web
      ln -s ../../uploads uploads
      chmod 777 uploads

      # var/sessions for sessions storage
      cd app
      ln -s ../../var/beta var
      chmod 777 var
      cd var
      mkdir sessions
      chmod 777 sessions
    fi

  fi

fi

# Installing PROD environment

cd ${APP_BASE_PATH}/${DEPLOY_DIRECTORY}/${name}
mkdir ${LIVE_DIRECTORY}

cd ${APP_BASE_PATH}/${DEPLOY_DIRECTORY}/${name}/${LIVE_DIRECTORY}
git init
git remote add -t ${LIVE_BRANCH} -f origin $url
git checkout ${LIVE_BRANCH}

if [ "$type" = "symfony2" ] || [ "$type" = "silex" ]; then

  curl -S http://getcomposer.org/installer | php
  php composer.phar self-update
  php composer.phar install --prefer-dist

  if [ "$type" = "symfony2" ]; then
    cd web
    ln -s ../../uploads uploads
    chmod 777 uploads

    # var/sessions for sessions storage
    cd app
    ln -s ../../var/prod var
    chmod 777 var
    cd var
    mkdir sessions
    chmod 777 sessions
  fi

fi

# Creating Web folders

cd ${APP_BASE_PATH}/${WWW_DIRECTORY}/
mkdir $name

# Rights
if [ "$type" = "symfony2" ]; then
  
  cd ${APP_BASE_PATH}/${WWW_DIRECTORY}/${name}
  mkdir uploads
  chmod 777 uploads

  mkdir var
  chmod 777 var

fi

# Summary

echo -e ${RESET}
echo -e " # "${GREEN}"Created environnements :"${RESET}
echo -e " |  - Staging "
echo -e " |    "${YELLOW}"Deploy path : "${RESET}${APP_BASE_PATH}/${DEPLOY_DIRECTORY}/${name}/${STAGING_DIRECTORY}
echo -e " |    "${YELLOW}" --> tracking branch "${RESET}${STAGING_BRANCH}${YELLOW}" of remote "${RESET}${url}

echo -e " |  - Live "
echo -e " |    "${YELLOW}"Deploy path : "${RESET}${APP_BASE_PATH}/${DEPLOY_DIRECTORY}/${name}/${LIVE_DIRECTORY}
echo -e " |    "${YELLOW}" --> tracking branch "${RESET}${LIVE_BRANCH}${YELLOW}" of remote "${RESET}${url}

echo -e " |  - Web Server "
echo -e " |    "${BLUE}"Apache path : "${RESET}${APP_BASE_PATH}/${WWW_DIRECTORY}/${name}
echo ""

# Done
echo -e ${RESET}
echo -e " # "${GREEN}"Done. "${RESET}"Exiting."
echo ""