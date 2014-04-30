# Brad

Build, release and deploy
(_built for standalone, Symfony 2 and Silex projects, and Ghost blogs_)

- - -

Make easy atomic deployments from Github / Bitbucket, or any remote Git server.

The package consists of one script : `brad`, and a configuration file : `brad.conf`.
It is based on the bootshtrap shell micro-library (see https://github.com/tchapi/bootshtrap).

> NB : You will have to copy `brad.conf.example` to `brad.conf` for the scripts to work. You should as well make sure that `brad` is executable, or run `chmod +x brad` in case

## Initial configuration

Before running anything, you have to configure your `APP_BASE_PATH` in the `brad.conf` file. Just define the `APP_BASE_PATH` in this file like this :

```bash
APP_BASE_PATH='/var'
```

This will be the root directory where the deployments will take place. This directory should not be served directly by your webserver, since the resulting directory structure will be :

```
APP_BASE_PATH
  |-- deploy
  `-- release
```

`release` and `deploy` are directories that should not be served by your webserver.

If your applications are to be served from the same server, the path will also have :

```
APP_BASE_PATH
  `-- wwww
```

Otherwise, your remote server (for each application) will have the following structure (see configuration) :

```
remote["app_1", "path"]
  `-- www
```

_NB : Be sure to have **no** trailing slash at the end of your paths_

> NB : if you run brad on a computer that does not have bash 4 required by `bootshtrap` or gnu_getopt, you can amend `bootshtrap.config` accordingly. See the bootshtrap documentation.

## Configurating for deployement

Before a project can be initialized, you have to add it in the `brad.conf` configuration file :

```bash
projects["app_1"]="standalone"
projects["my_symfony2_app"]="symfony2"
```          

  - `standalone` references a standard project.
  - `symfony2` (or `silex`) explicitely references a project that is based on the [Symfony2](http://symfony.com) (or Silex) framework. 
  - `ghost` references a project that uses node.js and the [ghost](ghost.org) blogging framework.

This is used when initing and deploying to accomplish tasks such as cache warmup, schema update, etc ...

If a project is to be deployed on a remote target, you should add the relevant information for connecting to the server :

```bash
remote["app_1", "host"]="myserver.com"
remote["app_1", "port"]="22"
remote["app_1", "user"]="john"
remote["app_1", "path"]="/home/webuser/sites"
```                  

> NB : It's easier if the target remote server has the key of the deployment server, to avoid password prompting.

## Cloning and initing a project

Once conf'ed, you can init a project with :

```bash
$ ./brad --init git_repository my_new_app 
```

.. where `my_new_app` will be the name of your application (the directories will be created ad hoc) and `git_repository` is the url of the related git repository.

The script will init the following deployment directory structure :

```
APP_BASE_PATH
  |-- deploy
  |   `-- app_1
  |       |-- beta
  |       |   `-- // all the stuff of app_1 from branch 'staging' of the repo
  |       `-- prod
  |           `-- // all the stuff of app_1 from branch 'live' of the repo
  `-- release
      `-- app_1
          `-- // all the release directories
```

And the following front structure (on the same erver or on a remote server) :

```
APP_BASE_PATH __or__ remote["app_1", "path"]
  |
  `-- www
      `-- app_1
          |-- uploads
          |-- var
          |   `-- sessions 
          |-- beta
              `--  // all the deployed stuff from app_1/beta
          `-- prod
              `--  // all the deployed stuff from app_1/prod
```

Your git repository **must** have at least a `live` branch that will reflect the `prod` environment. A `staging` branch is optional and would reflect the `beta` environment.

Upon completion of the script, one or two environments are created : prod and beta (only if the `staging` branch exists).

##### Environment : beta

This environment is going to pull the `staging` branch of the github repository

##### Environment : prod

This environment is going to pull the `live` branch of the github repository

#### Other directories

In the case of a Symfony 2 project (_automatically detected with the existence of a `composer.phar` file_), two folders are created as well :

  - `uploads` (_to store the user uploads_)
  - `var/sessions` (_to store the user sessions — this allows to separate the cache from the sessions and deploy without logging out all the users if configured in the Symfony 2 application_)

Links (symbolic) to these folders are created respectively in `web/` and in `app/` of your Symfony2 application.

In the case of a Ghost blog, two folders are created as well :

  - `data` (_to store the db - this allows to persist the sqlite db accross deployments_)
  - `images` (_to store the user uploaded media — this allows to persist the uploaded images accross deployments_)

Links (symbolic) to these folders are created in `content/` in your ghost blog.

## Deploying a project

Deploying an application is easy :

```bash
$ ./brad my_app environment
```

... where `my_app` (the first argument) is the name of the app previously initialized, and where environnement (second argument) can be one of :

  - beta (staging area, if available)
  - prod (live environment)

## Rollbacking to a previous deployment

If you haven't deleted the previous deployment directories, it is possible to rollback to a previous instance of your application. This only applies to the application itself and not to the database schema or sessions / uploads, for instance.

```bash
$ ./brad --rollback my_app environment
```
or 
```bash
$ ./brad -r my_app environment
```

> NB : As per the _getopt_ flavor, the options can be put anywhere in the command (after or before arguments).

This will link back the `www/prod` or `www/beta` folder to the previous instance of the application, if found.

## Cleaning up previous deployment folders when deploying

When deploying often, you will probably clutter your `www`folder with previous unnecessary instances. You can perform a deployment with a final cleanup of the old ones with this simple command :

```bash
$ ./brad --cleanup my_app environment
```
or

```bash
$ ./brad -c my_app environment
```

> NB : As per the _getopt_ flavor, the options can be put anywhere in the command (after or before arguments).

This will deploy your application normally, AND `rm -fR` all the non-linked deployment folders in `www` corresponding to the environment you're deploying.

> NB : It is not possible to cleanup and rollback at the same time, obviously

## Deploying easily from a remote client

In order to facilitate deployment from a remote client (your computer for instance), I recommend adding the following function to your `~/.profile` _(change the server url and script path accordingly)_ :

```bash
function deploy(){

  ssh -t -t -t my.server.com -p 22  "/var/deploy/_script/brad $*"

}
```
