FROM python:3.11-slim

# Install system dependencies including ffmpeg
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install python dependencies
COPY backend/requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir --root-user-action=ignore --upgrade pip && \
    pip install --no-cache-dir --root-user-action=ignore -r requirements.txt

# Copy application source code
COPY backend/ /app/backend/

ENV PYTHONUNBUFFERED=1
ENV PORT=10000

EXPOSE 10000

CMD ["gunicorn", "--chdir", "backend", "--bind", "0.0.0.0:10000", "--workers", "2", "--threads", "4", "--timeout", "300", "server:app"]
