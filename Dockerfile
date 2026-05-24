# ==================== 前端构建阶段 ====================
FROM oven/bun:1@sha256:0733e50325078969732ebe3b15ce4c4be5082f18c4ac1a0f0ca4839c2e4e42a7 AS builder
WORKDIR /build
COPY web/default/package.json web/default/bun.lock ./
RUN bun install --frozen-lockfile
COPY ./web/default .
COPY ./VERSION .
RUN DISABLE_ESLINT_PLUGIN='true' VITE_REACT_APP_VERSION=$(cat VERSION) bun run build

FROM oven/bun:1@sha256:0733e50325078969732ebe3b15ce4c4be5082f18c4ac1a0f0ca4839c2e4e42a7 AS builder-classic
WORKDIR /build
COPY web/classic/package.json web/classic/bun.lock ./
RUN bun install --frozen-lockfile
COPY ./web/classic .
COPY ./VERSION .
RUN VITE_REACT_APP_VERSION=$(cat VERSION) bun run build

# ==================== Go 编译阶段 ====================
FROM golang:1.26.1-alpine@sha256:2389ebfa5b7f43eeafbd6be0c3700cc46690ef842ad962f6c5bd6be49ed82039 AS builder2
ENV CGO_ENABLED=0 GO111MODULE=on
ARG TARGETOS TARGETARCH
ENV GOOS=${TARGETOS:-linux} GOARCH=${TARGETARCH:-amd64}

WORKDIR /build
ADD go.mod go.sum ./
RUN go mod download && go mod verify

COPY . .
COPY --from=builder /build/dist ./web/default/dist
COPY --from=builder-classic /build/dist ./web/classic/dist

# 先同步依赖，再编译（移除无效的 VERSION 注入）
RUN go mod tidy && \
    go build -ldflags="-s -w" -trimpath -o new-api

# ==================== 运行时镜像 ====================
FROM debian:bookworm-slim@sha256:f06537653ac770703bc45b4b113475bd402f451e85223f0f2837acbf89ab020a

# ✅ 仅保留 CA 证书与时区数据，移除 libasan8/wget
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates tzdata \
    && rm -rf /var/lib/apt/lists/* \
    && update-ca-certificates

# ✅ 创建非 root 用户运行，提升安全性
RUN groupadd -r appuser && useradd -r -g appuser -d /data -s /sbin/nologin appuser

COPY --from=builder2 /build/new-api /usr/local/bin/new-api
COPY LICENSE NOTICE THIRD-PARTY-LICENSES.md /licenses/

EXPOSE 3000
WORKDIR /data
USER appuser
ENTRYPOINT ["new-api"]
