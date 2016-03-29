var express = require('express');
var app = express();

var rangeCheck = require('range_check');

var sys = require('util')
var exec = require('child_process').exec;


// Extract projects from the config file
var fs = require('fs')

var result; var projects = [];
var data = fs.readFileSync("../brad.conf", 'utf8');

var re = /projects\[\"([a-zA-Z\_]*)\"\](.*)/gi;
 
while ((result = re.exec(data)) !== null) {
    projects.push(result[1]);
    if (result.index === re.lastIndex) {
        re.lastIndex++;
    }
}

app.get('/hooks', function (req, res) {
  res.send(projects);
});

app.post('/hook/:name/:env', function (req, res) {
  // A trigger has been made, first authenticate the sender (Github, bitbucket) :
  var ip = req.headers['x-forwarded-for'] || req.connection.remoteAddress;

  // Bitbucket
  if (ip == "::1" || ip == "127.0.0.1"
    || 
    // Bitbucket
    rangeCheck.inRange(ip, ['131.103.20.160/27', '165.254.145.0/26', '104.192.143.0/24']) 
    ||
    // Github
    rangeCheck.inRange(ip, ['192.30.252.0/22'])) {

    // Then act accordingly 
    var name = req.params.name;
    var env = req.params.env;

    if ((env == "prod" || env == "beta") && projects.indexOf(name) != -1) {
      console.log("Deploying for " + name + " to env " + env);

      // http://nodejs.org/api.html#_child_processes
      var child = exec("../brad -y " + name + " " + env, function (error, stdout, stderr) {
        
        if (error !== null) {
          console.log('exec error: ' + error);
          console.log('stderr: ' + stderr);
          res.sendStatus(404);
        } else {
          console.log('stdout: ' + stdout);
          res.sendStatus(200);
        }
      });

    } else {
      console.log("Project or env not found : " + name + " / " + env);
      res.sendStatus(404);
    }

  } else {
    res.sendStatus(404);
  }
});

app.listen(4978, function () {
  console.log('Brad hook — listening on port 4978');
});