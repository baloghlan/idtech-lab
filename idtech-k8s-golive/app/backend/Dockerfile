FROM docker.io/library/python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

RUN groupadd --system appgroup \
    && useradd --system --gid appgroup --create-home appuser

COPY requirements.txt .

RUN pip install --no-cache-dir -r requirements.txt

COPY --chown=appuser:appgroup app.py .

USER appuser

EXPOSE 5000

CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "1", "--threads", "4", "app:app"]