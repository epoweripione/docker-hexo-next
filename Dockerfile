FROM node:alpine

LABEL Maintainer="Ansley Leung" \
      Description="Hexo with theme NexT: Auto generate and deploy website use GITHUB webhook" \
      License="MIT License" \
      Version="12.1.0"

ENV TZ=Asia/Shanghai
RUN set -ex && \
    apk add --no-cache tzdata && \
    ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && \
    echo $TZ > /etc/timezone


# nginx
# TLS1.3: https://github.com/khs1994-website/tls-1.3
#         https://github.com/angristan/nginx-autoinstall
# mainline: https://github.com/nginxinc/docker-nginx/tree/master/mainline/alpine
ENV NGINX_VERSION 1.15.12
ENV NJS_VERSION   0.3.1
ENV PKG_RELEASE 1

RUN set -x \
    && apkArch="$(cat /etc/apk/arch)" \
    && nginxPackages=" \
        nginx=${NGINX_VERSION}-r${PKG_RELEASE} \
        nginx-module-xslt=${NGINX_VERSION}-r${PKG_RELEASE} \
        nginx-module-geoip=${NGINX_VERSION}-r${PKG_RELEASE} \
        nginx-module-image-filter=${NGINX_VERSION}-r${PKG_RELEASE} \
        nginx-module-njs=${NGINX_VERSION}.${NJS_VERSION}-r${PKG_RELEASE} \
    " \
    && case "$apkArch" in \
        x86_64) \
# arches officially built by upstream
            set -x \
            && KEY_SHA512="e7fa8303923d9b95db37a77ad46c68fd4755ff935d0a534d26eba83de193c76166c68bfe7f65471bf8881004ef4aa6df3e34689c305662750c0172fca5d8552a *stdin" \
            && apk add --no-cache --virtual .cert-deps \
                openssl curl ca-certificates \
            && curl -o /tmp/nginx_signing.rsa.pub https://nginx.org/keys/nginx_signing.rsa.pub \
            && if [ "$(openssl rsa -pubin -in /tmp/nginx_signing.rsa.pub -text -noout | openssl sha512 -r)" = "$KEY_SHA512" ]; then \
                 echo "key verification succeeded!"; \
                 mv /tmp/nginx_signing.rsa.pub /etc/apk/keys/; \
               else \
                 echo "key verification failed!"; \
                 exit 1; \
               fi \
            && printf "%s%s%s\n" \
                "http://nginx.org/packages/mainline/alpine/v" \
                `egrep -o '^[0-9]+\.[0-9]+' /etc/alpine-release` \
                "/main" \
            | tee -a /etc/apk/repositories \
            && apk del .cert-deps \
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
            && su - nobody -s /bin/sh -c " \
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
            && echo "${tempDir}/packages/alpine/" >> /etc/apk/repositories \
            && cp ${tempDir}/.abuild/abuild-key.rsa.pub /etc/apk/keys/ \
            && apk del .build-deps \
            ;; \
    esac \
    && apk add --no-cache $nginxPackages \
# if we have leftovers from building, let's purge them (including extra, unnecessary build deps)
    && if [ -n "$tempDir" ]; then rm -rf "$tempDir"; fi \
    && if [ -n "/etc/apk/keys/abuild-key.rsa.pub" ]; then rm -f /etc/apk/keys/abuild-key.rsa.pub; fi \
    && if [ -n "/etc/apk/keys/nginx_signing.rsa.pub" ]; then rm -f /etc/apk/keys/nginx_signing.rsa.pub; fi \
# remove the last line with the packages repos in the repositories file
    && sed -i '$ d' /etc/apk/repositories \
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
# forward request and error logs to docker log collector
    && ln -sf /dev/stdout /var/log/nginx/access.log \
    && ln -sf /dev/stderr /var/log/nginx/error.log


# acme.sh
ENV LE_WORKING_DIR=/opt/acme.sh

RUN set -ex && \
    apk add --no-cache ca-certificates curl openssl && \
    curl -sSL https://get.acme.sh | sh && \
    crontab -l | sed "s|acme.sh --cron|acme.sh --cron --renew-hook \"nginx -s reload\"|g" | crontab - && \
    ln -s /opt/acme.sh/acme.sh /usr/bin/acme.sh && \
    rm -rf /tmp/* /var/cache/apk/*


# # node
# # https://github.com/mhart/alpine-node
# ENV VERSION=v11.11.0 NPM_VERSION=6 YARN_VERSION=latest

# # For base builds
# ENV CONFIG_FLAGS="--fully-static --without-npm" DEL_PKGS="libstdc++" RM_DIRS=/usr/include

# RUN apk add --no-cache curl make gcc g++ python linux-headers binutils-gold gnupg libstdc++ && \
#   for server in ipv4.pool.sks-keyservers.net keyserver.pgp.com ha.pool.sks-keyservers.net; do \
#     gpg --keyserver $server --recv-keys \
#       4ED778F539E3634C779C87C6D7062848A1AB005C \
#       B9E2F5981AA6E0CD28160D9FF13993A75599653C \
#       94AE36675C464D64BAFA68DD7434390BDBE9B9C5 \
#       B9AE9905FFD7803F25714661B63B535A4C206CA9 \
#       77984A986EBC2AA786BC0F66B01FBB92821C587A \
#       71DCFD284A79C3B38668286BC97EC7A07EDE3FC1 \
#       FD3A5288F042B6850C66B31F09FE44734EB7990E \
#       8FCCA13FEF1D0C2E91008E09770F7A9A5AE15600 \
#       C4F0DFFF4E8C1A8236409D08E73BC641CC11F4C8 \
#       DD8F2338BAE7501E3DD5AC78C273792F7D83545D \
#       A48C2BEE680E841632CD4E44F07496B3EB3C1762 && break; \
#   done && \
#   curl -sfSLO https://nodejs.org/dist/${VERSION}/node-${VERSION}.tar.xz && \
#   curl -sfSL https://nodejs.org/dist/${VERSION}/SHASUMS256.txt.asc | gpg -d -o SHASUMS256.txt && \
#   grep " node-${VERSION}.tar.xz\$" SHASUMS256.txt | sha256sum -c | grep ': OK$' && \
#   tar -xf node-${VERSION}.tar.xz && \
#   cd node-${VERSION} && \
#   ./configure --prefix=/usr ${CONFIG_FLAGS} && \
#   make -j$(getconf _NPROCESSORS_ONLN) && \
#   make install && \
#   cd / && \
#   if [ -z "$CONFIG_FLAGS" ]; then \
#     if [ -n "$NPM_VERSION" ]; then \
#       npm install -g npm@${NPM_VERSION}; \
#     fi; \
#     find /usr/lib/node_modules/npm -name test -o -name .bin -type d | xargs rm -rf; \
#     if [ -n "$YARN_VERSION" ]; then \
#       for server in ipv4.pool.sks-keyservers.net keyserver.pgp.com ha.pool.sks-keyservers.net; do \
#         gpg --keyserver $server --recv-keys \
#           6A010C5166006599AA17F08146C2130DFD2497F5 && break; \
#       done && \
#       curl -sfSL -O https://yarnpkg.com/${YARN_VERSION}.tar.gz -O https://yarnpkg.com/${YARN_VERSION}.tar.gz.asc && \
#       gpg --batch --verify ${YARN_VERSION}.tar.gz.asc ${YARN_VERSION}.tar.gz && \
#       mkdir /usr/local/share/yarn && \
#       tar -xf ${YARN_VERSION}.tar.gz -C /usr/local/share/yarn --strip 1 && \
#       ln -s /usr/local/share/yarn/bin/yarn /usr/local/bin/ && \
#       ln -s /usr/local/share/yarn/bin/yarnpkg /usr/local/bin/ && \
#       rm ${YARN_VERSION}.tar.gz*; \
#     fi; \
#   fi && \
#   apk del curl make gcc g++ python linux-headers binutils-gold gnupg ${DEL_PKGS} && \
#   rm -rf ${RM_DIRS} /node-${VERSION}* /SHASUMS256.txt /usr/share/man /tmp/* /var/cache/apk/* \
#     /root/.npm /root/.node-gyp /usr/lib/node_modules/npm/man \
#     /usr/lib/node_modules/npm/doc /usr/lib/node_modules/npm/html /usr/lib/node_modules/npm/scripts && \
#   { rm -rf /root/.gnupg || true; }


# hexo
RUN set -ex && \
    npm install hexo-cli -g && \
    npm install pm2 -g && \
    mkdir -p /opt/hexo /var/lib/hexo && \
    cd /opt/hexo && \
    hexo init . && \
    npm install && \
    npm install hexo-generator-feed --save && \
    npm install hexo-generator-sitemap --save && \
    npm install hexo-generator-searchdb --save

# hexo theme NexT
# NexT https://theme-next.iissnan.com/getting-started.html
RUN set -ex && \
    apk add --no-cache git openssh && \
    rm -rf /tmp/* /var/cache/apk/* && \
    cd /opt/hexo && \
    git clone https://github.com/theme-next/hexo-theme-next themes/next && \
    git clone https://github.com/theme-next/theme-next-fancybox3 themes/next/source/lib/fancybox && \
    git clone https://github.com/theme-next/theme-next-fastclick themes/next/source/lib/fastclick && \
    git clone https://github.com/theme-next/theme-next-jquery-lazyload themes/next/source/lib/jquery_lazyload && \
    git clone https://github.com/theme-next/theme-next-pace themes/next/source/lib/pace && \
    git clone https://github.com/theme-next/theme-next-pdf themes/next/source/lib/pdf && \
    git clone https://github.com/theme-next/theme-next-han themes/next/source/lib/Han && \
    git clone https://github.com/theme-next/theme-next-pangu themes/next/source/lib/pangu && \
    git clone https://github.com/theme-next/theme-next-needmoreshare2 themes/next/source/lib/needsharebutton && \
    git clone https://github.com/theme-next/theme-next-bookmark themes/next/source/lib/bookmark && \
    git clone https://github.com/theme-next/theme-next-canvas-nest themes/next/source/lib/canvas-nest && \
    git clone https://github.com/theme-next/theme-next-three themes/next/source/lib/three && \
    git clone https://github.com/theme-next/theme-next-canvas-ribbon themes/next/source/lib/canvas-ribbon && \
    git clone https://github.com/theme-next/theme-next-quicklink themes/next/source/lib/quicklink && \
    git clone https://github.com/theme-next/theme-next-reading-progress themes/next/source/lib/reading_progress

# other hexo plugins
RUN set -ex && \
    cd /opt/hexo && \
    npm install gulp -g && \
    npm install gulp gulp-htmlclean gulp-htmlmin gulp-minify-css --save && \
    npm install hexo-symbols-count-time --save && \
    npm install hexo-filter-github-emojis --save && \
    npm install hexo-tag-aplayer --save && \
    npm install hexo-tag-dplayer --save && \
    npm install hexo-footnotes --save && \
    npm install hexo-filter-flowchart --save && \
    npm uninstall hexo-generator-index --save && \
    npm install hexo-generator-index-pin-top --save

# deploy webhook plugins
RUN set -ex && \
    cd /opt/hexo && \
    npm install github-webhook-handler && \
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
    apk add --no-cache coreutils && \
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

STOPSIGNAL SIGTERM

ENTRYPOINT ["/entrypoint.sh"]

CMD ["nginx", "-g", "daemon off;"]
