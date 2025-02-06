FROM nginx:1.27.4-alpine
LABEL version="2.0.0"

RUN apk -v --update add \
        curl \
        python3 \
        py-pip \
        jq \
    && pip install --upgrade pip awscli --break-system-packages \
    && apk -v --purge del py-pip \
    && rm /var/cache/apk/*

COPY configs/nginx /etc/nginx
COPY configs/*.sh /

EXPOSE 80

ENTRYPOINT ["/entrypoint.sh"]

CMD ["nginx", "-g", "daemon off;"]
