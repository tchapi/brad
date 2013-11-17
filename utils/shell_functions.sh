SERVER='myserver.com'
PORT=22
SCRIPT_PATH='~/brad'

function brad(){

  ssh -t -t -t ${SERVER} -p ${PORT}  "${SCRIPT_PATH} $*"

}

# On the remote server directly :

function brad(){
  ~/brad/brad "$@"
}
