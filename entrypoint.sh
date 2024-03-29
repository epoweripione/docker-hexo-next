#!/bin/sh

# GITHUB: github repository address
# GITLAB: Gitlab repository address
# WEBHOOK_SECRET: github webhook secret （not support for GitLab）

set -ex

if [ ! -x "$(command -v hexo)" ]; then
	/var/lib/hexo/install.sh
fi

# Init
if [ ! -f "/opt/hexo/_config.yml" ]; then
	hexo init .
	npm install
fi

# Deploy
if [ ! -f "/opt/hexo/deploy.sh" ]; then
	cp /var/lib/hexo/deploy.sh /opt/hexo
fi

if [ ! -f "/opt/hexo/gulpfile.js" ]; then
	cp /var/lib/hexo/gulpfile.js /opt/hexo/gulpfile.js
fi

if [ ! -f "/opt/hexo/index.js" ]; then
	cp /var/lib/hexo/index.js /opt/hexo/index.js

	[ -z "$WEBHOOK_SECRET" ] && WEBHOOK_SECRET=123456
	sed -i "s/WEBHOOK_SECRET/$WEBHOOK_SECRET/" /opt/hexo/index.js

	# Github webhook
	if [ -n "$GITHUB" ]; then
		# npm install github-webhook-handler
		sed -i "s/WEBHOOK-HANDLER/github-webhook-handler/" /opt/hexo/index.js
		rm -rf /opt/hexo/source/_posts
		git clone "$GITHUB" /opt/hexo/source/_posts
		pm2 start index.js --name hexo
		/opt/hexo/deploy.sh
	fi

	# Gitlab webhook
	if [ -n "$GITLAB" ]; then
		# npm install node-gitlab-webhook
		sed -i "s/WEBHOOK-HANDLER/node-gitlab-webhook/" /opt/hexo/index.js
		rm -rf /opt/hexo/source/_posts
		git clone "$GITLAB" /opt/hexo/source/_posts
		pm2 start index.js --name hexo
		/opt/hexo/deploy.sh
	fi
else
	pm2 start index.js --name hexo
fi

if [ ! -d "/opt/hexo/public" ]; then
	/opt/hexo/deploy.sh
fi

if [ ! -s "/opt/hexo/public/index.html" ]; then
	/opt/hexo/deploy.sh
fi

# crond -b -L /var/log/crond.log
# nginx -g "daemon off;"

exec "$@"
