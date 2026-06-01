# The otel-contrib image is distroless — no shell, curl, or wget — so a Docker
# HEALTHCHECK has nothing to probe with. Pull in a single static busybox binary
# purely so the healthcheck (see docker-compose.yml) can wget the :13133
# health_check endpoint. This lets restart: unless-stopped catch a HUNG
# collector, not just a dead process.
FROM busybox:1.36-musl AS probe

FROM otel/opentelemetry-collector-contrib:0.120.0

COPY --from=probe /bin/busybox /bin/busybox
COPY config.yaml /etc/otelcol-contrib/config.yaml

EXPOSE 4317 4318 13133

CMD ["--config=/etc/otelcol-contrib/config.yaml"]
