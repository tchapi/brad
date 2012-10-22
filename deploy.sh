# Deployement script for GitHub
#!/bin/bash

YELLOW='\033[01;33m'  # bold yellow
RED='\033[01;31m' # bold red
GREEN='\033[01;32m' # green
BLUE='\033[01;34m'  # blue
RESET='\033[00;00m' # normal white

APP_BASE_PATH='/home/tchap'

if [ $# -lt 2 ]
then
  echo ""
  echo -e ${GREEN}" Github / Git common promotion script "${RESET}
  echo " Usage: $0 (application) (env) [file1 file2 ...]"
  echo ""
  exit 1
fi  

# Checking application is good
app=$1

case $app in
  "tuneefy") app="tuneefy";;
  "panorame") app="panorame";;
  *) echo -e " # "${RED}"ERROR"${RESET}" : Bad application ($app)"
  echo ""
  exit 1;;
esac

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
WWW_PATH=${APP_BASE_PATH}'/www/'${app}'/release-'${env}'-'${date_today}"-"${timestamp}
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
  rsync -rlpt ${WWW_LINK}/* ${SCALPEL_PATH}/.
  
  echo ""
  echo -e " #"${GREEN}" Scalpeling "${RESET}${env}" environment to partial release"
  echo -e " #  "${YELLOW}"\_Files : "
  
  # Checking we have files and copying
  for x in "$@"; do 
    if [ -e ${DEPLOY_PATH}"/"$x ]
    then
      echo -e "    | "$x
      rsync -rlptv --inplace ${DEPLOY_PATH}/$x ${SCALPEL_PATH}/.
    fi
  done
  
  echo ""
  echo -e " #"${GREEN}" Linking "${RESET}

  # Link
  unlink ${WWW_LINK}
  ln -s ${SCALPEL_PATH} ${WWW_LINK}

  echo ""
  echo -e " # "${GREEN}"Done. "${RESET}
  echo ""

else

  echo -e " #"${GREEN}" Promoting "${RESET}${env}" environment to current release"

  # Copy all files to the destination folder
  mkdir ${WWW_PATH}
  rsync -rlpt ${DEPLOY_PATH}/. ${WWW_PATH}/. --exclude-from "${DEPLOY_PATH}/exclude.rsync"
  
  echo -e " #"${GREEN}" Linking "${RESET}

  # Link
  unlink ${WWW_LINK}
  ln -s ${WWW_PATH} ${WWW_LINK}

  echo -e " # "${GREEN}"Done. "${RESET}
  echo ""

fi


# Restart Apache
echo -e " #"${GREEN}" Restarting Apache ... "${RESET}
echo ""
sudo /root/apachereload.sh
echo ""

# Done
echo -e ${RESET}
echo -e " # "${GREEN}"Done. "${RESET}"Exiting."
echo ""