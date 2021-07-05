FROM node:lts-alpine3.13

LABEL Maintainer="Ansley Leung" \
    Description="Hexo with theme NexT: Auto generate and deploy website use GITHUB webhook" \
    License="MIT License" \
    Version="14.17.1"

ENV TZ=Asia/Shanghai
RUN set -ex && \
    # sed -i 's|http://dl-cdn.alpinelinux.org|https://mirrors.ustc.edu.cn|g' /etc/apk/repositories && \
    apk update && \
    apk upgrade && \
    apk add --no-cache coreutils ca-certificates curl openssl git openssh tzdata && \
    # ln -snf /usr/share/zoneinfo/ /etc/localtime && \
    cp /usr/share/zoneinfo/$TZ /etc/localtime && \
    echo $TZ > /etc/timezone && \
    apk del tzdata && \
    npm set registry https://registry.npm.taobao.org && \
    # PROXY_ADDRESS="127.0.0.1:1080" && \
    # git config --global http.proxy "socks5://${PROXY_ADDRESS}" && \
    # git config --global https.proxy "socks5://${PROXY_ADDRESS}" && \
    rm -rf /tmp/* /var/cache/apk/*


# nginx
# mainline: https://github.com/nginxinc/docker-nginx/tree/master/mainline/alpine
ENV NGINX_VERSION 1.21.0
ENV NJS_VERSION   0.5.3
ENV PKG_RELEASE   1

RUN set -x \
# create nginx user/group first, to be consistent throughout docker variants
    && addgroup -g 101 -S nginx \
    && adduser -S -D -H -u 101 -h /var/cache/nginx -s /sbin/nologin -G nginx -g nginx nginx \
    && apkArch="$(cat /etc/apk/arch)" \
    && nginxPackages=" \
        nginx=${NGINX_VERSION}-r${PKG_RELEASE} \
        nginx-module-xslt=${NGINX_VERSION}-r${PKG_RELEASE} \
        nginx-module-geoip=${NGINX_VERSION}-r${PKG_RELEASE} \
        nginx-module-image-filter=${NGINX_VERSION}-r${PKG_RELEASE} \
        nginx-module-njs=${NGINX_VERSION}.${NJS_VERSION}-r${PKG_RELEASE} \
    " \
    && case "$apkArch" in \
        x86_64|aarch64) \
# arches officially built by upstream
            set -x \
            && KEY_SHA512="e7fa8303923d9b95db37a77ad46c68fd4755ff935d0a534d26eba83de193c76166c68bfe7f65471bf8881004ef4aa6df3e34689c305662750c0172fca5d8552a *stdin" \
            && apk add --no-cache --virtual .cert-deps \
                openssl \
            && wget -O /tmp/nginx_signing.rsa.pub https://nginx.org/keys/nginx_signing.rsa.pub \
            && if [ "$(openssl rsa -pubin -in /tmp/nginx_signing.rsa.pub -text -noout | openssl sha512 -r)" = "$KEY_SHA512" ]; then \
                echo "key verification succeeded!"; \
                mv /tmp/nginx_signing.rsa.pub /etc/apk/keys/; \
            else \
                echo "key verification failed!"; \
                exit 1; \
            fi \
            && apk del .cert-deps \
            && apk add -X "https://nginx.org/packages/mainline/alpine/v$(egrep -o '^[0-9]+\.[0-9]+' /etc/alpine-release)/main" --no-cache $nginxPackages \
            ;; \
        *) \
# we're on an architecture upstream doesn't officially build for
# let's build binaries from the published packaging sources
            set -x \
            && tempDir="$(mktemp -d)" \
            && chown nobody:nobody $tempDir \
            && apk add --no-cache --virtual .build-deps \
                gcc \
                libc-dev \
                make \
                openssl-dev \
                pcre-dev \
                zlib-dev \
                linux-headers \
                libxslt-dev \
                gd-dev \
                geoip-dev \
                perl-dev \
                libedit-dev \
                mercurial \
                bash \
                alpine-sdk \
                findutils \
            && su nobody -s /bin/sh -c " \
                export HOME=${tempDir} \
                && cd ${tempDir} \
                && hg clone https://hg.nginx.org/pkg-oss \
                && cd pkg-oss \
                && hg up ${NGINX_VERSION}-${PKG_RELEASE} \
                && cd alpine \
                && make all \
                && apk index -o ${tempDir}/packages/alpine/${apkArch}/APKINDEX.tar.gz ${tempDir}/packages/alpine/${apkArch}/*.apk \
                && abuild-sign -k ${tempDir}/.abuild/abuild-key.rsa ${tempDir}/packages/alpine/${apkArch}/APKINDEX.tar.gz \
                " \
            && cp ${tempDir}/.abuild/abuild-key.rsa.pub /etc/apk/keys/ \
            && apk del .build-deps \
            && apk add -X ${tempDir}/packages/alpine/ --no-cache $nginxPackages \
            ;; \
    esac \
# if we have leftovers from building, let's purge them (including extra, unnecessary build deps)
    && if [ -n "$tempDir" ]; then rm -rf "$tempDir"; fi \
    && if [ -n "/etc/apk/keys/abuild-key.rsa.pub" ]; then rm -f /etc/apk/keys/abuild-key.rsa.pub; fi \
    && if [ -n "/etc/apk/keys/nginx_signing.rsa.pub" ]; then rm -f /etc/apk/keys/nginx_signing.rsa.pub; fi \
# Bring in gettext so we can get `envsubst`, then throw
# the rest away. To do this, we need to install `gettext`
# then move `envsubst` out of the way so `gettext` can
# be deleted completely, then move `envsubst` back.
    && apk add --no-cache --virtual .gettext gettext \
    && mv /usr/bin/envsubst /tmp/ \
    \
    && runDeps="$( \
        scanelf --needed --nobanner /tmp/envsubst \
            | awk '{ gsub(/,/, "\nso:", $2); print "so:" $2 }' \
            | sort -u \
            | xargs -r apk info --installed \
            | sort -u \
    )" \
    && apk add --no-cache $runDeps \
    && apk del .gettext \
    && mv /tmp/envsubst /usr/local/bin/ \
# Bring in tzdata so users could set the timezones through the environment
# variables
    && apk add --no-cache tzdata \
# Bring in curl and ca-certificates to make registering on DNS SD easier
    && apk add --no-cache curl ca-certificates \
# forward request and error logs to docker log collector
    && ln -sf /dev/stdout /var/log/nginx/access.log \
    && ln -sf /dev/stderr /var/log/nginx/error.log \
# create a docker-entrypoint.d directory
    && mkdir /docker-entrypoint.d


# acme.sh
RUN set -ex && \
    git clone --depth=1 https://github.com/acmesh-official/acme.sh.git /tmp/acme.sh && \
    cd /tmp/acme.sh && \
    ./acme.sh --install --home /opt/acme.sh --config-home /etc/nginx/ssl && \
    cd ~ && \
    crontab -l | sed "s|acme.sh --cron|acme.sh --cron --renew-hook \"nginx -s reload\"|g" | crontab - && \
    ln -s /opt/acme.sh/acme.sh /usr/bin/acme.sh && \
    rm -rf /tmp/* /var/cache/apk/*


## node
## https://github.com/mhart/alpine-node
# ENV VERSION=v14.15.4 NPM_VERSION=6 YARN_VERSION=v1.22.10 NODE_BUILD_PYTHON=python3

# RUN apk upgrade --no-cache -U && \
#   apk add --no-cache curl make gcc g++ ${NODE_BUILD_PYTHON} linux-headers binutils-gold gnupg libstdc++

# RUN for server in ipv4.pool.sks-keyservers.net keyserver.pgp.com ha.pool.sks-keyservers.net; do \
#     gpg --keyserver $server --recv-keys \
#       4ED778F539E3634C779C87C6D7062848A1AB005C \
#       94AE36675C464D64BAFA68DD7434390BDBE9B9C5 \
#       1C050899334244A8AF75E53792EF661D867B9DFA \
#       71DCFD284A79C3B38668286BC97EC7A07EDE3FC1 \
#       8FCCA13FEF1D0C2E91008E09770F7A9A5AE15600 \
#       C4F0DFFF4E8C1A8236409D08E73BC641CC11F4C8 \
#       C82FA3AE1CBEDC6BE46B9360C43CEC45C17AB93C \
#       DD8F2338BAE7501E3DD5AC78C273792F7D83545D \
#       A48C2BEE680E841632CD4E44F07496B3EB3C1762 \
#       108F52B48DB57BB0CC439B2997B01419BD92F80A \
#       B9E2F5981AA6E0CD28160D9FF13993A75599653C && break; \
#   done

# RUN curl -sfSLO https://nodejs.org/dist/${VERSION}/node-${VERSION}.tar.xz && \
#   curl -sfSL https://nodejs.org/dist/${VERSION}/SHASUMS256.txt.asc | gpg -d -o SHASUMS256.txt && \
#   grep " node-${VERSION}.tar.xz\$" SHASUMS256.txt | sha256sum -c | grep ': OK$' && \
#   tar -xf node-${VERSION}.tar.xz && \
#   cd node-${VERSION} && \
#   ./configure --prefix=/usr ${CONFIG_FLAGS} && \
#   make -j$(getconf _NPROCESSORS_ONLN) && \
#   make install

# RUN if [ -z "$CONFIG_FLAGS" ]; then \
#     if [ -n "$NPM_VERSION" ]; then \
#       npm install -g npm@${NPM_VERSION}; \
#     fi; \
#     find /usr/lib/node_modules/npm -type d \( -name test -o -name .bin \) | xargs rm -rf; \
#     if [ -n "$YARN_VERSION" ]; then \
#       for server in ipv4.pool.sks-keyservers.net keyserver.pgp.com ha.pool.sks-keyservers.net; do \
#         gpg --keyserver $server --recv-keys \
#           6A010C5166006599AA17F08146C2130DFD2497F5 && break; \
#       done && \
#       curl -sfSL -O https://github.com/yarnpkg/yarn/releases/download/${YARN_VERSION}/yarn-${YARN_VERSION}.tar.gz -O https://github.com/yarnpkg/yarn/releases/download/${YARN_VERSION}/yarn-${YARN_VERSION}.tar.gz.asc && \
#       gpg --batch --verify yarn-${YARN_VERSION}.tar.gz.asc yarn-${YARN_VERSION}.tar.gz && \
#       mkdir /usr/local/share/yarn && \
#       tar -xf yarn-${YARN_VERSION}.tar.gz -C /usr/local/share/yarn --strip 1 && \
#       ln -s /usr/local/share/yarn/bin/yarn /usr/local/bin/ && \
#       ln -s /usr/local/share/yarn/bin/yarnpkg /usr/local/bin/ && \
#       rm yarn-${YARN_VERSION}.tar.gz*; \
#     fi; \
#   fi

# RUN apk del curl make gcc g++ ${NODE_BUILD_PYTHON} linux-headers binutils-gold gnupg ${DEL_PKGS} && \
#   rm -rf ${RM_DIRS} /node-${VERSION}* /SHASUMS256.txt /tmp/* \
#     /usr/share/man/* /usr/share/doc /root/.npm /root/.node-gyp /root/.config \
#     /usr/lib/node_modules/npm/man /usr/lib/node_modules/npm/doc /usr/lib/node_modules/npm/docs \
#     /usr/lib/node_modules/npm/html /usr/lib/node_modules/npm/scripts && \
#   { rm -rf /root/.gnupg || true; }


# hexo
RUN set -ex && \
    npm install hexo-cli -g && \
    npm install pm2 -g && \
    mkdir -p /opt/hexo /var/lib/hexo && \
    cd /opt/hexo && \
    hexo init . && \
    npm install

# hexo theme NexT
# NexT https://theme-next.iissnan.com/getting-started.html
RUN set -ex && \
    cd /opt/hexo && \
    git clone --depth=1 https://github.com/next-theme/hexo-theme-next themes/next && \
    git clone --depth=1 https://github.com/next-theme/theme-next-pdf themes/next/source/lib/pdf

# other hexo plugins
RUN set -ex && \
    cd /opt/hexo && \
    # npm install gulp -g && \
    # npm install gulp gulp-htmlclean gulp-htmlmin gulp-minify-css --save && \
    : && \
    npm install hexo-tag-aplayer --save && \
    npm install hexo-tag-dplayer --save && \
    npm install hexo-filter-flowchart --save && \
    : && \
    npm uninstall hexo-renderer-marked --save && \
    npm install hexo-renderer-markdown-it --save && \
    : && \
    npm install markdown-it-abbr --save && \
    npm install markdown-it-footnote --save && \
    npm install markdown-it-ins --save && \
    npm install markdown-it-sub --save && \
    npm install markdown-it-sup --save && \
    npm install markdown-it-deflist --save && \
    npm install markdown-it-emoji --save && \
    npm install markdown-it-container --save && \
    npm install markdown-it-mark --save && \
    npm install markdown-it-anchor --save && \
    npm install markdown-it-multimd-table --save && \
    npm install markdown-it-replace-link --save && \
    npm install markdown-it-toc-and-anchor --save && \
    npm install markdown-it-task-lists --save && \
    npm install markdown-it-katex --save && \
    npm install @gerhobbelt/markdown-it-html5-embed --save


# Awesome NexT
# https://github.com/next-theme/awesome-next
RUN set -ex && \
    cd /opt/hexo && \
    npm install @next-theme/plugins --save && \
    npm install @next-theme/utils --save && \
    : && \
    # Hexo Plugins
    npm install hexo-optimize --save && \
    npm install hexo-generator-searchdb --save && \
    npm install hexo-filter-emoji --save && \
    npm install hexo-pangu --save && \
    npm install hexo-filter-mathjax --save && \
    npm install hexo-renderer-ruby-sass --save && \
    : && \
    npm install hexo-word-counter --save && \
    npm install hexo-symbols-count-time --save && \
    : && \
    npm install hexo-generator-feed --save && \
    npm install hexo-generator-seo-friendly-sitemap --save && \
    npm install hexo-generator-indexed --save && \
    : && \
    # Widgets
    # npm install theme-next/theme-next-calendar --save && \
    # npm install theme-next/hexo-cake-moon-menu --save && \
    : && \
    # Fancy stuff
    npm install next-theme/hexo-next-three --save && \
    npm install next-theme/hexo-next-fireworks --save && \
    # npm install theme-next/hexo-next-title --save && \
    npm install next-theme/hexo-next-exif --save && \
    : && \
    # Tools for posts
    # npm install theme-next/hexo-next-coauthor --save && \
    # npm install theme-next/hexo-next-share --save && \
    : && \
    # Comment
    npm install hexo-disqus-php-api --save && \
    # npm install theme-next/hexo-next-utteranc --save && \
    npm install hexo-next-minivaline --save && \
    npm install @waline/hexo-next --save && \
    # npm install hexo-next-discussbot --save && \
    : && \
    npm install 1v9/hexo-next-nightmode --save

# deploy webhook plugins
RUN set -ex && \
    cd /opt/hexo && \
    npm install github-webhook-handler && \
    npm install gogs-webhook-handler && \
    npm install node-gitlab-webhook


WORKDIR /opt/hexo

# nginx files
COPY ./nginx.conf /etc/nginx/nginx.conf
COPY ./nginx.vh.default.conf /etc/nginx/conf.d/default.conf

COPY ./404.html /usr/share/nginx/html/404.html
COPY ./svg404.html /usr/share/nginx/html/svg404.html
COPY ./50x.html /usr/share/nginx/html/50x.html

COPY ./nginxBlocksIP.sh /nginxBlocksIP.sh
COPY ./nginxLogRotate.sh /nginxLogRotate.sh

# hexo files
COPY ./index.js /var/lib/hexo/index.js
COPY ./gulpfile.js /var/lib/hexo/gulpfile.js

COPY ./deploy.sh /var/lib/hexo/deploy.sh
COPY ./entrypoint.sh /entrypoint.sh

# Add GNU coreutils for date to support -d options
RUN set -ex && \
    mkdir -p /etc/nginx/snippets && \
    touch /etc/nginx/snippets/BlocksIP.conf && \
    chmod +x /var/lib/hexo/deploy.sh /entrypoint.sh && \
    chmod +x /nginxBlocksIP.sh /nginxLogRotate.sh && \
    (crontab -l 2>/dev/null || true; echo "0 0 * * * /nginxLogRotate.sh > /dev/null") | crontab - && \
    rm -rf /tmp/* /var/cache/apk/*


# Expose Ports
EXPOSE 80
EXPOSE 443
EXPOSE 5000

STOPSIGNAL SIGQUIT

ENTRYPOINT ["/entrypoint.sh"]

CMD ["nginx", "-g", "daemon off;"]
