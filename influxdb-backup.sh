#!/bin/bash

set -e

# Check and set missing environment vars
: ${DATABASE:?"DATABASE env variable is required"}
export BACKUP_PATH=${BACKUP_PATH:-/data/influxdb/backup}
export BACKUP_RESERVED_DAY=${BACKUP_RESERVED_DAY:-3}
export RESTORE_FILE_NAME=${BACKUP_RESERVED_DAY:-influxdb_backup_${DATABASE}} # without .tgz
export RESTORE_DATABASE=${RESTORE_DATABASE:-${DATABASE}-restore} # without .tgz
export DATABASE_HOST=${DATABASE_HOST:-localhost}
export DATABASE_PORT=${DATABASE_PORT:-8088}

# Add this script to the crontab and start crond
cron() {
  echo "Starting backup cron job with frequency '$1'"
  echo "$1 $0 backup" > /var/spool/cron/crontabs/root
  crond -f
}

# Dump the database to a file
backup() {
  # Dump database to directory
  echo "Backing up $DATABASE to $BACKUP_PATH"
  # back path exit or not
  if [ ! -d $BACKUP_PATH ]; then
    mkdir -p $BACKUP_PATH
  fi
  prefix=influxdb_backup_${DATABASE}_
  # count exist
  cd $BACKUP_PATH
  count=`find -mindepth 1 -maxdepth 1 -type f -name ${prefix}* | wc -w`
  echo "$DATABASE already Exist $count Backup"
  # remove
  if [ $count -gt $BACKUP_RESERVED_DAY ]; then
    find -mindepth 1 -maxdepth 1 -type f -name ${prefix}* -ctime +${BACKUP_RESERVED_DAY} -exec rm -rf {} \;
  fi
  # cur date dir
  curdir=${prefix}$(date +%Y%m%d)
  if [ -d $curdir ]; then
    rm -rf $curdir
  fi
  mkdir $curdir
  # backup
  influxd backup -portable -database $DATABASE -host $DATABASE_HOST:$DATABASE_PORT $curdir
  if [ $? -ne 0 ]; then
    echo "Failed to backup $DATABASE to $BACKUP_PATH"
    exit 1
  fi
  # Compress backup directory
  curfile=${curdir}.tgz
  if [ -e $curfile ]; then
    rm -rf $curfile
  fi
  tar -cvzf $curfile $curdir
  if [ $? -ne 0 ]; then
    echo "Failed to backup $DATABASE to $BACKUP_PATH"
    exit 1
  fi
  # remove dir
  if [ -d $curdir ]; then
    rm -rf $curdir
  fi
  echo "Done"
}

# Pull down the latest backup from S3 and restore it to the database
restore() {
  cd $BACKUP_PATH
  # Remove old backup file
  if [ -d $RESTORE_FILE_NAME ]; then
    echo "Removing out of date backup"
    rm -rf $RESTORE_FILE_NAME
  fi
  
  # Extract archive
  tar -xvzf ${RESTORE_FILE_NAME}.tgz

  # Restore database from backup file
  echo "Running restore"
  if influxd restore -db $DATABASE -portable -host $DATABASE_HOST:$DATABASE_PORT -newdb $RESTORE_DATABASE $RESTORE_FILE_NAME ; then
    echo "Successfully restored"
  else
    echo "Restore failed"
    exit 1
  fi
  echo "Done"
}

# Handle command line arguments
case "$1" in
  "cron")
    cron "$2"
    ;;
  "backup")
    backup
    ;;
  "restore")
    restore
    ;;
  *)
    echo "Invalid command '$@'"
    echo "Usage: $0 {backup|restore|cron <pattern>}"
esac
