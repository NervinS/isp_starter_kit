# ---------- Base ----------
FROM node:20-alpine AS base
WORKDIR /app
RUN apk add --no-cache bash tini

# ---------- Deps (instala TODAS las deps, incluidas dev, para poder compilar) ----------
FROM base AS deps
WORKDIR /app
COPY package.json package-lock.json ./
# npm ci usa el package-lock.json; si cambiaste package.json, regenera el lock en tu host.
RUN npm ci

# ---------- Build (usa deps ya instaladas) ----------
FROM deps AS build
WORKDIR /app
COPY tsconfig*.json ./
COPY src ./src
# Deja un rastro con la versión de tsc y compila
RUN rm -rf dist && npx tsc -v && npm run build

# ---------- Runtime (solo prod) ----------
FROM node:20-alpine AS runtime
WORKDIR /app
RUN apk add --no-cache tini
ENV NODE_ENV=production \
    PORT=3000
EXPOSE 3000

# Solo dependencias de producción en la imagen final
COPY package.json package-lock.json ./
RUN npm ci --omit=dev

# Copiamos el build
COPY --from=build /app/dist ./dist

# Entrypoint limpio con tini
ENTRYPOINT ["/sbin/tini","--"]
CMD ["node","dist/main.js"]
