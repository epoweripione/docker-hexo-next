FROM node:alpine

LABEL Maintainer="Ansley Leung" \
      Description="Hexo with theme NexT: Auto generate and deploy website use GITHUB webhook" \
      License="MIT License" \
      Version="11.10.0"

ENV TZ=Asia/Shanghai
RUN set -ex && \
    ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && \
    echo $TZ > /etc/timezone


# nginx
# TLS1.3: https://github.com/khs1994-website/tls-1.3
#         https://github.com/angristan/nginx-autoinstall
# mainline: https://github.com/nginxinc/docker-nginx/tree/master/mainline/alpine
ENV NGINX_VERSION 1.15.8

RUN GPG_KEYS=B0F4253373F8F6F510D42178520A9993A1C052F8 \
	&& CONFIG="\
		--prefix=/etc/nginx \
		--sbin-path=/usr/sbin/nginx \
		--modules-path=/usr/lib/nginx/modules \
		--conf-path=/etc/nginx/nginx.conf \
		--error-log-path=/var/log/nginx/error.log \
		--http-log-path=/var/log/nginx/access.log \
		--pid-path=/var/run/nginx.pid \
		--lock-path=/var/run/nginx.lock \
		--http-client-body-temp-path=/var/cache/nginx/client_temp \
		--http-proxy-temp-path=/var/cache/nginx/proxy_temp \
		--http-fastcgi-temp-path=/var/cache/nginx/fastcgi_temp \
		--http-uwsgi-temp-path=/var/cache/nginx/uwsgi_temp \
		--http-scgi-temp-path=/var/cache/nginx/scgi_temp \
		--user=nginx \
		--group=nginx \
		--with-http_ssl_module \
		--with-http_realip_module \
		--with-http_addition_module \
		--with-http_sub_module \
		--with-http_dav_module \
		--with-http_flv_module \
		--with-http_mp4_module \
		--with-http_gunzip_module \
		--with-http_gzip_static_module \
		--with-http_random_index_module \
		--with-http_secure_link_module \
		--with-http_stub_status_module \
		--with-http_auth_request_module \
		--with-http_xslt_module=dynamic \
		--with-http_image_filter_module=dynamic \
		--with-http_geoip_module=dynamic \
		--with-threads \
		--with-stream \
		--with-stream_ssl_module \
		--with-stream_ssl_preread_module \
		--with-stream_realip_module \
		--with-stream_geoip_module=dynamic \
		--with-http_slice_module \
		--with-mail \
		--with-mail_ssl_module \
		--with-compat \
		--with-file-aio \
		--with-http_v2_module \
	" \
	&& addgroup -S nginx \
	&& adduser -D -S -h /var/cache/nginx -s /sbin/nologin -G nginx nginx \
	&& apk add --no-cache --virtual .build-deps \
		gcc \
		libc-dev \
		make \
		openssl-dev \
		pcre-dev \
		zlib-dev \
		linux-headers \
		curl \
		gnupg1 \
		libxslt-dev \
		gd-dev \
		geoip-dev \
	&& curl -fSL https://nginx.org/download/nginx-$NGINX_VERSION.tar.gz -o nginx.tar.gz \
	&& curl -fSL https://nginx.org/download/nginx-$NGINX_VERSION.tar.gz.asc -o nginx.tar.gz.asc \
	&& export GNUPGHOME="$(mktemp -d)" \
	&& found=''; \
	for server in \
		ha.pool.sks-keyservers.net \
		hkp://keyserver.ubuntu.com:80 \
		hkp://p80.pool.sks-keyservers.net:80 \
		pgp.mit.edu \
	; do \
		echo "Fetching GPG key $GPG_KEYS from $server"; \
		gpg --keyserver "$server" --keyserver-options timeout=10 --recv-keys "$GPG_KEYS" && found=yes && break; \
	done; \
	test -z "$found" && echo >&2 "error: failed to fetch GPG key $GPG_KEYS" && exit 1; \
	gpg --batch --verify nginx.tar.gz.asc nginx.tar.gz \
	&& rm -rf "$GNUPGHOME" nginx.tar.gz.asc \
	&& mkdir -p /usr/src \
	&& tar -zxC /usr/src -f nginx.tar.gz \
	&& rm nginx.tar.gz \
	&& cd /usr/src/nginx-$NGINX_VERSION \
	&& ./configure $CONFIG --with-debug \
	&& make -j$(getconf _NPROCESSORS_ONLN) \
	&& mv objs/nginx objs/nginx-debug \
	&& mv objs/ngx_http_xslt_filter_module.so objs/ngx_http_xslt_filter_module-debug.so \
	&& mv objs/ngx_http_image_filter_module.so objs/ngx_http_image_filter_module-debug.so \
	&& mv objs/ngx_http_geoip_module.so objs/ngx_http_geoip_module-debug.so \
	&& mv objs/ngx_stream_geoip_module.so objs/ngx_stream_geoip_module-debug.so \
	&& ./configure $CONFIG \
	&& make -j$(getconf _NPROCESSORS_ONLN) \
	&& make install \
	&& rm -rf /etc/nginx/html/ \
	&& mkdir /etc/nginx/conf.d/ \
	&& mkdir -p /usr/share/nginx/html/ \
	&& install -m644 html/index.html /usr/share/nginx/html/ \
	&& install -m644 html/50x.html /usr/share/nginx/html/ \
	&& install -m755 objs/nginx-debug /usr/sbin/nginx-debug \
	&& install -m755 objs/ngx_http_xslt_filter_module-debug.so /usr/lib/nginx/modules/ngx_http_xslt_filter_module-debug.so \
	&& install -m755 objs/ngx_http_image_filter_module-debug.so /usr/lib/nginx/modules/ngx_http_image_filter_module-debug.so \
	&& install -m755 objs/ngx_http_geoip_module-debug.so /usr/lib/nginx/modules/ngx_http_geoip_module-debug.so \
	&& install -m755 objs/ngx_stream_geoip_module-debug.so /usr/lib/nginx/modules/ngx_stream_geoip_module-debug.so \
	&& ln -s ../../usr/lib/nginx/modules /etc/nginx/modules \
	&& strip /usr/sbin/nginx* \
	&& strip /usr/lib/nginx/modules/*.so \
	&& rm -rf /usr/src/nginx-$NGINX_VERSION \
	\
	# Bring in gettext so we can get `envsubst`, then throw
	# the rest away. To do this, we need to install `gettext`
	# then move `envsubst` out of the way so `gettext` can
	# be deleted completely, then move `envsubst` back.
	&& apk add --no-cache --virtual .gettext gettext \
	&& mv /usr/bin/envsubst /tmp/ \
	\
	&& runDeps="$( \
		scanelf --needed --nobanner --format '%n#p' /usr/sbin/nginx /usr/lib/nginx/modules/*.so /tmp/envsubst \
			| tr ',' '\n' \
			| sort -u \
			| awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
	)" \
	&& apk add --no-cache --virtual .nginx-rundeps $runDeps \
	&& apk del .build-deps \
	&& apk del .gettext \
	&& mv /tmp/envsubst /usr/local/bin/ \
	\
	# Bring in tzdata so users could set the timezones through the environment
	# variables
	&& apk add --no-cache tzdata \
	\
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
# ENV VERSION=v11.5.0 NPM_VERSION=6 YARN_VERSION=latest

# # For base builds
# ENV CONFIG_FLAGS="--fully-static --without-npm" DEL_PKGS="libstdc++" RM_DIRS=/usr/include

# RUN apk add --no-cache curl make gcc g++ python linux-headers binutils-gold gnupg libstdc++ && \
#     for server in ipv4.pool.sks-keyservers.net keyserver.pgp.com ha.pool.sks-keyservers.net; do \
#         gpg --keyserver $server --recv-keys \
#         94AE36675C464D64BAFA68DD7434390BDBE9B9C5 \
#         B9AE9905FFD7803F25714661B63B535A4C206CA9 \
#         77984A986EBC2AA786BC0F66B01FBB92821C587A \
#         71DCFD284A79C3B38668286BC97EC7A07EDE3FC1 \
#         FD3A5288F042B6850C66B31F09FE44734EB7990E \
#         8FCCA13FEF1D0C2E91008E09770F7A9A5AE15600 \
#         C4F0DFFF4E8C1A8236409D08E73BC641CC11F4C8 \
#         DD8F2338BAE7501E3DD5AC78C273792F7D83545D && break; \
#     done && \
#     curl -sfSLO https://nodejs.org/dist/${VERSION}/node-${VERSION}.tar.xz && \
#     curl -sfSL https://nodejs.org/dist/${VERSION}/SHASUMS256.txt.asc | gpg --batch --decrypt | \
#         grep " node-${VERSION}.tar.xz\$" | sha256sum -c | grep ': OK$' && \
#     tar -xf node-${VERSION}.tar.xz && \
#     cd node-${VERSION} && \
#     ./configure --prefix=/usr ${CONFIG_FLAGS} && \
#     make -j$(getconf _NPROCESSORS_ONLN) && \
#     make install && \
#     cd / && \
#     if [ -z "$CONFIG_FLAGS" ]; then \
#         if [ -n "$NPM_VERSION" ]; then \
#             npm install -g npm@${NPM_VERSION}; \
#         fi; \
#         find /usr/lib/node_modules/npm -name test -o -name .bin -type d | xargs rm -rf; \
#         if [ -n "$YARN_VERSION" ]; then \
#             for server in ipv4.pool.sks-keyservers.net keyserver.pgp.com ha.pool.sks-keyservers.net; do \
#                 gpg --keyserver $server --recv-keys \
#                     6A010C5166006599AA17F08146C2130DFD2497F5 && break; \
#             done && \
#             curl -sfSL -O https://yarnpkg.com/${YARN_VERSION}.tar.gz -O https://yarnpkg.com/${YARN_VERSION}.tar.gz.asc && \
#             gpg --batch --verify ${YARN_VERSION}.tar.gz.asc ${YARN_VERSION}.tar.gz && \
#             mkdir /usr/local/share/yarn && \
#             tar -xf ${YARN_VERSION}.tar.gz -C /usr/local/share/yarn --strip 1 && \
#             ln -s /usr/local/share/yarn/bin/yarn /usr/local/bin/ && \
#             ln -s /usr/local/share/yarn/bin/yarnpkg /usr/local/bin/ && \
#             rm ${YARN_VERSION}.tar.gz*; \
#         fi; \
#     fi && \
#     apk del curl make gcc g++ python linux-headers binutils-gold gnupg ${DEL_PKGS} && \
#     rm -rf ${RM_DIRS} /node-${VERSION}* /usr/share/man /tmp/* /var/cache/apk/* \
#         /root/.npm /root/.node-gyp /root/.gnupg /usr/lib/node_modules/npm/man \
#         /usr/lib/node_modules/npm/doc /usr/lib/node_modules/npm/html /usr/lib/node_modules/npm/scripts


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
    git clone https://github.com/theme-next/theme-next-canvas-ribbon themes/next/source/lib/canvas-ribbon

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
    apk add --update coreutils && \
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
