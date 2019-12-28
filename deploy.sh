#!/bin/sh
set -ex

POSTS_PATH='/opt/hexo/source/_posts'

if [[ -d "$POSTS_PATH/.git" ]]; then
    echo "Start generation and deployment"
    cd "$POSTS_PATH"

    echo "Pulling source code..."
    git pull origin master
fi

echo "Generate and deploy..."
cd /opt/hexo
hexo clean && hexo g

if [[ -n "$GULP_MINIFY" ]]; then
    if [[ -d "/opt/hexo/public" && -f "/opt/hexo/gulpfile.js" ]]; then
        echo "gulp minify..."
        gulp
    fi
fi

echo "Deploy finished."
