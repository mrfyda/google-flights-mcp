# syntax=docker/dockerfile:1

# --- Build stage: compile TypeScript, then drop dev dependencies ---
FROM node:22-slim AS build
WORKDIR /app

# better-sqlite3 is a native module; install a toolchain in case no prebuilt
# binary is available for this platform/Node ABI.
RUN apt-get update \
 && apt-get install -y --no-install-recommends python3 make g++ \
 && rm -rf /var/lib/apt/lists/*

# package.json requires Node >=22.12.0 and .npmrc sets engine-strict=true,
# so the base image MUST be Node 22+.
COPY package.json package-lock.json .npmrc ./
RUN npm ci

COPY tsconfig.json tsup.config.ts ./
COPY src ./src
RUN npm run build && npm prune --omit=dev

# --- Runtime stage ---
FROM node:22-slim AS runtime
WORKDIR /app

ENV NODE_ENV=production
ENV PORT=3000

# Only the production dependencies and the build output are shipped.
COPY --from=build /app/package.json ./package.json
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist

# Price-tracking SQLite file. Ephemeral in this container; mount a disk at
# /data (or point GF_MCP_PRICE_DB_DIR elsewhere) to persist it.
RUN mkdir -p /data
ENV GF_MCP_PRICE_DB_DIR=/data

EXPOSE 3000

# --http starts the Streamable HTTP transport on $PORT at /mcp (and /health).
# Render also sets PORT, which alone triggers HTTP mode.
CMD ["node", "dist/index.js", "--http"]
