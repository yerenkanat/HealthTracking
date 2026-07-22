# Umay · Cry Classifier

Лёгкий сервис распознавания причины плача младенца по короткой (~5 c)
аудиозаписи. Рассчитан на **обычный бюджетный VPS** (Ubuntu, 1–2 CPU, 2 ГБ RAM,
без GPU): признаки MFCC/спектральные + `RandomForest`, ответ — мгновенный.

Пять классов: `hungry`, `tired`, `belly_pain`, `discomfort`, `burping`.

## Структура

```
cry-classifier/
├── cry_features.py       # извлечение признаков — ОБЩЕЕ для обучения и API
├── cry_labels.py         # классы + рекомендации на русском
├── download_data.py      # скачать и разложить корпус Donate-a-Cry
├── train.py              # обучение RandomForest + метрики + model.pkl
├── app/
│   └── main.py           # FastAPI: POST /api/v1/predict-cry
├── requirements.txt
├── Dockerfile
└── docker-compose.yml
```

Ключевой инвариант: и `train.py`, и `app/main.py` считают признаки **одной и той
же** функцией `cry_features.extract_features`. В модель пишется `feature_version`,
и API откажется стартовать, если версия схемы признаков разошлась с кодом.

## 1. Данные

```bash
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt

python download_data.py --out data
```

Скрипт клонирует корпус **Donate-a-Cry** и раскладывает `.wav` по
`data/<class>/`. Имена папок-классов в корпусе совпадают с нашими метками.

> Baby Cry Sound Database (Kaggle) автоматически не тянется — у Kaggle нет
> анонимного прямого скачивания. Если он есть локально, просто доложите файлы в
> `data/<class>/`, `train.py` подхватит всё, что там лежит.

## 2. Обучение

```bash
python train.py --data data --out model.pkl
```

Что делает:
- извлекает MFCC + дельты + spectral centroid/bandwidth/rolloff + ZCR + chroma +
  RMS, агрегируя по времени (mean/std) в фиксированный вектор;
- аугментирует **только train** (белый шум / pitch shift / сдвиг по времени);
- обучает `RandomForestClassifier(class_weight="balanced")` — корпус перекошен
  (класс `hungry` преобладает), баланс это компенсирует;
- печатает Accuracy, per-class отчёт и confusion matrix;
- сохраняет `model.pkl` (модель + метаданные).

Полезные флаги: `--trees 500`, `--test-size 0.25`, `--no-augment`.

## 3. Локальный запуск API

```bash
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

Проверка:

```bash
curl -F "file=@sample.m4a" http://localhost:8000/api/v1/predict-cry
```

Ответ:

```json
{
  "status": "success",
  "primary_reason": "hungry",
  "confidence": 0.84,
  "probabilities": { "hungry": 84, "tired": 10, "belly_pain": 4, "discomfort": 2, "burping": 0 },
  "recommendation_ru": "Малыш, скорее всего, проголодался. Попробуйте покормить."
}
```

Есть `GET /health` — для healthcheck/балансировщика (`{"status":"ok","model_loaded":true}`).

Принимает `.wav`, `.m4a`, `.aac` — pydub через ffmpeg приводит к 16 кГц моно PCM
целиком в памяти (без временных файлов).

## 4. Деплой на VPS (Docker)

Модель `model.pkl` **монтируется томом**, а не вшивается в образ — можно
переобучать без пересборки.

```bash
# на VPS, в папке сервиса, где уже лежит обученный model.pkl
docker compose up -d --build
docker compose logs -f          # "Модель загружена: ..."
curl -F "file=@sample.wav" http://localhost:8000/api/v1/predict-cry
```

Образ на базе `python:3.10-slim` (не alpine — так ставятся готовые колёса
librosa/scipy/sklearn без компиляции), ставит системный `ffmpeg` и `libsndfile1`.
`mem_limit: 1500m` держит сервис в рамках 2 ГБ.

## Интеграция с приложением Flutter

Мобильный клиент пишет ~5-секундный клип и шлёт его `multipart/form-data` полем
`file` на `POST /api/v1/predict-cry`, затем показывает `primary_reason`,
столбики из `probabilities` и `recommendation_ru`.

## Альтернатива: CNN (Опция А)

Для 2 ГБ RAM по умолчанию выбран RandomForest — быстрее и легче. Если позже
захотите CNN: замените вектор в `cry_features.py` на 2D мел-спектрограмму
(`librosa.feature.melspectrogram` → `power_to_db`, фикс. форма, напр. 64×157),
обучите компактную 2D-CNN (2–3 conv-блока) на PyTorch/TF, сохраните веса, и в
`app/main.py` подмените `predict_proba` на прогон через сеть. Контракт REST при
этом не меняется. На слабом CPU инференс будет медленнее RF, но выполним.

## Дисклеймер

Это вспомогательная подсказка для родителей, а не медицинский диагноз. При
устойчивом беспокойстве, повышенной температуре или других тревожных признаках —
обращайтесь к педиатру.
