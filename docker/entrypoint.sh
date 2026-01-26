#!/bin/sh

set -e


# sh version of https://github.com/docker-library/mysql/blob/master/docker-entrypoint.sh
file_env() {
  var="$1"
  fileVar="${var}_FILE"
  def="${2:-}"

  # Check if both var and fileVar are set
  eval "val_var=\$$var"
  eval "val_fileVar=\$$fileVar"
  if [ -n "$val_var" ] && [ -n "$val_fileVar" ]; then
    echo >&2 "error: both $var and $fileVar are set (but are exclusive)"
    exit 1
  fi

  # Set default value
  val="$def"

  # Use var if set
  if [ -n "$val_var" ]; then
    val="$val_var"
  # Use fileVar if set
  elif [ -n "$val_fileVar" ]; then
    val="$(cat "$val_fileVar")" || {
      echo >&2 "error: could not read file $val_fileVar"
      exit 1
    }
  fi

  # Export and unset
  eval "export $var=\"$val\""
  eval "unset $fileVar"
}

echo "Running version ${VERSION} commit ${COMMIT} built on ${CREATED}"

# Show versions
echo "supervisord version: $(supervisord version)"
php-fpm84 -v | head -n 1
nginx -v

# Initialize env vars that might be stored in a file
file_env APP_KEY
file_env DB_DATABASE
file_env DB_USERNAME
file_env DB_PASSWORD
file_env DB_HOST
file_env MAIL_USERNAME
file_env MAIL_PASSWORD
file_env REDIS_PASSWORD


# Database creation
if [ "${DB_CONNECTION}" = "sqlite" ]; then
  # DB_DATABASE is trimmed if necessary
  if [[ $DB_DATABASE == \"* ]] && [[ $DB_DATABASE == *\" ]] ; then
    dbpath=${DB_DATABASE:1:${#DB_DATABASE}-2}
  else
    dbpath=${DB_DATABASE}
  fi
  if [ $dbpath != "/srv/database/database.sqlite" ]; then
    echo "DB_DATABASE sets with custom path: ${dbpath}"
    if [ ! -f ${dbpath} ]; then
      echo "${dbpath} does not exist, we create it"
      touch ${dbpath}
    fi
  else
    echo "DB_DATABASE sets with default path, we will use a symlink"
    echo "Actual db file will be /2fauth/database.sqlite"
    if [ ! -f /2fauth/database.sqlite ]; then
      echo "/2fauth/database.sqlite does not exist, we create it"
      touch /2fauth/database.sqlite
    fi
    rm -f /srv/database/database.sqlite
    ln -s /2fauth/database.sqlite /srv/database/database.sqlite
    echo "/srv/database/database.sqlite is now a symlink to /2fauth/database.sqlite"
  fi
fi

# Inject storage in /2fauth and use it with a symlink
if [ ! -d /2fauth/storage ]; then
  mv /srv/storage /2fauth/storage
else
  rm -r /srv/storage
fi
ln -s /2fauth/storage /srv/storage
echo "/srv/storage is now a symlink to /2fauth/storage"

# validate a bunch of environment variables and warn the user:
for v in APP_KEY; do
    eval "val=\$$v"
    if [ -z "$val" ]; then
        echo "!! Environment variable $v is empty !!"
    fi
done

# Note: ${COMMIT} is set by the CI
if [ -f /2fauth/installed ]; then
  INSTALLED_COMMIT="$(cat /2fauth/installed)"
  if [ "${INSTALLED_COMMIT}" != "${COMMIT}" ]; then
    echo "Installed commit ${INSTALLED_COMMIT} is different from program commit ${COMMIT}, we are migrating..."
    php artisan cache:clear
    php artisan config:clear
    php artisan migrate --force
  fi
else
  echo "First installation detected, running migrations..."
  php artisan migrate --force
  php artisan passport:install --no-interaction
fi

echo "${COMMIT}" > /2fauth/installed
php artisan storage:link --quiet

# Clearing compiled, cache has already been cleared
php artisan clear-compiled

# Clearing and Caching config, events, routes, views
php artisan optimize

supervisord
