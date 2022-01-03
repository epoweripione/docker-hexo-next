FROM node:lts-alpine

LABEL Maintainer="Ansley Leung" \
    Description="Hexo with theme NexT: Auto generate and deploy website use GITHUB webhook" \
    License="MIT License" \
    Version="16.13.1"

RUN set -ex && \
    apk update && \
    apk upgrade && \
    apk add --no-cache coreutils ca-certificates curl git


# nginx
# mainline: https://github.com/nginxinc/docker-nginx/tree/master/mainline/alpine
ENV NGINX_VERSION 1.21.5
ENV NJS_VERSION   0.7.1
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
# install prerequisites for public key and pkg-oss checks
    && apk add --no-cache --virtual .checksum-deps \
        openssl \
    && case "$apkArch" in \
        x86_64|aarch64) \
# arches officially built by upstream
            set -x \
            && KEY_SHA512="e7fa8303923d9b95db37a77ad46c68fd4755ff935d0a534d26eba83de193c76166c68bfe7f65471bf8881004ef4aa6df3e34689c305662750c0172fca5d8552a *stdin" \
            && wget -O /tmp/nginx_signing.rsa.pub https://nginx.org/keys/nginx_signing.rsa.pub \
            && if [ "$(openssl rsa -pubin -in /tmp/nginx_signing.rsa.pub -text -noout | openssl sha512 -r)" = "$KEY_SHA512" ]; then \
                echo "key verification succeeded!"; \
                mv /tmp/nginx_signing.rsa.pub /etc/apk/keys/; \
            else \
                echo "key verification failed!"; \
                exit 1; \
            fi \
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
                pcre2-dev \
                zlib-dev \
                linux-headers \
                libxslt-dev \
                gd-dev \
                geoip-dev \
                perl-dev \
                libedit-dev \
                bash \
                alpine-sdk \
                findutils \
            && su nobody -s /bin/sh -c " \
                export HOME=${tempDir} \
                && cd ${tempDir} \
                && curl -f -O https://hg.nginx.org/pkg-oss/archive/${NGINX_VERSION}-${PKG_RELEASE}.tar.gz \
                && PKGOSSCHECKSUM=\"b0ed109a820a2e8921f313d653032b8e70d3020138d634039ebb9194dc3968493f6eb4d85bdbf18d2aea7229deddb98ca0f1d9825defcc5af45f68ee37845232 *${NGINX_VERSION}-${PKG_RELEASE}.tar.gz\" \
                && if [ \"\$(openssl sha512 -r ${NGINX_VERSION}-${PKG_RELEASE}.tar.gz)\" = \"\$PKGOSSCHECKSUM\" ]; then \
                    echo \"pkg-oss tarball checksum verification succeeded!\"; \
                else \
                    echo \"pkg-oss tarball checksum verification failed!\"; \
                    exit 1; \
                fi \
                && tar xzvf ${NGINX_VERSION}-${PKG_RELEASE}.tar.gz \
                && cd pkg-oss-${NGINX_VERSION}-${PKG_RELEASE} \
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
# remove checksum deps
    && apk del .checksum-deps \
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
    npm install next-theme/hexo-next-valine --save && \
    npm install @waline/hexo-next --save && \
    # npm install hexo-next-discussbot --save && \
    npm install hexo-next-twikoo@1.0.1 --save && \
    npm install hexo-next-giscus --save && \
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
