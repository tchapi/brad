# Deployement script for GitHub / Bitbucket / Any remote Git server
#!/bin/bash

# Common color helpers
YELLOW='\033[01;33m'  # bold yellow
RED='\033[01;31m' # bold red
GREEN='\033[01;32m' # green
BLUE='\033[01;34m'  # blue
RESET='\033[00;00m' # normal white

# Configuration file
CONFIG_FILE="$(dirname $0)/deploy.conf"

# Arguments
ARGS=$(getopt -o "hrc" -l "help,rollback,cleanup" -n $0 -- "$@");

# 
# Notifications 
#

ack(){
  echo -e " # "${GREEN}"$1"${RESET}" : $2"
}
indicate(){
  echo -e " # "${BLUE}"$1"${RESET}" : $2"
}
warn(){
  echo -e " # "${YELLOW}"$1"${RESET}" : $2"
}
ask(){
  echo -e " # "${RED}"$1"${RESET}" [$2] ?\c"
}
said_yes(){
  echo -e "   | "$(whoami)" said "${GREEN}"Yes"${RESET}"."${GREEN}" $1"${RESET}" :"
  echo ""
}
said_no(){
  echo -e "   | "$(whoami)" said "${RED}"No. "${RESET}
  echo ""
}
notify_error(){

  echo -e " # "${RED}"ERROR"${RESET}" : $1"
  echo ""

}
notify_done(){

  echo ""
  echo -e ${RESET}" # "${GREEN}"Done. "${RESET}
  echo ""

}

usage(){

  echo -e " # "${GREEN}"Usage:"${RESET}" `basename $0` [-h] [-rc] application environment [file 1 file2 ...]"
  echo -e ${BLUE}"     -h --help "${RESET}"prints this help message"
  echo -e ${BLUE}"     -r --rollback "${RESET}"rollbacks to the previous version"
  echo -e ${BLUE}"     -c --cleanup "${RESET}"cleans all previous versions upon deployment"
  echo ""

}

title(){

  echo -e ""${RESET}
  echo    " # ---------------------------------- #"
  echo -e " # "${GREEN}"Remote Git common promotion script"${RESET}" #"
  echo    " # ---------------------------------- #"
  echo ""

}


# Check major bash version
min_bash_version=4

check_bash_version(){

  bash_version=${BASH_VERSION%%[^0-9]*}

  if [ "$bash_version" -lt "$min_bash_version" ]; then
    echo ""
    indicate "Your bash version" ${BASH_VERSION}
    notify_error "Oh, ... bugger. This script requires bash > "${min_bash_version}"."
    exit 1
  fi

}

check_bash_version
# Associative arrays only in bash > 4.0, check `bash -version`for help
unset projects
declare -A projects


# -------------------------------------
# -------------------------------------

load_config(){

  indicate "Loading configuration" ${CONFIG_FILE}

  # Load configuration file
  if [[ -f $CONFIG_FILE ]]; then
          source $CONFIG_FILE
  else

    notify_error "Missing configuration file!"
    exit 1

  fi

}

parse(){

  # Bad arguments
  if [ $? -ne 0 ]; then
    notify_error "Invalid options : #@"
    usage
    exit 1
  fi

  # Magic
  eval set -- "$ARGS";

  # Parse command line options.
  while true; do
    case "$1" in
      -h|--help)
        shift;
        usage
        exit 0
        ;;
      -r|--rollback)
        shift;
        ROLLBACK=1
        ;;
      -c|--cleanup)
        shift;
        CLEANUP=1
        ;;
      --)
        shift;
        break;
        ;;
    esac
  done

  # Do we have enough arguments ?
  if [ $# -lt 2 ]; then
    notify_error "You either miss an application name or the environment name"
    usage
    exit 1
  fi

  if [ $# -ge 3 ] && [ "$ROLLBACK" = 1 ]; then
    notify_error "Cannot rollback single files"
    usage
    exit 1
  fi
  
  app=$1
  # Checking that the project exists
  project_found=false
  # What project, sir ?
  for project_slug in "${!projects[@]}"; do
    if [ "$app" = "$project_slug" ]; then
      type=${command}${projects["$project_slug"]}
      project_found=true
    fi
  done

  # Naaaaay
  if ! $project_found; then
    notify_error "Bad application name ($app)"
    exit 1
  fi

  env=$2
  # Checking environment is good
  case $env in
    "prod") env="prod";;
    "beta") env="beta";;
    *) notify_error "Bad environment ($env)"
       exit 1;;
  esac

}


main(){

  load_config
  echo ""

  parse

  date_today=`date '+%Y-%m-%d'`
  timestamp=`date '+%s'`
  DEPLOY_PATH=${APP_BASE_PATH}'/deploy/'${app}'/'${env}
  WWW_PATH=${APP_BASE_PATH}'/www/'${app}'/rel-'${env}'-'${date_today}"-"${timestamp}
  WWW_LINK=${APP_BASE_PATH}'/www/'${app}'/'${env}

  ADMIN_PATH=${DEPLOY_PATH}'/admin'

  PREVIOUS_PATHS=`ls ${APP_BASE_PATH}/www/${app} | sed -n "s|rel\-beta\-[0-9]\{4\}\-[0-9]\{2\}\-[0-9]\{2\}\-\([0-9]*\).*|\1_&|gp" | sort -n | cut -d_ -f2`
  
  # Check user
  ack "Current user is" $(whoami)

  # Application name and type
  ack "This application ${app}(${env}) is" "$type"

  indicate "Deployment path" ${DEPLOY_PATH}
  indicate "Release www path" ${WWW_PATH}
  indicate "Live www path" ${WWW_LINK}

  # Go into the deploy directory
  warn "Changing directory to" ${DEPLOY_PATH}
  echo ""
  cd ${DEPLOY_PATH}

  if [ "$type" = "standalone" ] && ! [ "$ROLLBACK" = 1] ; then build_js; fi

  if [ $# -ge 3 ]; then 
    git_pull
    scalpel
    link_scalpel
  else
    if [ "$ROLLBACK" = 1 ]; then
      revert
    else
      git_pull
      deploy
      link_full
      if [ "$CLEANUP" = 1 ]; then
        cleanup
      fi
    fi
  fi

  update_changelog
  restart_apache

  notify_done

}

git_pull(){

  # Git all the way
  ack "Checking out remote branch from origin"
  echo ""
  echo "   | "`git reset --hard HEAD`
  echo "   | "`git pull origin`
  echo "   | "`git status`
  echo ""

  revision=`git log -n 1 --pretty="format:%h %ci"`
  indicate "Repository updated to revision" ${revision}
  echo ""

  revision_safe=`git log -n 1 --pretty="format:%h"`
  WWW_PATH=${WWW_PATH}"-"${revision_safe}

}

build_js(){

  # Building minified JS if we have a minify script in admin/
  if [ -e ${ADMIN_PATH}"/minify.php" ]; then
    ask "Do you wish to build minified Javascript" "no"
    read yn
    case $yn in
        [Yy]* ) said_yes "Building minified JS"
                indicate "Minified JS Path" ${DEPLOY_PATH}"/js/min/"${app}".min.js"
                cd ${ADMIN_PATH}
                php minify.php > ${DEPLOY_PATH}/js/min/${app}.min.js
                echo "" ;;
        * ) said_no ;;
    esac

  fi

}

revert(){


  LAST_PATH=`ls $APP_BASE_PATH/www/$app | sed -n "s|rel\-$env\-[0-9]\{4\}\-[0-9]\{2\}\-[0-9]\{2\}\-\([0-9]*\).*|\1_&|gp" | sort -n | tail -2 | head -1 | cut -d_ -f2`
  LAST_PATH=${APP_BASE_PATH}'/www/'${app}/${LAST_PATH}
  
  if ! [ "$LAST_PATH" = "" ]; then

    indicate "Rollback path" ${LAST_PATH}

    ask "Are you sure you want to rollback (link)" "no"
    read yn
    case $yn in
        [Yy]* ) said_yes "Rollbacking"
                ln -sfvn ${LAST_PATH} ${WWW_LINK}
                echo "" ;;
         * ) said_no ;;
    esac

  else

    notify_error "No previous instance to rollback to, exiting."
    exit 1

  fi

}

scalpel(){

  SCALPEL_PATH=${WWW_PATH}"_scalpel"

  indicate "Duplicating actual "${env}" environment into" ${SCALPEL_PATH}

  # Copy all files from current release to a new release
  mkdir ${SCALPEL_PATH}
  rsync -rlpt ${WWW_LINK}/. ${SCALPEL_PATH}/.
  
  echo ""
  echo -e " #"${GREEN}" Scalpeling "${RESET}${env}" environment to partial release"
  echo -e " #  "${YELLOW}"\_Files : "
  
  # Checking we have files and copying
  for x in "$@"; do 
    if [ -e ${DEPLOY_PATH}"/"$x ]; then
      echo -e "    | "$x
      rsync -rlptv --inplace ${DEPLOY_PATH}/$x ${SCALPEL_PATH}/$x
    fi
  done

}

deploy(){

  warn "Promoting environment to current release" ${env}

  # Should we install the vendors before deploying ?
  if [ "$type" = "symfony2" ] || [ "$type" = "silex" ]; then

    cd ${DEPLOY_PATH}

    # Symfony2 or Silex
    echo ""
    ask "Do you wish to install [i] or update [u] vendors" "no"
    read yn
    case $yn in
        [Ii]* ) said_yes "Installing vendors via Composer"

                php composer.phar self-update
                php composer.phar install

                # Cleaning the mess since it is a deploy folder
                if [ "$type" == "symfony2" ]; then
                  rm -fR ${DEPLOY_PATH}/web/bundles
                  find ${DEPLOY_PATH}/app/cache/dev -delete
                fi

                echo "" ;;
        [Uu]* ) said_yes "Updating vendors via Composer"

                php composer.phar self-update
                php composer.phar update

                # Cleaning the mess since it is a deploy folder
                if [ "$type" == "symfony2" ]; then
                  rm -fR ${DEPLOY_PATH}/web/bundles
                  find ${DEPLOY_PATH}/app/cache/dev -delete
                fi

                echo "" ;;
         * ) said_no ;;
    esac
  
  fi

  # Copy all files to the destination folder
  mkdir ${WWW_PATH}
  if [ -f "${DEPLOY_PATH}/exclude.rsync" ]; then
    rsync -rlpt ${DEPLOY_PATH}/. ${WWW_PATH}/. --exclude-from "${DEPLOY_PATH}/exclude.rsync"
  else
    rsync -rlpt ${DEPLOY_PATH}/. ${WWW_PATH}/.
  fi

  # Symfony 2 Stuff
  if [ "$type" == "symfony2" ]; then

    cd ${WWW_PATH}

    ack "Upcoming changes to the schema"
    UPDATES=`php app/console doctrine:schema:update --dump-sql`

    echo ""
    echo ${UPDATES}
    echo ""
    
    if ! [ "$UPDATES" = "Nothing to update - your database is already in sync with the current entity metadata." ]; then

      ask "Do you wish to update the schema" "no"
      read yn
      case $yn in
          [Yy]* ) said_yes "Updating schema"
                  php app/console doctrine:schema:update --force # To be replaced with migrations later on ?
                  echo "" ;;
          * ) said_no ;;
      esac
    fi

    # Dump assetic assets
    php app/console assets:install web --symlink
    php app/console assetic:dump --env=prod --no-debug

    # Warming up caches
    php app/console cache:warmup
    php app/console cache:warmup --env=prod

    # Ensure that cache, logs are writable
    chmod -R 777 app/cache app/logs # web/uploads
    
    echo ""
 
  fi

}

link_full(){

  ask "Deployment is done — Do you wish to promote (link)" "no"
  read yn
  case $yn in
      [Yy]* ) said_yes "Linking"
              ln -sfvn ${WWW_PATH} ${WWW_LINK}
              echo "";;
       * ) said_no ;;
  esac

}


link_scalpel(){

  ask "Deployment is done — Do you wish to scalpel (link)" "no"
  read yn
  case $yn in
      [Yy]* ) said_yes "Linking"
              ln -sfvn ${SCALPEL_PATH} ${WWW_LINK}
              echo "" ;;
       * ) said_no ;;
  esac

}

cleanup(){

  warn "All these paths will be permanently deleted"
  for f in $PREVIOUS_PATHS; do
    warn "${app} ($env)" $f
  done

  ask "Are you sure you want to cleanup" "no"
  read yn
  case $yn in
      [Yy]* ) said_yes "Cleaning up"
              for f in $PREVIOUS_PATHS
              do
                PATH_TO_DELETE=${APP_BASE_PATH}'/www/'${app}/$f
                if ! [ $PATH_TO_DELETE = $WWW_PATH ]; then
                  echo -e "   | "${RED}"Removing "${RESET}"$PATH_TO_DELETE"
                  rm -fR $PATH_TO_DELETE
                fi
              done
              echo "" ;;
       * ) said_no ;;
  esac

}

update_changelog(){

  # Update CHANGELOG.txt
  CHANGELOG_NAME='CHANGELOG.txt'

  if [ "$ROLLBACK" = 1 ]; then
    BASE_CHANGELOG_PATH=${LAST_PATH}
  else
    BASE_CHANGELOG_PATH=${WWW_PATH}
  fi
  
  if [ "$type" = "symfony2" ] || [ "$type" = "silex" ]; then
    CHANGELOG_PATH=${BASE_CHANGELOG_PATH}'/web/'${CHANGELOG_NAME}
  elif [ "$type" = "standalone" ]; then
    CHANGELOG_PATH=${BASE_CHANGELOG_PATH}'/'${CHANGELOG_NAME}
  fi

  indicate "Writing CHANGELOG to" ${CHANGELOG_PATH}

  echo "# CHANGELOG" > ${CHANGELOG_PATH}

  if [ "$ROLLBACK" = 1 ]; then

    NOW=$(date +"%c")
    echo "# Last update : ${NOW}" >> ${CHANGELOG_PATH}
    echo "# ! Site is now in ROLLBACKED state !" >> ${CHANGELOG_PATH}
    echo "" >> ${CHANGELOG_PATH}

  else 

    cd ${DEPLOY_PATH}

    current_date=`git log -1 --format="%ad"`
    echo "# Last update : ${current_date}" >> ${CHANGELOG_PATH}
    echo "" >> ${CHANGELOG_PATH}

    change_log=`git log --no-merges --date-order --date=rfc | \
      sed -e '/^commit.*$/d' | \
      awk '/^Author/ {sub(/\\$/,""); getline t; print $0 t; next}; 1' | \
      sed -e 's/^Author: //g' | \
      sed -e 's/>Date:   \(.*\)/>\t\1/g' | \
      sed -e 's/^\(.*\) \(\)\t\(.*\)/\3    \1    \2/g' >> ${CHANGELOG_PATH}`

  fi

  echo ""

}

restart_apache(){

  # Restart Apache
  ask "Do you wish to restart Apache 2" "no"
  read yn
  case $yn in
      [Yy]* ) said_yes "Restarting Apache"
              sudo /root/apachereload.sh
              ;;
      * ) said_no ;;
  esac

}

# Launches :
title
main
