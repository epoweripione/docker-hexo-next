#!/bin/sh

# Rotate the Nginx logs to prevent a single logfile from consuming too much disk space
# Rotate logs everyday with crons: 
# (crontab -l 2>/dev/null || true; echo "0 0 * * * /nginxLogRotate.sh > /dev/null") | crontab -

NGINX_LOGS_PATH=/var/log/nginx
BACKUP_LOGS_PATH=/opt/log/nginx

if [[ ! -d "$BACKUP_LOGS_PATH" ]]; then
    mkdir -p "$BACKUP_LOGS_PATH"
fi

YESTERDAY=$(date -d "yesterday" +%Y-%m-%d)
find "$NGINX_LOGS_PATH" -type f -name "*.log" | while read FULLFILE; do
    # echo 'hello.txt' | sed -r 's/.+\.(.+)|.*/\1/' # EXTENSION
    # echo 'hello.txt' | sed -r 's/(.+)\..+|(.*)/\1\2/' # FILENAME
    if [[ -s "$FULLFILE" ]]; then
        FILENAME=$(echo $(basename ${FULLFILE}) | sed -r 's/(.+)\..+|(.*)/\1\2/')

        mv ${FULLFILE} ${BACKUP_LOGS_PATH}/${FILENAME}_${YESTERDAY}.log
    fi
    # mv ${NGINX_LOGS_PATH}/access.log ${BACKUP_LOGS_PATH}/access_${YESTERDAY}.log
    # mv ${NGINX_LOGS_PATH}/error.log ${BACKUP_LOGS_PATH}/error_${YESTERDAY}.log
done

# re-open NGINX logs in response to the USR1 signal
kill -USR1 $(cat /var/run/nginx.pid)