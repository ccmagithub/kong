FROM alpine:3.6
MAINTAINER Yee <yee@geminiopencloud.com>

RUN apk add --no-cache --virtual .build-deps ca-certificates \
	&& apk add --no-cache libgcc openssl pcre perl tzdata \
	&& apk del .build-deps

ADD Resources /Resources

RUN cp -R /Resources/usr / \
	&& cp -R /Resources/etc / \
	&& rm -rf /Resources

COPY docker-entrypoint.sh /docker-entrypoint.sh
ENTRYPOINT ["/docker-entrypoint.sh"]

EXPOSE 8000 8443 8001 8444

STOPSIGNAL SIGTERM

CMD ["/usr/local/openresty/nginx/sbin/nginx", "-c", "/usr/local/kong/nginx.conf", "-p", "/usr/local/kong/"]
