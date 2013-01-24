# Deployement script for GitHub
#!/bin/bash

# Common color helpers
YELLOW='\033[01;33m'  # bold yellow
RED='\033[01;31m' # bold red
GREEN='\033[01;32m' # green
BLUE='\033[01;34m'  # blue
RESET='\033[00;00m' # normal white

# Check major bash version
bash_version=${BASH_VERSION%%[^0-9]*}
min_bash_version=4

if [ "$bash_version" -lt "$min_bash_version" ]
then
  echo ""
  echo "Oh, ... bugger. This script requires bash > "${min_bash_version}"."
  echo -e ${RED}"Your bash version is "${RESET}${BASH_VERSION}
  echo ""
  exit 1;
fi

# Only in bash > 4.0, check `bash -version`for help
declare -A projects

# Load configuration file
CONFIG_FILE="$(dirname $0)/deploy.conf"

if [[ -f $CONFIG_FILE ]]; then
        . $CONFIG_FILE
else

  echo ""
  echo -e ${GREEN}" Github / Git common promotion script "${RESET}
  echo -e ${RED}" Missing deploy.conf configuration file!"${RESET}"."
  echo ""
  exit 1

fi

# Do we have enough arguments ?
if [ $# -lt 2 ]
then
  echo ""
  echo -e ${GREEN}" Github / Git common promotion script "${RESET}
  echo " Usage: $0 (application) (env) [file1 file2 ...]"
  echo ""
  exit 1
fi  

# Checking that the project exists
app=$1

project_found=false
# What project, sir ?
for project_slug in "${!projects[@]}"; do
  if [ "$app" = "$project_slug" ]
  then
    type=${command}${projects["$project_slug"]}
    project_found=true
  fi
done

# Naaaaay
if ! $project_found
then
  echo -e " # "${RED}"ERROR"${RESET}" : Bad action name ($action)"
  echo ""
  exit 1
fi

# Checking environment is good
env=$2

case $env in
  "prod") env="prod";;
  "beta") env="beta";;
  "poc")  env="poc";;
  *) echo -e " # "${RED}"ERROR"${RESET}" : Bad environment ($env)"
  echo ""
  exit 1;;
esac

date_today=`date '+%Y-%m-%d'`
timestamp=`date '+%s'`
DEPLOY_PATH=${APP_BASE_PATH}'/deploy/'${app}'/'${env}
WWW_PATH=${APP_BASE_PATH}'/www/'${app}'/rel-'${env}'-'${date_today}"-"${timestamp}
WWW_LINK=${APP_BASE_PATH}'/www/'${app}'/'${env}

ADMIN_PATH=${DEPLOY_PATH}'/admin'

echo -e ""${RESET}
echo " # ------------------------- #"
echo " # "${app}" promotion script #"
echo " # ------------------------- #"
echo ""

# Check user
echo -e " #"${GREEN}" Current user is : "${RESET}$(whoami)
echo ""

echo -e " #"${BLUE}" Deployment path : "${RESET}${DEPLOY_PATH}
echo -e " #"${BLUE}" Release www path : "${RESET}${WWW_PATH}
echo -e " #"${BLUE}" Live www path : "${RESET}${WWW_LINK}

# Go into the deploy directory
echo -e " #"${YELLOW}" Changing directory "${RESET}" to "${DEPLOY_PATH} 
echo ""
cd ${DEPLOY_PATH}

# Git all the way
echo -e " #"${GREEN}" Checking out live branch from origin"${RESET}
echo ""
echo "   | "`git reset --hard HEAD`
echo "   | "`git pull origin`
echo "   | "`git status`
echo ""

revision=`git log -n 1 --pretty="format:%h %ci"`
echo -e " #"${BLUE}" Repository updated to revision : "${RESET}${revision}
echo ""

revision_safe=`git log -n 1 --pretty="format:%h"`
WWW_PATH=${WWW_PATH}"-"${revision_safe}

if [ "$type" == "standalone" ]
then

  # Building minified JS if we have a minify script in admin/
  if [ -e ${ADMIN_PATH}"/minify.php" ]
  then
    echo -e " # "${RED}"Do you wish to build minified Javascript"${RESET}" [no] ?\c"
    read yn
    case $yn in
        [Yy]* ) echo -e "   | "$(whoami)" said "${GREEN}"Yes"${RESET}"."${GREEN}" Building"${RESET}" minified JS :"
                echo -e "   |  \__ "${BLUE}${DEPLOY_PATH}"/js/min/"${app}".min.js"${RESET}
                cd ${ADMIN_PATH}
                php minify.php > ${DEPLOY_PATH}/js/min/${app}.min.js
                echo ""
                echo -e " # "${GREEN}"Done. "${RESET}
                echo "" ;;
        * ) echo -e "   | "$(whoami)" said "${RED}"No. "${RESET}
            echo "" ;;
    esac

  fi

fi

#
# Do we promote live the whole branch or just files ?
#
if [ $# -ge 3 ]
then

  SCALPEL_PATH=${WWW_PATH}"_scalpel"

  echo -e " #"${GREEN}" Duplicating"${RESET}" actual "${env}" environment into "${SCALPEL_PATH}
  echo ""
  # Copy all files from current release to a new release
  mkdir ${SCALPEL_PATH}
  rsync -rlpt ${WWW_LINK}/. ${SCALPEL_PATH}/.
  
  echo ""
  echo -e " #"${GREEN}" Scalpeling "${RESET}${env}" environment to partial release"
  echo -e " #  "${YELLOW}"\_Files : "
  
  # Checking we have files and copying
  for x in "$@"; do 
    if [ -e ${DEPLOY_PATH}"/"$x ]
    then
      echo -e "    | "$x
      rsync -rlptv --inplace ${DEPLOY_PATH}/$x ${SCALPEL_PATH}/$x
    fi
  done
  
  echo ""
  echo -e " #"${GREEN}" Linking "${RESET}

  # Link
  ln -sfvn ${SCALPEL_PATH} ${WWW_LINK}

  echo ""
  echo -e " # "${GREEN}"Done. "${RESET}
  echo ""

else

  echo -e " #"${GREEN}" Promoting "${RESET}${env}" environment to current release"

  # Copy all files to the destination folder
  mkdir ${WWW_PATH}
  rsync -rlpt ${DEPLOY_PATH}/. ${WWW_PATH}/. --exclude-from "${DEPLOY_PATH}/exclude.rsync"
  
  if [ "$type" == "symfony2" ]
  then

    cd ${WWW_PATH}

    # Symfony2
    echo ""
    echo -e " # "${RED}"Do you wish to update vendors"${RESET}" [no] ?\c"
    read yn
    case $yn in
        [Yy]* ) echo -e "   | "$(whoami)" said "${GREEN}"Yes"${RESET}"."${GREEN}" Updating"${RESET}" vendors via Composer :"
                echo ""
                php composer.phar self-update
                php composer.phar update
                echo ""
                echo -e " # "${GREEN}"Done. "${RESET}
                echo "" ;;
         * ) echo -e "   | "$(whoami)" said "${RED}"No. "${RESET} 
            echo "" ;;
    esac

    echo -e " # "${GREEN}"Doing Symfony 2 Stuff"${RESET}" :"
    echo ""

    php app/console doctrine:schema:update --force # To be replaced with migrations later on 
    php app/console cache:clear
    php app/console cache:clear --env=prod
    php app/console assets:install web --symlink
    php app/console assetic:dump --env=prod --no-debug
    chmod -R 777 app/cache app/logs
    echo ""
 
  fi

  echo -e " #"${GREEN}" Linking "${RESET}
  echo ""

  # Link
  ln -sfvn ${WWW_PATH} ${WWW_LINK}

  echo ""
  echo -e " # "${GREEN}"Done. "${RESET}
  echo ""

fi

# Update CHANGELOG.txt
CHANGELOG_NAME='CHANGELOG.txt'
if [ "$type" == "symfony2" ]
then
CHANGELOG_PATH=${WWW_PATH}'/web/'${CHANGELOG_NAME}
elif [ "$type" == "standalone" ]
then
CHANGELOG_PATH=${WWW_PATH}'/'${CHANGELOG_NAME}
fi

cd ${DEPLOY_PATH}
echo "# CHANGELOG" > ${CHANGELOG_PATH}
current_date=`git log -1 --format="%ad"`
echo "# Last update : ${current_date}" > ${CHANGELOG_PATH}
change_log=`git log --no-merges --date-order --date=short | \
    sed -e '/^commit.*$/d' | \
    awk '/^Author/ {sub(/\\$/,""); getline t; print $0 t; next}; 1' | \
    sed -e 's/^Author: //g' | \
    sed -e 's/>Date:   \([0-9]*-[0-9]*-[0-9]*\)/>\t\1/g' | \
    sed -e 's/^\(.*\) \(\)\t\(.*\)/\3    \1    \2/g' >> ${CHANGELOG_PATH}`

# Restart Apache
echo -e " # "${RED}"Do you wish to restart Apache 2"${RESET}" [no] ?\c"
read yn
case $yn in
    [Yy]* ) echo -e "   | "$(whoami)" said "${GREEN}"Yes"${RESET}"."${GREEN}" Restarting Apache"${RESET}":"
            echo ""
            sudo /root/apachereload.sh
            echo "" ;;
    * ) echo -e "   | "$(whoami)" said "${RED}"No. "${RESET}
        echo "" ;;
esac

# Done
echo -e ${RESET}
echo -e " # "${GREEN}"Done. "${RESET}"Exiting."
echo ""

