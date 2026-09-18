# syntax=docker/dockerfile:1
FROM golang:1.23-alpine AS builder
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/media-converter ./cmd/media-converter

FROM alpine:3.21
RUN apk add --no-cache ca-certificates ffmpeg shadow su-exec tzdata \
    && addgroup -g 1000 media \
    && adduser -D -u 1000 -G media media
COPY --from=builder /out/media-converter /usr/local/bin/media-converter
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod 0755 /usr/local/bin/docker-entrypoint.sh
VOLUME ["/data"]
ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["media-converter", "serve"]
