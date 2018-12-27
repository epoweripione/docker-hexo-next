#!/bin/sh

# block ip which access times greater than 1000 in latest 50000 requests
# log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
#                   '$status $body_bytes_sent "$http_referer" $request_time '
#                   '"$http_user_agent" "$http_x_forwarded_for"';
# $1: remote_addr
# $13: http_user_agent

PARAMS_NUM=$#

TAIL_COUNT=50000
DENY_COUNT=1000
if [[ $PARAMS_NUM >= 2 ]]; then
    TAIL_COUNT=$1
    DENY_COUNT=$2
fi

expr 1 + $TAIL_COUNT &>/dev/null
[ $? -eq 2 ] && echo "$TAIL_COUNT is not an integer!" && exit 2

expr 1 + $DENY_COUNT &>/dev/null
[ $? -eq 2 ] && echo "$DENY_COUNT is not an integer!" && exit 2

NGINX_HOME=/etc/nginx
NGINX_LOGS_PATH=/var/log/nginx

tail -n${TAIL_COUNT} ${NGINX_LOGS_PATH}/access.log \
    |awk '{print $1,$13}' \
    |grep -i -v -E "google|bing|baidu|qq|so|sogou" \
    |awk '{print $1}'|sort|uniq -c|sort -rn \
    |awk -v count=$DENY_COUNT '{if($1>count) print "deny "$2";"}' >${NGINX_HOME}/snippets/BlocksIP.conf

nginx -t && nginx -s reload