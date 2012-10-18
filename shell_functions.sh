SERVER='myserver.com'
PORT=22
SCRIPT_PATH='~/deploy.sh'

function deploy(){

  ssh -t -t -t ${SERVER} -p ${PORT}  "${SCRIPT_PATH} $*"

}
