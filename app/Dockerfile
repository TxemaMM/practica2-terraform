FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

RUN useradd --system --no-create-home --uid 10001 appuser
COPY --chown=appuser:appuser . .
USER appuser

EXPOSE 5000

CMD ["sh", "-c", "exec gunicorn --bind 0.0.0.0:5000 --workers ${GUNICORN_WORKERS:-2} --threads ${GUNICORN_THREADS:-4} --access-logfile - main:app"]