FROM alpine

RUN apk --no-cache add git jq bash coreutils git-lfs gnupg
RUN mkdir /data
COPY data /data
COPY src/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
