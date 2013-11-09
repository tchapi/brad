#!/bin/bash
# Deployement script for GitHub / Bitbucket / Any remote Git server

# Use BootSHtrap
# __DEBUG=1 # Sets the debug mode, which outputs logs to standard output
config="`dirname $0`"/bootshtrap.config
source "`dirname $0`"/bootshtrap/bootshtrap/autoload.sh # Autoloads the whole stuff

# Associative arrays for projects in config
unset projects
declare -A projects
unset remote
declare -A remote

# Globals
DEPLOY_DIRECTORY='deploy'
WWW_DIRECTORY='www'

# Live branch and directory
LIVE_BRANCH='live'
LIVE_DIRECTORY='prod'

# Staging branch and directory
STAGING_BRANCH='staging'
STAGING_DIRECTORY='beta'

# Init flags
CLEANUP=0
ROLLBACK=0
INIT=0

# Main entry point
main(){

  load_config_file "$(dirname $0)/deploy.conf"

  check_arguments "${@}"

  date_today=`date '+%Y-%m-%d'`
  timestamp=`date '+%s'`
  DEPLOY_PATH=${APP_BASE_PATH}'/'${DEPLOY_DIRECTORY}'/'${app}'/'${env}
  WWW_PATH=${APP_BASE_PATH}'/'${WWW_DIRECTORY}'/'${app}'/rel-'${env}'-'${date_today}"-"${timestamp}
  REMOTE_WWW_PATH=${REMOTE_APP_BASE_PATH}'/'${WWW_DIRECTORY}'/'${app}'/rel-'${env}'-'${date_today}"-"${timestamp}
  WWW_LINK=${REMOTE_APP_BASE_PATH}'/'${WWW_DIRECTORY}'/'${app}'/'${env}

  ADMIN_PATH=${DEPLOY_PATH}'/admin'

  if [ ! "$INIT" = 1 ]; then
    PREVIOUS_PATHS=`$ON_TARGET_DO ls ${REMOTE_APP_BASE_PATH}/${WWW_DIRECTORY}/${app} | sed -n "s|rel\-${env}\-[0-9]\{4\}\-[0-9]\{2\}\-[0-9]\{2\}\-\([0-9]*\).*|\1_&|gp" | sort -n | cut -d_ -f2`
  fi

  # Check user
  ack "Current user is" $(whoami)

  # Application name and type
  ack "This application ${app} is" "$type"

  indicate "Deployment path" ${DEPLOY_PATH}
  if [ ! "$INIT" = 1 ]; then
    indicate "Release www path" ${WWW_PATH}
    indicate "Remote www path" ${REMOTE_WWW_PATH}
  fi
  indicate "Deployment target" ${remote}
  indicate "Live www path" ${WWW_LINK}

  # Init or Deploy ?
  if [ "$INIT" = 1 ]; then
    # ---- INIT ----

    header "Initializing deployment structure"

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

    # Go into the deploy directory
    cd ${DEPLOY_PATH}

    if [ $# -ge 3 ]; then

      git_pull
      update_changelog 

      if [ "$type" = "standalone" ] && ! [ "$ROLLBACK" = 1 ] ; then build_js; fi

      scalpel

      header "Promoting ${env} environment now"
      link_scalpel

    else

      if [ "$ROLLBACK" = 1 ]; then
        revert
      else

        git_pull
        update_changelog 

        if [ "$type" = "standalone" ] && ! [ "$ROLLBACK" = 1 ] ; then build_js; fi
  
        header "Preparing ${env} environment for release"
        deploy

        header "Promoting ${env} environment now"
        upgrade_db
        link_full

        if [ "$CLEANUP" = 1 ]; then
          cleanup
        fi

      fi

    fi

    install_crontabs # remote
    restart_apache # remote

    # ---- END : DEPLOY ----
  fi
  
  notify_done

}

# Check that app, env and other arguments are ok
check_arguments(){

  if [ $# -ge 3 ] && [ "$ROLLBACK" = 1 ]; then
    notify_error "Cannot rollback single files"
    usage
    error_exit
  fi
  
  # We need an app and an environment at least
  app="${1-}"

  # Checking that the project exists
  project_found=false
  # What project, sir ?
  for project_slug in "${!projects[@]}"; do
    if [ "$app" = "$project_slug" ]; then
      type=${projects["$project_slug"]}
      if [ ${remote["$project_slug", "host"]+1} ]; then
        host=${remote["$project_slug", "host"]}
        port=${remote["$project_slug", "port"]}
        path=${remote["$project_slug", "path"]}
        user=${remote["$project_slug", "user"]}
      fi
      project_found=true
    fi
  done

  # Naaaaay
  if ! $project_found; then
    notify_error "Bad application name ($app)"
    error_exit
  fi

  indicate "Deploying" ${app}

  env="${2-}"
  # Checking environment is good
  case $env in
    "prod") env="$LIVE_DIRECTORY";;
    "beta") env="$STAGING_DIRECTORY";;
    *) if ! [ "$INIT" = 1 ]; then
        notify_error "Bad environment ($env)"
        error_exit
       fi;;
  esac

  if [ ! "${host-}" = "" ]; then
    ON_TARGET_DO="ssh -t -t -t ${user}@${host} -p ${port}"
    remote="${user}@${host}:${port}"
    REMOTE_APP_BASE_PATH=${path}
  else
    remote="`whoami`@localhost"
    ON_TARGET_DO=""
    REMOTE_APP_BASE_PATH=${APP_BASE_PATH}
  fi

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

  DIR_PATH=`readlink -f "${APP_BASE_PATH}/${DEPLOY_DIRECTORY}/${app}"` # Get rid of symlinks and get abs path
  if [[ -d "${DIR_PATH}" ]] ; then # now we're testing
    notify_error "This application already has a deployment folder ($app). Delete the whole folder and retry."
    error_exit
  fi

  # We create a dir for the app if it doesn't already exist
  mkdir ${APP_BASE_PATH}/${DEPLOY_DIRECTORY}/$app

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

  if [ "$type" = "symfony2" ]; then
    $ON_TARGET_DO mkdir -p ${REMOTE_APP_BASE_PATH}/${WWW_DIRECTORY}/${app}/var  
    $ON_TARGET_DO chmod 775 ${REMOTE_APP_BASE_PATH}/${WWW_DIRECTORY}/${app}/var
    $ON_TARGET_DO mkdir -p ${REMOTE_APP_BASE_PATH}/${WWW_DIRECTORY}/${app}/uploads
    $ON_TARGET_DO chmod 775 ${REMOTE_APP_BASE_PATH}/${WWW_DIRECTORY}/${app}/uploads
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

        # var/sessions for sessions storage
        cd ../app
        ln -s ../../var/${STAGING_DIRECTORY} var

      fi

    fi

    # Rights
    if [ "$type" = "symfony2" ]; then
     
      $ON_TARGET_DO mkdir -p ${REMOTE_APP_BASE_PATH}/${WWW_DIRECTORY}/${app}/var/${STAGING_DIRECTORY}/sessions
      $ON_TARGET_DO chmod 775 ${REMOTE_APP_BASE_PATH}/${WWW_DIRECTORY}/${app}/var/${STAGING_DIRECTORY}/sessions

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

      # var/sessions for sessions storage
      cd app
      ln -s ../../var/prod var

    fi

  fi

  # Rights
  if [ "$type" = "symfony2" ]; then
    
    $ON_TARGET_DO mkdir -p ${REMOTE_APP_BASE_PATH}/${WWW_DIRECTORY}/${app}/var/${LIVE_DIRECTORY}/sessions
    $ON_TARGET_DO chmod 775 ${REMOTE_APP_BASE_PATH}/${WWW_DIRECTORY}/${app}/var/${LIVE_DIRECTORY}/sessions

  fi

  # Summary

  ack "Created environnements :"
  indicate "Remote repository" ${GIT_URL}

  indicate "Staging Deploy path" ${APP_BASE_PATH}/${DEPLOY_DIRECTORY}/${app}/${STAGING_DIRECTORY}
  indicate " --> tracking branch" ${STAGING_BRANCH}

  indicate "Live Deploy path" ${APP_BASE_PATH}/${DEPLOY_DIRECTORY}/${app}/${LIVE_DIRECTORY}
  indicate " --> tracking branch " ${LIVE_BRANCH}

  indicate "Web path" ${host}${REMOTE_APP_BASE_PATH}/${WWW_DIRECTORY}/${app}
  clear

  # Done
  notify_done
  exit 0

}

# Fetches and merge the changes found on the remote branch of the given folder
git_pull(){

  header "Pulling changes"

  # Git all the way
  ack "Checking out remote branch from origin"
  clear
  echo "   | "`git reset --hard HEAD`
  echo "   | "`git pull origin`
  echo "   | "`git status`
  clear

  revision=`git log -n 1 --pretty="format:%h %ci"`
  indicate "Deployment folder updated to revision" ${revision}

  revision_safe=`git log -n 1 --pretty="format:%h"`
  WWW_PATH=${WWW_PATH}"-"${revision_safe}

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
  clear

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

    # Dump assetic assets
    php app/console assets:install web --symlink
    php app/console assetic:dump --env=prod --no-debug

    # Warming up caches
    php app/console cache:warmup
    php app/console cache:warmup --env=prod

    # Ensure that cache, logs are writable
    chmod -R 777 app/cache app/logs # web/uploads
 
  fi

  clear
  ack "Deployment is done !"

}

upgrade_db() {

  # Symfony 2 Stuff
  if [ "$type" = "symfony2" ]; then

    clear
    ack "Upcoming changes to the schema"
    UPDATES=`$ON_TARGET_DO php ${REMOTE_WWW_PATH}/app/console doctrine:schema:update --dump-sql`

    clear
    echo ${UPDATES}
    clear
    
    if ! [ "$UPDATES" = "Nothing to update - your database is already in sync with the current entity metadata." ]; then

      yn=`ask "Do you wish to update the schema" "no"`
      case $yn in
          [Yy]* ) said_yes "Updating schema"
                  $ON_TARGET_DO php ${REMOTE_WWW_PATH}/app/console doctrine:schema:update --force # To be replaced with migrations later on ?
                  ;;
          * ) said_no ;;
      esac
    fi

  fi

  clear
  ack "Database updated !"

}

# Revert to a previous deployment folder
revert(){

  LAST_PATH=`$ON_TARGET_DO ls ${REMOTE_APP_BASE_PATH}/${WWW_DIRECTORY}/$app | sed -n "s|rel\-$env\-[0-9]\{4\}\-[0-9]\{2\}\-[0-9]\{2\}\-\([0-9]*\).*|\1_&|gp" | sort -n | tail -2 | head -1 | cut -d_ -f2`
  LAST_PATH=${REMOTE_APP_BASE_PATH}'/'${WWW_DIRECTORY}'/'${app}/${LAST_PATH}
  
  if ! [ "$LAST_PATH" = "" ]; then

    indicate "Rollback path" ${LAST_PATH}

    yn=`ask "Are you sure you want to rollback (link)" "no"`
    case $yn in
        [Yy]* ) said_yes "Rollbacking"
                $ON_TARGET_DO ln -sfvn ${LAST_PATH} ${WWW_LINK}
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

  yn=`ask "Do you wish to promote (link)" "no"`
  case $yn in
      [Yy]* ) said_yes "Linking"
              # Local
              ln -sfvn ${WWW_PATH} ${WWW_LINK}
              # Remote
              if [ ! "$remote" = "" ]; then
                rsync -av --del --stats -e 'ssh -p ${port}' ${WWW_PATH} ${user}@m${server}:${REMOTE_WWW_PATH}
                $ON_TARGET_DO ln -sfvn ${REMOTE_WWW_PATH} ${WWW_LINK}
              fi
              notify_done ;;
       * ) said_no ;;
  esac

}

# Link a single file in a copied deployment folder
link_scalpel(){

  yn=`ask "Do you wish to scalpel (link)" "no"`
  case $yn in
      [Yy]* ) said_yes "Linking"
              ln -sfvn ${SCALPEL_PATH} ${WWW_LINK}
              notify_done ;;
       * ) said_no ;;
  esac

}


# Install crontabs if necessary
install_crontabs(){

  if [ -f "${DEPLOY_PATH}/crontabs" ]; then

    yn=`ask "Do you want to reinstall cron jobs" "no"`
    case $yn in
        [Yy]* ) said_yes "Installing crontabs"

                AUTOMATED_KEYWORD_START="\#\[AUTOMATED\:START\:${app}\:${env}\]"
                AUTOMATED_KEYWORD_END="\#\[AUTOMATED\:END\:${app}\:${env}\]"

                CRONTABS="`$ON_TARGET_DO cat "${DEPLOY_PATH}/crontabs"`"

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
                $ON_TARGET_DO crontab -l | sed "/${AUTOMATED_KEYWORD_START}/,/${AUTOMATED_KEYWORD_END}/d" | crontab -

                # Install new crontab
                $ON_TARGET_DO (crontab -l ; echo "${NEW_CRON}")| crontab -

                # Outputs to check
                $ON_TARGET_DO crontab -l
                clear
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
                PATH_TO_DELETE=${REMOTE_APP_BASE_PATH}'/'${WWW_DIRECTORY}'/'${app}/$f
                if ! [ $PATH_TO_DELETE = $REMOTE_WWW_PATH ]; then
                  $ON_TARGET_DO rm -fR $PATH_TO_DELETE
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
              $ON_TARGET_DO sudo /root/apachereload.sh
              ;;
      * ) said_no ;;
  esac

}


# Runs the application
run
