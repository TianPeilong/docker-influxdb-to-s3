FROM influxdb:1.7.6-alpine
MAINTAINER Tian Peilong <tianpl@4dbim.ren>

# Install system dependancies
RUN apk add --no-cache bash py-pip && rm -rf /var/cache/apk/*

COPY influxdb-backup.sh /usr/bin/influxdb-backup

ENTRYPOINT ["/usr/bin/influxdb-backup"]
CMD ["backup"]