ARG ENABLE_PROXY=true

FROM openresty/openresty:1.19.3.1-alpine-fat AS production-stage
COPY rockspec/ztgw-0.2-0.rockspec .
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
    && luarocks install ztgw-0.2-0.rockspec --tree=/usr/local/ztgw/deps \
    && cp -v /usr/local/ztgw/deps/lib/luarocks/rocks-5.1/ztgw/0.2-0/bin/ztgw /usr/bin/ \
    && mv /usr/local/ztgw/deps/share/lua/5.1/ztgw /usr/local/ztgw \
    && apk del .builddeps build-base make unzip

FROM alpine:3.13 AS last-stage

ARG ENABLE_PROXY=true
# add runtime for  ztgw
RUN set -x \
    && (test "${ENABLE_PROXY}" != "true" || /bin/sed -i 's,https://dl-cdn.alpinelinux.org,https://mirrors.aliyun.com,g' /etc/apk/repositories) \
    && apk add --no-cache bash libstdc++ curl tzdata

WORKDIR /usr/local/ztgw

COPY --from=production-stage /usr/local/openresty/ /usr/local/openresty/
COPY --from=production-stage /usr/local/ztgw/ /usr/local/ztgw/
COPY --from=production-stage /usr/bin/ztgw /usr/bin/ztgw

# forward request and error logs to docker log collector
RUN ln -sf /dev/stdout /usr/local/ztgw/logs/access.log \
    && ln -sf /dev/stderr /usr/local/ztgw/logs/error.log

ENV PATH=$PATH:/usr/local/openresty/luajit/bin:/usr/local/openresty/nginx/sbin:/usr/local/openresty/bin

EXPOSE 8080
EXPOSE 8443

CMD ["sh", "-c", "/usr/local/openresty/bin/openresty -p /usr/local/ztgw -g 'daemon off;'"]

STOPSIGNAL SIGQUIT
