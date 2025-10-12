# ---------- Base ----------
FROM node:20-alpine AS base
WORKDIR /app
RUN apk add --no-cache bash tini

# ---------- Deps ----------
FROM base AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci

# ---------- Build ----------
FROM deps AS build
WORKDIR /app
COPY tsconfig*.json ./
COPY src ./src
RUN rm -rf dist && npx tsc -v && npm run build

# ---------- Runtime ----------
FROM node:20-alpine AS runtime
WORKDIR /app
RUN apk add --no-cache tini
ENV NODE_ENV=production \
    PORT=3000
EXPOSE 3000

COPY package.json package-lock.json ./
RUN npm ci --omit=dev

COPY --from=build /app/dist ./dist

ENTRYPOINT ["/sbin/tini","--"]
CMD ["node","dist/main.js"]
