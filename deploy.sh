#!/bin/sh
set -ex

POSTS_PATH='/opt/hexo/source/_posts'

echo "Start generation and deployment"
cd $POSTS_PATH

echo "Pulling source code..."
git pull origin master

echo "Generate and deploy..."
cd /opt/hexo
hexo clean && hexo g

if [ -f "/opt/hexo/gulp.js" ]; then
    echo "gulp minify..."
    gulp
fi

echo "Deploy finished."
