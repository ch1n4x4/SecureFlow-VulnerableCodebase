# CK-01 — Upgraded to python:3.12-slim and pinned by digest
FROM python:3.12-slim@sha256:7a8b475003c4fe15a2cd4e55e5cfc2f3560bdc9333d624f24cdd6d4340fd7a17

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

# Create a non-root user and group, then change ownership of the working directory
RUN groupadd -r appgroup && \
    useradd -r -g appgroup -d /app -s /sbin/nologin appuser && \
    chown -R appuser:appgroup /app

# Added HEALTHCHECK for the application on port 5000
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:5000/health')" || exit 1

# CK-02 & IV-05 — Enforce the non-root USER directive
USER appuser

EXPOSE 5000

CMD ["python", "app.py"]