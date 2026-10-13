# Builds localhost/geoip_generator: haproxy-mapper plus geoip_generator.py.
# Built by build.sh, which pins the base images by digest and haproxy-mapper by commit.
# Ref: https://github.com/babraham123/haproxy-mapper

ARG GO_IMAGE=docker.io/library/golang:1-alpine
ARG PY_IMAGE=docker.io/library/python:3-alpine

FROM ${GO_IMAGE} AS mapper
ARG MAPPER_REF=main
WORKDIR /src
RUN wget -qO- "https://github.com/babraham123/haproxy-mapper/archive/${MAPPER_REF}.tar.gz" | \
      tar xz --strip-components=1 && \
    go mod tidy && \
    CGO_ENABLED=0 go build -ldflags="-s -w" -o /haproxy-mapper .

FROM ${PY_IMAGE}
COPY --from=mapper /haproxy-mapper /usr/local/bin/haproxy-mapper
COPY geoip_generator.py /usr/local/bin/geoip_generator.py
ENTRYPOINT ["python3", "/usr/local/bin/geoip_generator.py"]
