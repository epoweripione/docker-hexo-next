#!/bin/sh

# GITHUB: github repository address
# GITLAB: Gitlab repository address
# WEBHOOK_SECRET: github webhook secret （not support for GitLab）

set -ex

# Init
if [ ! -f "/opt/hexo/_config.yml" ]; then
	hexo init .
	npm install
fi

# Deploy
if [ ! -f "/opt/hexo/deploy.sh" ]; then
	cp /var/lib/hexo/deploy.sh /opt/hexo
fi

if [ ! -f "/opt/hexo/gulp.js" ]; then
	cp /var/lib/hexo/gulp.js /opt/hexo/gulp.js
fi

if [ ! -f "/opt/hexo/index.js" ]; then
	cp /var/lib/hexo/index.js /opt/hexo/index.js

	[ -z $WEBHOOK_SECRET ] && WEBHOOK_SECRET=123456
	sed -i "s/WEBHOOK_SECRET/$WEBHOOK_SECRET/" /opt/hexo/index.js

	# Github webhook
	if [ ! -z $GITHUB ]; then
		npm install github-webhook-handler
		sed -i "s/WEBHOOK-HANDLER/github-webhook-handler/" /opt/hexo/index.js
		rm -rf /opt/hexo/source/_posts
		git clone $GITHUB /opt/hexo/source/_posts
		pm2 start index.js --name hexo
		/opt/hexo/deploy.sh
	fi

	# Gitlab webhook
	if [ ! -z $GITLAB ]; then
		npm install node-gitlab-webhook
		sed -i "s/WEBHOOK-HANDLER/node-gitlab-webhook/" /opt/hexo/index.js
		rm -rf /opt/hexo/source/_posts
		git clone $GITLAB /opt/hexo/source/_posts
		pm2 start index.js --name hexo
		/opt/hexo/deploy.sh
	fi
else
	pm2 start index.js --name hexo
	hexo clean && hexo g

	if [ -f "/opt/hexo/gulp.js" ]; then
		gulp
	fi
fi


crond -b -L /var/log/crond.log

nginx -g "daemon off;"

# exec "$@"
