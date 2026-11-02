# Fly.io image: released oscore-server + SmartParcel extension layer baked in.
ARG OSCORE_SERVER_VERSION=0.1.0-preview.2
FROM ghcr.io/joncloud-dev/oscore-server:${OSCORE_SERVER_VERSION}

COPY pb_hooks /pb_hooks
COPY pb_migrations /pb_migrations
COPY pb_public /pb_public

ENV PGPS_DISABLE=1
