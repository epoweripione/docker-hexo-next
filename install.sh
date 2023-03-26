#!/bin/sh
set -ex

# git config
# GITHUB_URL="https://hub.fastgit.org"
if [ -n "${GITHUB_URL}" ]; then
    git config --global url."${GITHUB_URL}/".insteadOf "https://github.com/"
else
    GITHUB_URL="https://github.com"
fi

git config --global url."${GITHUB_URL}/".insteadOf "ssh://git@github.com/"

echo "Install hexo & pm2..."
# NPM_REGISTRY="https://registry.npmmirror.com"
[ -n "${NPM_REGISTRY}" ] && npm config set registry "${NPM_REGISTRY}"

npm install hexo-cli -g
npm install pm2 -g

mkdir -p /opt/hexo /var/lib/hexo

cd /opt/hexo && hexo init . && npm install

# [NexT](https://theme-next.iissnan.com/getting-started.html)
echo "Install hexo theme NexT..."
git clone --depth=1 "${GITHUB_URL}/next-theme/hexo-theme-next" themes/next

echo "Install theme-next-pdf..."
git clone --depth=1 "${GITHUB_URL}/next-theme/theme-next-pdf" themes/next/source/lib/pdf

# hexo plugins
echo "Install hexo plugins..."
# npm install gulp -g
# npm install gulp gulp-htmlclean gulp-htmlmin gulp-minify-css --save

npm install hexo-tag-aplayer --save
npm install hexo-tag-dplayer --save
npm install hexo-filter-flowchart --save

npm uninstall hexo-renderer-marked --save
npm install hexo-renderer-markdown-it --save

npm install markdown-it-abbr --save
npm install markdown-it-footnote --save
npm install markdown-it-ins --save
npm install markdown-it-sub --save
npm install markdown-it-sup --save
npm install markdown-it-deflist --save
npm install markdown-it-emoji --save
npm install markdown-it-container --save
npm install markdown-it-mark --save
npm install markdown-it-anchor --save
npm install markdown-it-multimd-table --save
npm install markdown-it-replace-link --save
npm install markdown-it-toc-and-anchor --save
npm install markdown-it-task-lists --save
npm install markdown-it-katex --save
npm install @gerhobbelt/markdown-it-html5-embed --save

# npm install hexo-optimize --save
npm install hexo-generator-searchdb --save
npm install hexo-filter-emoji --save
npm install hexo-pangu --save
npm install hexo-filter-mathjax --save
npm install hexo-renderer-ruby-sass --save

npm install hexo-word-counter --save
npm install hexo-symbols-count-time --save

npm install hexo-generator-feed --save
npm install hexo-generator-seo-friendly-sitemap --save
npm install hexo-generator-indexed --save

# [Awesome NexT](https://github.com/next-theme/awesome-next)
npm install @next-theme/plugins --save
npm install @next-theme/utils --save

# Widgets
# npm install theme-next/theme-next-calendar --save
# npm install theme-next/hexo-cake-moon-menu --save

# Fancy stuff
npm install next-theme/hexo-next-three --save
npm install next-theme/hexo-next-fireworks --save
# npm install theme-next/hexo-next-title --save
npm install next-theme/hexo-next-exif --save

# Tools for posts
# npm install theme-next/hexo-next-coauthor --save
# npm install theme-next/hexo-next-share --save

# Comment
npm install hexo-disqus-php-api --save
# npm install theme-next/hexo-next-utteranc --save
npm install next-theme/hexo-next-valine --save
npm install @waline/hexo-next --save
# npm install hexo-next-discussbot --save
npm install hexo-next-twikoo@1.0.3 --save
npm install hexo-next-giscus --save

npm install 1v9/hexo-next-nightmode --save

# deploy webhook plugins
npm install github-webhook-handler --save
npm install gogs-webhook-handler --save
npm install node-gitlab-webhook --save

echo "Install hexo & theme finished."
