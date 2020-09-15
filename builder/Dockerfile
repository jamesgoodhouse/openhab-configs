ARG ALPINE_VERSION=3.12
ARG GOMPLATE_VERSION=3.8.0

################################################################################

# would skip this but COPY --from doesn't do interpolation of ARGs
FROM hairyhenderson/gomplate:v${GOMPLATE_VERSION}-slim as gomplate

################################################################################

FROM alpine:${ALPINE_VERSION}
RUN apk add --no-cache bash git less openssh rsync
COPY entrypoint.sh /entrypoint.sh
COPY --from=gomplate /gomplate /usr/local/bin/gomplate
ENTRYPOINT ["/entrypoint.sh"]
