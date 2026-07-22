# Лёгкий образ под обычный VPS. Берём python:3.10-slim (НЕ alpine): у librosa /
# scipy / scikit-learn есть готовые manylinux-колёса под slim, а под alpine их
# пришлось бы компилировать — это долгая сборка и лишние сотни МБ инструментов.
FROM python:3.10-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1

# ffmpeg — чтобы pydub читал .m4a/.aac с телефонов; libsndfile1 — для soundfile.
RUN apt-get update \
    && apt-get install -y --no-install-recommends ffmpeg libsndfile1 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Сначала зависимости — слой кэшируется, пока не менялся requirements.txt.
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Затем код. Модель НЕ копируем в образ — она монтируется томом (см.
# docker-compose.yml), чтобы переобучать без пересборки контейнера.
COPY cry_features.py cry_labels.py ./
COPY app ./app

ENV MODEL_PATH=/app/model.pkl

EXPOSE 8000

# Один воркер: на 2 ГБ RAM держим единственный инстанс модели в памяти.
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1"]
