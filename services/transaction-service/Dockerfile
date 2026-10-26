# CK-01 — Upgraded to python:3.12-slim, pinned by digest, and patched OS packages
FROM python:3.12-slim@sha256:7a8b475003c4fe15a2cd4e55e5cfc2f3560bdc9333d624f24cdd6d4340fd7a17

WORKDIR /app

RUN apt-get update && \
    apt-get dist-upgrade -y --no-install-recommends && \
    rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip setuptools wheel && \
    pip install --no-cache-dir -r requirements.txt

COPY app.py .

RUN groupadd -r appgroup && \
    useradd -r -g appgroup -d /app -s /sbin/nologin appuser && \
    chown -R appuser:appgroup /app

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:5002/health')" || exit 1

# CK-02 & IV-05 — Enforce non-root USER directive
USER appuser

EXPOSE 5002
CMD ["python", "app.py"]