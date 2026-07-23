# syntax=docker/dockerfile:1
# Multi-stage production image for the VitePress wiki.
# Build: Node 22 — Runtime: Caddy (static site + cleanUrls).

FROM node:22-alpine AS build

# vitepress lastUpdated shells out to git
RUN apk add --no-cache git

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY docs ./docs
RUN npm run docs:build

FROM caddy:2.10-alpine

COPY --from=build /app/docs/.vitepress/dist /usr/share/caddy
COPY deploy/Caddyfile /etc/caddy/Caddyfile

EXPOSE 80

# BusyBox wget is present on the Alpine base image.
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -q -O /dev/null http://127.0.0.1:80/ || exit 1
