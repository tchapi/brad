# Deployment scripts from a remote Git server
- - -

Make easy atomic deployments from Github / Bitbucket, or any remote Git server

The package consists of two scripts : `init.sh` and `deploy.sh`, and a configuration file : `deploy.conf`.

> NB : You will have to copy `deploy.conf.example` to `deploy.conf` for the scripts to work. You should as well make sure that `init.sh` and `deploy.sh` are executable, or run `chmod +x init.sh deploy.sh` in case

## Initial configuration

Before running anything, you have to configure your `APP_BASE_PATH` in the `deploy.conf` file. Just define the `APP_BASE_PATH` in this file like this :

```bash
APP_BASE_PATH='/var'
```

This will be the root directory where the deployments will take place. This directory should not be served directly by your webserver, since the resulting directory structure will be :

```
APP_BASE_PATH
  |-- deploy
  `-- www
```

`www` should be your webserver root and `deploy` should not be served.

_NB : Be sure to have no trailing slash at the end of your path_

## Cloning and initing a project

The script `init.sh` allows you to create a new project :

```bash
$ ./init.sh my_new_app git_repository
```

.. where `my_new_app` will be the name of your application directory (created ad hoc) and `git_repository` is the url of the related git repository.

The script will init the following directory structure :

```
APP_BASE_PATH
  |-- deploy
  |   `-- app_1
  |       |-- beta
  |       |   `-- // all the stuff of app_1 from branch 'staging' of the repo
  |       `-- prod
  |           `-- // all the stuff of app_1 from branch 'live' of the repo
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

Your git repository **must** have two branches : `live` and `staging`.

Upon completion of the script, two environments are created : beta and prod.

#### Environment : beta

This environment is going to pull the `staging` branch of the github repository

#### Environment : prod

This environment is going to pull the `live` branch of the github repository

#### Other directories

In the case of a Symfony 2 project (_automatically detected with the existence of a `composer.phar` file_), two folders are created as well :

  - `uploads` (_to store the user uploads_)
  - `var/sessions` (_to store the user sessions — this allows to separate the cache from the sessions and deploy without logging out all the users if configured in the Symfony 2 application_)

Links (symbolic) to these folders are created respectively in `web/` and in `app/` of your Symfony2 application.

## Configurating for deployement

Once a project has been initialized, you have to add it in the `deploy.conf` configuration file :

```bash
projects["app_1"]="standalone"
projects["my_symfony2_app"]="symfony2"
```                            

`standalone` references a standard project, whereas `symfony2` explicitely references a project that is based on the Symfony2 framework. This is used when deploying to accomplish tasks such as cache warmup, schema update, etc ...

## Deploying a project

Deploying an application is easy :

```bash
$ ./deploy.sh my_app environment
```

... where `my_app` (the first argument) is the name of the app previously initialized, and where environnement (second argument) can be one of :

  - beta (staging area)
  - prod (live environment)

## Deploying a single file ("scalpel")

You can deploy a single file  :

```bash
$ ./deploy.sh my_app environment [file1 file2 ... ]
```
In this case, the previous production or staging release directory will be copied to a new release directory, and the file(s) will be replaced _in situ_ in this new directory.

## Rollbacking to a previous deployement

If you haven't deleted the previous deployment directories, it is possible to rollback to a previous instance of your application. This only applies to the application itself and not to the database schema or sessions / uploads, for instance.

```bash
$ ./deploy.sh --rollback my_app environment
```
or 
```bash
$ ./deploy.sh -r my_app environment
```

> NB : As per the _getopt_ flavor, the options can be put anywhere in the command (after or before arguments).

This will link back the `www/prod` or `www/beta` folder to the previous instance of the application, if found.

> NB : It is not possible to rollback to a scalpel instance, and other supplementary arguments such as files are not valid.

## Cleaning up previous deployment folders when deploying

When deploying often, you will probably clutter your `www`folder with previous unnecessary instances. You can perform a deployment with a final cleanup of the old ones with this simple command :

```bash
$ ./deploy.sh --cleanup my_app environment
```
or 
```bash
$ ./deploy.sh -c my_app environment
```

> NB : As per the _getopt_ flavor, the options can be put anywhere in the command (after or before arguments).

This will deploy your application normally, AND `rm -fR` all the non-linked deployment folders in `www` corresponding to the environment you're deploying.

> NB : It is not possible to cleanup and rollback at the same time, obviously

## Deploying easily from a remote client

In order to facilitate deployment from a remote client (your computer for instance), I recommend adding the following function to your `~/.profile` _(change the server url and script path accordingly)_ :

```bash
function deploy(){

  ssh -t -t -t my.server.com -p 22  "/var/deploy/_script/deploy.sh $*"

}
```
