# Upgraded from python:3.9-slim to 3.12-slim and pinned the SHA256 digest
FROM python:3.12-slim@sha256:2c941e860699f878900b0edc2403613c234d4b32eda3cc9fa7036991a2a63c4a

# Install curl for the HEALTHCHECK command
RUN apt-get update && apt-get upgrade -y && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

# Address CK-02 / IV-05: Create a non-root user, change ownership, and switch to it
RUN groupadd -r appuser && useradd -r -g appuser appuser \
    && chown -R appuser:appuser /app
    
USER appuser

# Address missing HEALTHCHECK: Ping the app to ensure it is running successfully
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:5001/health || exit 1

EXPOSE 5001

CMD ["python", "app.py"]