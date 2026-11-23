# API image: builds apps/api with tsup and runs apps/api/dist/index.js.
# Storage is Postgres via DATABASE_URL (see docker-compose.yml).

FROM node:22-slim AS build
WORKDIR /app

# Workspace manifests first so `npm ci` is cached until dependencies change.
COPY package.json package-lock.json ./
COPY apps/api/package.json ./apps/api/
COPY packages/shared/package.json ./packages/shared/
RUN npm ci --workspace @edtech/api --include-workspace-root

COPY apps/api ./apps/api
COPY packages/shared ./packages/shared
RUN npm run build:api

FROM node:22-slim AS runtime
WORKDIR /app
ENV NODE_ENV=production
ENV PORT=4000
ENV HOST=0.0.0.0

COPY package.json package-lock.json ./
COPY apps/api/package.json ./apps/api/
COPY packages/shared/package.json ./packages/shared/
RUN npm ci --omit=dev --workspace @edtech/api --include-workspace-root \
  && npm cache clean --force

COPY --from=build /app/apps/api/dist ./apps/api/dist

EXPOSE 4000
USER node
CMD ["node", "apps/api/dist/index.js"]
