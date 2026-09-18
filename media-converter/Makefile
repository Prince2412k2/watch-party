.PHONY: build test run docker-build

build:
	go build -o bin/media-converter ./cmd/media-converter

test:
	go test ./...

run:
	go run ./cmd/media-converter serve

docker-build:
	docker build -t media-converter .
