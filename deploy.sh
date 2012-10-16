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
  echo " Usage: $0 (application) (env) [file1 file2 ...]";
  echo ""
  exit 1;
fi  

# Checking application is good
app=$1;

case $app in
  "tuneefy") app="tuneefy";;
  "panorame") app="panorame";;
  *) echo -e " # "${RED}"ERROR"${RESET}" : Bad application ($app)"
  echo ""
  exit 1;;
esac

# Checking environment is good
env=$2;

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
DEPLOY_PATH=${APP_BASE_PATH}'/deploy/'${app}
WWW_PATH=${APP_BASE_PATH}'/www/'${app}'/release-'${date_today}"-"${timestamp}
WWW_LINK=${APP_BASE_PATH}'/www/'${app}'/'${env}

echo -e ""${RESET}
echo " # ------------------------- #"
echo " # "${app}" promotion script #"
echo " # ------------------------- #"
echo ""

echo -e " #"${BLUE}" Deployment path : "${RESET}${DEPLOY_PATH}
echo -e " #"${BLUE}" Release www path : "${RESET}${WWW_PATH}
echo -e " #"${BLUE}" Live www path : "${RESET}${WWW_LINK}
echo ""

# Check user
echo -e " #"${GREEN}" Current user is : "${RESET}$(whoami)
echo ""

# Go into the deploy directory
echo -e " #"${GREEN}" Changing directory "${RESET}" to "${DEPLOY_PATH} 
echo ""
cd ${DEPLOY_PATH}

# Git all the way
echo -e " #"${GREEN}" Checking out live branch from origin"${RESET}
echo ""
git checkout live
git reset --hard HEAD
git pull origin
git status
echo ""

#
# Do we promote live the whole branch or just files ?
#
if [ $# -ge 3 ]
then

  echo -e " #"${GREEN}" Promoting "${RESET}${env}" environment partially to current release"
  echo -e " #  "${YELLOW}"\_Files : "
  
  # Checking we have files and copying
  for x in "$@"; do 
    if [ -e ${DEPLOY_PATH}"/"$x ]
    then
    echo -e " #   - "$x
    cp -f ${DEPLOY_PATH}/$x ${WWW_LINK}/.;
    fi
  done

  echo -e ${RESET}
  echo -e " # "${GREEN}"Done. "${RESET}
  echo ""

else

  echo -e " #"${GREEN}" Promoting "${RESET}${env}" environment to current release"
  echo ""
  # Copy all files to the destination folder
  mkdir ${WWW_PATH}
  rsync -r ${DEPLOY_PATH}/* ${WWW_PATH}/. --exclude-from "${DEPLOY_PATH}/exclude.rsync"
  
  echo -e " #"${GREEN}" Linking "${RESET}
  echo ""
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