ARG ENABLE_PROXY=true

FROM openresty/openresty:1.19.3.1-alpine-fat AS production-stage
COPY rockspec/gw-0.1-0.rockspec .
ARG ENABLE_PROXY=true
RUN set -x \
    && (test "${ENABLE_PROXY}" != "true" || /bin/sed -i 's,https://dl-cdn.alpinelinux.org,https://mirrors.aliyun.com,g' /etc/apk/repositories) \
    && apk add --no-cache --virtual .builddeps \
    automake \
    autoconf \
    libtool \
    pkgconfig \
    cmake \
    git \
    && mkdir ~/.luarocks \
    && luarocks config variables.OPENSSL_LIBDIR /usr/local/openresty/openssl/lib \
    && luarocks config variables.OPENSSL_INCDIR /usr/local/openresty/openssl/include \
    && luarocks install gw-0.1-0.rockspec --tree=/usr/local/gw/deps \
    && cp -v /usr/local/gw/deps/lib/luarocks/rocks-5.1/gw/0.1-0/bin/gw /usr/bin/ \
    && mv /usr/local/gw/deps/share/lua/5.1/gw /usr/local/gw \
    && apk del .builddeps build-base make unzip

FROM alpine:3.13 AS last-stage

ARG ENABLE_PROXY=true
# add runtime for  gw
RUN set -x \
    && (test "${ENABLE_PROXY}" != "true" || /bin/sed -i 's,https://dl-cdn.alpinelinux.org,https://mirrors.aliyun.com,g' /etc/apk/repositories) \
    && apk add --no-cache bash libstdc++ curl tzdata

WORKDIR /usr/local/gw

COPY --from=production-stage /usr/local/openresty/ /usr/local/openresty/
COPY --from=production-stage /usr/local/gw/ /usr/local/gw/
COPY --from=production-stage /usr/bin/gw /usr/bin/gw

# forward request and error logs to docker log collector
RUN ln -sf /dev/stdout /usr/local/gw/logs/access.log \
    && ln -sf /dev/stderr /usr/local/gw/logs/error.log

ENV PATH=$PATH:/usr/local/openresty/luajit/bin:/usr/local/openresty/nginx/sbin:/usr/local/openresty/bin

EXPOSE 8080
EXPOSE 8443

CMD ["sh", "-c", "/usr/local/openresty/bin/openresty -p /usr/local/gw -g 'daemon off;'"]

STOPSIGNAL SIGQUIT
