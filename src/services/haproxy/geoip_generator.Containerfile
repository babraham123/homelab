# Builds localhost/geoip_generator: haproxy-mapper plus geoip_generator.py.
# Usage (context src/services/haproxy, as install_svcs.sh geoip_generator does):
#   podman build -t geoip_generator -f geoip_generator.Containerfile .
# Ref: https://github.com/babraham123/haproxy-mapper

FROM docker.io/library/golang:1-alpine AS mapper
WORKDIR /src
RUN wget -qO- https://github.com/babraham123/haproxy-mapper/archive/refs/heads/main.tar.gz | \
      tar xz --strip-components=1 && \
    go mod tidy && \
    CGO_ENABLED=0 go build -ldflags="-s -w" -o /haproxy-mapper .

FROM docker.io/library/python:3-alpine
COPY --from=mapper /haproxy-mapper /usr/local/bin/haproxy-mapper
COPY geoip_generator.py /usr/local/bin/geoip_generator.py
ENTRYPOINT ["python3", "/usr/local/bin/geoip_generator.py"]
