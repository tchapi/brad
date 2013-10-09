#!/bin/bash
# Deployement script for GitHub / Bitbucket / Any remote Git server

# Use BootSHtrap
# __DEBUG=1 # Sets the debug mode, which outputs logs to standard output
source bootshtrap/bootshtrap/autoload.sh # Autoloads the whole stuff

# Associative arrays for projects in config
unset projects
declare -A projects

# Globals
DEPLOY_DIRECTORY='deploy'
WWW_DIRECTORY='www'

# Live branch and directory
LIVE_BRANCH='live'
LIVE_DIRECTORY='prod'

# Staging branch and directory
STAGING_BRANCH='staging'
STAGING_DIRECTORY='beta'

# Main entry point
main(){

  load_config_file "$(dirname $0)/deploy.conf"

  check_arguments

  date_today=`date '+%Y-%m-%d'`
  timestamp=`date '+%s'`
  DEPLOY_PATH=${APP_BASE_PATH}'/'${DEPLOY_DIRECTORY}'/'${app}'/'${env}
  WWW_PATH=${APP_BASE_PATH}'/'${WWW_DIRECTORY}'/'${app}'/rel-'${env}'-'${date_today}"-"${timestamp}
  WWW_LINK=${APP_BASE_PATH}'/'${WWW_DIRECTORY}'/'${app}'/'${env}

  ADMIN_PATH=${DEPLOY_PATH}'/admin'

  PREVIOUS_PATHS=`ls ${APP_BASE_PATH}/${WWW_DIRECTORY}/${app} | sed -n "s|rel\-${env}\-[0-9]\{4\}\-[0-9]\{2\}\-[0-9]\{2\}\-\([0-9]*\).*|\1_&|gp" | sort -n | cut -d_ -f2`
  
  # Check user
  ack "Current user is" $(whoami)

  # Application name and type
  ack "This application ${app} (${env}) is" "$type"

  indicate "Deployment path" ${DEPLOY_PATH}
  indicate "Release www path" ${WWW_PATH}
  indicate "Live www path" ${WWW_LINK}

  # Go into the deploy directory
  warn "Changing directory to" ${DEPLOY_PATH}
  clear
  cd ${DEPLOY_PATH}

  # Init or Deploy ?
  if [ "$INIT" = 1 ]; then
    # ---- INIT ----

    # Check if git url is valid :
    git ls-remote "$GIT_URL" &>- # Problem: creates a "./-" file ????
    if [ "$?" -ne 0 ]; then
      notify_error "$url is not a valid GIT repository url"
      error_exit
    fi

    init_repo

    # ---- END : INIT ----
  else
    # ---- DEPLOY ----

    if [ $# -ge 3 ]; then 
      git_pull
      if [ "$type" = "standalone" ] && ! [ "$ROLLBACK" = 1 ] ; then build_js; fi
      scalpel
      link_scalpel
    else
      if [ "$ROLLBACK" = 1 ]; then
        revert
      else
        git_pull
        if [ "$type" = "standalone" ] && ! [ "$ROLLBACK" = 1 ] ; then build_js; fi
        deploy
        link_full
        if [ "$CLEANUP" = 1 ]; then
          cleanup
        fi
      fi
    fi

    install_crontabs
    update_changelog
    restart_apache

    # ---- END : DEPLOY ----
  fi

  
  notify_done

}

# Check that app, env and oter arguments are ok
check_arguments(){

  if [ $# -ge 3 ] && [ "$ROLLBACK" = 1 ]; then
    notify_error "Cannot rollback single files"
    usage
    error_exit
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
    error_exit
  fi

  env=$2
  # Checking environment is good
  case $env in
    "prod") env="$LIVE_DIRECTORY";;
    "beta") env="$STAGING_DIRECTORY";;
    *) notify_error "Bad environment ($env)"
       error_exit;;
  esac

}

# Set flags
set_cleanup_flag(){ 
  CLEANUP=1
}
set_init_flag(){ 
  INIT=1
  GIT_URL="$1"
}
set_rollback_flag(){ 
  ROLLBACK=1
}

init_repo(){

  DIR_PATH=`readlink -f "${app}"` # Get rid of symlinks and get abs path
  if [[ -d "${DIR_PATH}" ]] ; then # now we're testing
    notify_error "This application already has a deployment folder ($app)"
    error_exit
  fi

  # We create a dir for the app if it doesn't already exist
  mkdir $app

  # Check the existence of branches
  HAS_STAGING=`git ls-remote $GIT_URL | grep ${STAGING_BRANCH} | wc -l`
  HAS_LIVE=`git ls-remote $GIT_URL | grep ${LIVE_BRANCH} | wc -l`

  if [ "$HAS_LIVE" -lt 1 ]; then
    notify_error "no ${LIVE_BRANCH} branch"
    error_exit
  fi

  if [ "$HAS_STAGING" -lt 1 ]; then
    warn "no ${STAGING_BRANCH} branch"
  fi

  # Installing STAGING deployed environment
  if [ "$HAS_STAGING" -gt 0 ]; then

    cd ${APP_BASE_PATH}/${DEPLOY_DIRECTORY}/${app}
    mkdir ${STAGING_DIRECTORY}

    cd ${APP_BASE_PATH}/${DEPLOY_DIRECTORY}/${app}/${STAGING_DIRECTORY}
    git init
    git remote add -t ${STAGING_BRANCH} -f origin $GIT_URL

    git checkout ${STAGING_BRANCH}

    if [ "$type" = "symfony2" ] || [ "$type" = "silex" ]; then

      curl -S http://getcomposer.org/installer | php
      php composer.phar self-update
      php composer.phar install --prefer-dist

      # web/uploads for apache uploads
      if [ "$type" = "symfony2" ]; then
        cd web
        ln -s ../../uploads uploads
        chmod 775 uploads

        # var/sessions for sessions storage
        cd app
        ln -s ../../var/beta var
        chmod 775 var
        cd var
        mkdir sessions
        chmod 775 sessions
      fi

    fi

  fi

  # Installing PROD deployed environment

  cd ${APP_BASE_PATH}/${DEPLOY_DIRECTORY}/${app}
  mkdir ${LIVE_DIRECTORY}

  cd ${APP_BASE_PATH}/${DEPLOY_DIRECTORY}/${app}/${LIVE_DIRECTORY}
  git init
  git remote add -t ${LIVE_BRANCH} -f origin $GIT_URL
  git checkout ${LIVE_BRANCH}

  if [ "$type" = "symfony2" ] || [ "$type" = "silex" ]; then

    curl -S http://getcomposer.org/installer | php
    php composer.phar self-update
    php composer.phar install --prefer-dist

    if [ "$type" = "symfony2" ]; then
      cd web
      ln -s ../../uploads uploads
      chmod 775 uploads

      # var/sessions for sessions storage
      cd app
      ln -s ../../var/prod var
      chmod 775 var
      cd var
      mkdir sessions
      chmod 775 sessions
    fi

  fi

  # Creating Web folders
  cd ${APP_BASE_PATH}/${WWW_DIRECTORY}/
  mkdir $app

  # Rights
  if [ "$type" = "symfony2" ]; then
    
    cd ${APP_BASE_PATH}/${WWW_DIRECTORY}/${app}
    
    mkdir uploads
    chmod 775 uploads

    mkdir var
    chmod 775 var

  fi

  # Summary

  ack "Created environnements :"
  indicate "Remote repository" ${GIT_URL}

  indicate "Staging Deploy path" ${APP_BASE_PATH}/${DEPLOY_DIRECTORY}/${app}/${STAGING_DIRECTORY}
  indicate " --> tracking branch" ${STAGING_BRANCH}

  indicate "Live Deploy path" ${APP_BASE_PATH}/${DEPLOY_DIRECTORY}/${app}/${LIVE_DIRECTORY}
  indicate " --> tracking branch " ${LIVE_BRANCH}

  indicate "Web path" ${APP_BASE_PATH}/${WWW_DIRECTORY}/${app}
  clear

  # Done
  notify_done
  exit 0

}

# Fetches and merge the changes found on the remote branch of the given folder
git_pull(){

  # Git all the way
  ack "Checking out remote branch from origin"
  clear
  echo "   | "`git reset --hard HEAD`
  echo "   | "`git pull origin`
  echo "   | "`git status`
  clear

  revision=`git log -n 1 --pretty="format:%h %ci"`
  indicate "Repository updated to revision" ${revision}
  clear

  revision_safe=`git log -n 1 --pretty="format:%h"`
  WWW_PATH=${WWW_PATH}"-"${revision_safe}

}

# Builds minified JS if needed (if exists /minify.php)
build_js(){

  # Building minified JS if we have a minify script in admin/
  if [ -e ${ADMIN_PATH}"/minify.php" ]; then

    answer=`ask "Do you wish to build minified Javascript" "no"`
    case $answer in
        [Yy]* ) said_yes "Building minified JS"
                cd ${ADMIN_PATH}
                php minify.php > ${DEPLOY_PATH}/js/min/${app}.min.js
                indicate "Minified JS Path" ${DEPLOY_PATH}"/js/min/"${app}".min.js"
                ;;
        * ) said_no ;;
    esac

  fi

}


# Scalpels only a single file
scalpel(){

  SCALPEL_PATH=${WWW_PATH}"_scalpel"

  indicate "Duplicating actual "${env}" environment into" ${SCALPEL_PATH}

  # Copy all files from current release to a new release
  mkdir ${SCALPEL_PATH}
  rsync -rlpt ${WWW_LINK}/. ${SCALPEL_PATH}/.
  
  indicate "Scalpeling "${env}" environment to partial release"
  indicate "\_Files : "
  
  # Checking we have files and copying
  for x in "$@"; do 
    if [ -e ${DEPLOY_PATH}"/"$x ]; then
      warn "   " $x
      rsync -rlptv --inplace ${DEPLOY_PATH}/$x ${SCALPEL_PATH}/$x
    fi
  done

}

# Deploys to current release
deploy(){

  warn "Promoting environment to current release" ${env}

  # Should we install the vendors before deploying ?
  if [ "$type" = "symfony2" ] || [ "$type" = "silex" ]; then

    cd ${DEPLOY_PATH}

    # Symfony2 or Silex
    yn=`ask "Do you wish to install [i] or update [u] vendors" "no"`
    case $yn in
        [Ii]* ) said_yes "Installing vendors via Composer"

                php composer.phar self-update
                php composer.phar install

                # Cleaning the mess since it is a deploy folder
                if [ "$type" = "symfony2" ]; then
                  rm -fR ${DEPLOY_PATH}/web/bundles
                  find ${DEPLOY_PATH}/app/cache/dev -delete
                fi

                ;;
        [Uu]* ) said_yes "Updating vendors via Composer"

                php composer.phar self-update
                php composer.phar update

                # Cleaning the mess since it is a deploy folder
                if [ "$type" = "symfony2" ]; then
                  rm -fR ${DEPLOY_PATH}/web/bundles
                  find ${DEPLOY_PATH}/app/cache/dev -delete
                fi

                ;;
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
  if [ "$type" = "symfony2" ]; then

    cd ${WWW_PATH}

    ack "Upcoming changes to the schema"
    UPDATES=`php app/console doctrine:schema:update --dump-sql`

    clear
    echo ${UPDATES}
    clear
    
    if ! [ "$UPDATES" = "Nothing to update - your database is already in sync with the current entity metadata." ]; then

      yn=`ask "Do you wish to update the schema" "no"`
      case $yn in
          [Yy]* ) said_yes "Updating schema"
                  php app/console doctrine:schema:update --force # To be replaced with migrations later on ?
                  ;;
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
 
  fi

}

# Revert to a previous deployment folder
revert(){

  LAST_PATH=`ls $APP_BASE_PATH/${WWW_DIRECTORY}/$app | sed -n "s|rel\-$env\-[0-9]\{4\}\-[0-9]\{2\}\-[0-9]\{2\}\-\([0-9]*\).*|\1_&|gp" | sort -n | tail -2 | head -1 | cut -d_ -f2`
  LAST_PATH=${APP_BASE_PATH}'/'${WWW_DIRECTORY}'/'${app}/${LAST_PATH}
  
  if ! [ "$LAST_PATH" = "" ]; then

    indicate "Rollback path" ${LAST_PATH}

    yn=`ask "Are you sure you want to rollback (link)" "no"`
    case $yn in
        [Yy]* ) said_yes "Rollbacking"
                ln -sfvn ${LAST_PATH} ${WWW_LINK}
                notify_done ;;
         * ) said_no ;;
    esac

  else

    notify_error "No previous instance to rollback to, exiting."
    exit 1

  fi

}

# Link the full folder
link_full(){

  yn=`ask "Deployment is done — Do you wish to promote (link)" "no"`
  case $yn in
      [Yy]* ) said_yes "Linking"
              ln -sfvn ${WWW_PATH} ${WWW_LINK}
              notify_done ;;
       * ) said_no ;;
  esac

}

# Link a single file in a copied deployment folder
link_scalpel(){

  yn=`ask "Deployment is done — Do you wish to scalpel (link)" "no"`
  case $yn in
      [Yy]* ) said_yes "Linking"
              ln -sfvn ${SCALPEL_PATH} ${WWW_LINK}
              notify_done ;;
       * ) said_no ;;
  esac

}


# Update Changelog
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

}

# Install crontabs if necessary
install_crontabs(){

  if [ -f "${DEPLOY_PATH}/crontabs" ]; then

    yn=`ask "Do you want to reinstall cron jobs" "no"`
    case $yn in
        [Yy]* ) said_yes "Installing crontabs"

                AUTOMATED_KEYWORD_START="\#\[AUTOMATED\:START\:${app}\:${env}\]"
                AUTOMATED_KEYWORD_END="\#\[AUTOMATED\:END\:${app}\:${env}\]"

                CRONTABS="`cat "${DEPLOY_PATH}/crontabs"`"

                NEW_CRON=${AUTOMATED_KEYWORD_START//\\}$'\n'${CRONTABS}$'\n'${AUTOMATED_KEYWORD_END//\\}

                # Replace the [CONSOLE]
                if [ "$type" = "symfony2" ]; then
                  CONSOLE_PATH=${WWW_LINK}"/app/console"
                  NEW_CRON=${NEW_CRON//\[CONSOLE\]/$CONSOLE_PATH}
                fi

                # Replace the [ENV]
                if [ "$type" = "symfony2" ] && [ "$env" = "prod" ]; then
                  NEW_CRON=${NEW_CRON//\[ENV\]/prod}
                else
                  NEW_CRON=${NEW_CRON//\[ENV\]/dev}
                fi
             
                # Remove automated tasks
                crontab -l | sed "/${AUTOMATED_KEYWORD_START}/,/${AUTOMATED_KEYWORD_END}/d" | crontab -

                # Install new crontab
                (crontab -l ; echo "${NEW_CRON}")| crontab -

                # Outputs to check
                crontab -l

                ;;
         * ) said_no ;;
    esac

  fi

}

# Cleanup previous deployment directories
cleanup(){

  warn "All these paths will be permanently deleted"
  for f in $PREVIOUS_PATHS; do
    warn "${app} ($env)" $f
  done

  yn=`ask "Are you sure you want to cleanup" "no"`
  case $yn in
      [Yy]* ) said_yes "Cleaning up"
              for f in $PREVIOUS_PATHS
              do
                PATH_TO_DELETE=${APP_BASE_PATH}'/'${WWW_DIRECTORY}'/'${app}/$f
                if ! [ $PATH_TO_DELETE = $WWW_PATH ]; then
                  rm -fR $PATH_TO_DELETE
                  warn "Removed" $PATH_TO_DELETE
                fi
              done
              ;;
       * ) said_no ;;
  esac

}


# Restart Apache
restart_apache(){

  # Restart Apache
  res=`ask "Do you wish to restart Apache 2" "no"`
  case $res in
      [Yy]* ) said_yes "Restarting Apache"
              sudo /root/apachereload.sh
              ;;
      * ) said_no ;;
  esac

}


# Runs the application
run
