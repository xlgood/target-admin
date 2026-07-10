# syntax=docker/dockerfile:1

FROM node:20-alpine AS builder

WORKDIR /app

RUN corepack enable

COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile

COPY . .

ARG VITE_API_BASE_URL=""
ARG VITE_ADMIN_PATH=""
ENV VITE_API_BASE_URL=${VITE_API_BASE_URL}
ENV VITE_ADMIN_PATH=${VITE_ADMIN_PATH}

RUN pnpm run build

FROM nginx:1.27-alpine

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=builder /app/dist /usr/share/nginx/html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
