"""FastAPI-сервис распознавания причины плача младенца.

Эндпоинт ``POST /api/v1/predict-cry`` принимает короткую (~5 c) аудиозапись
(.wav / .m4a / .aac) от мобильного приложения, приводит её к 16 кГц моно PCM,
считает те же признаки, что и на обучении, и возвращает вероятности по классам
и рекомендацию на русском.

Модель загружается ОДИН раз при старте (событие lifespan) — это важно на слабом
VPS: держим один инстанс в памяти, а не читаем pkl на каждый запрос.

Декодирование входного аудио идёт через pydub → ffmpeg целиком в памяти
(BytesIO), без россыпи временных файлов на диске.
"""

from __future__ import annotations

import io
import os
from contextlib import asynccontextmanager
from pathlib import Path

import joblib
import numpy as np
from fastapi import FastAPI, File, HTTPException, UploadFile
from pydub import AudioSegment

# Пакет запускается как `uvicorn app.main:app` из корня сервиса, где лежат
# cry_features.py / cry_labels.py — поэтому импорт абсолютный.
from cry_features import FEATURE_VERSION, SAMPLE_RATE, extract_features
from cry_labels import CLASSES, recommendation_for

MODEL_PATH = Path(os.environ.get("MODEL_PATH", "model.pkl"))
MAX_UPLOAD_BYTES = 5 * 1024 * 1024  # 5 МБ — с запасом для 5-секундного клипа

# Загруженная модель и её метаданные (заполняется в lifespan).
STATE: dict[str, object] = {}


def _load_model() -> None:
    """Прочитать pkl и проверить совместимость версии признаков."""
    if not MODEL_PATH.exists():
        print(f"[!] Модель не найдена: {MODEL_PATH}. /predict-cry вернёт 503, пока не появится файл.")
        return
    bundle = joblib.load(MODEL_PATH)
    if bundle.get("feature_version") != FEATURE_VERSION:
        # Явная ошибка лучше тихого мусора: схема фич кода и модели разошлась.
        raise RuntimeError(
            f"feature_version модели ({bundle.get('feature_version')}) не совпадает с кодом "
            f"({FEATURE_VERSION}). Переобучите модель: python train.py"
        )
    STATE["model"] = bundle["model"]
    STATE["classes"] = list(bundle.get("classes") or CLASSES)
    STATE["accuracy"] = bundle.get("accuracy")
    print(f"Модель загружена: {MODEL_PATH} (классы: {STATE['classes']}, acc={STATE.get('accuracy')})")


@asynccontextmanager
async def lifespan(app: FastAPI):
    _load_model()
    yield
    STATE.clear()


app = FastAPI(title="Baby Cry Reason API", version="1.0.0", lifespan=lifespan)


def _decode_to_pcm(data: bytes) -> np.ndarray:
    """Любой аудиоформат (wav/m4a/aac) → float32 моно 16 кГц в диапазоне [-1, 1].

    pydub сам подберёт декодер через ffmpeg. Работаем целиком в памяти.
    """
    try:
        seg = AudioSegment.from_file(io.BytesIO(data))
    except Exception as exc:  # noqa: BLE001 - битый/неизвестный формат
        raise HTTPException(status_code=400, detail=f"Не удалось прочитать аудио: {exc}") from exc

    seg = seg.set_frame_rate(SAMPLE_RATE).set_channels(1).set_sample_width(2)  # 16-bit PCM
    samples = np.array(seg.get_array_of_samples(), dtype=np.float32)
    if samples.size == 0:
        raise HTTPException(status_code=400, detail="Пустая аудиозапись")
    return samples / 32768.0  # int16 → float [-1, 1]


@app.get("/health")
def health() -> dict:
    """Проверка живости + готова ли модель (для Docker healthcheck / балансировщика)."""
    return {"status": "ok", "model_loaded": "model" in STATE}


@app.post("/api/v1/predict-cry")
async def predict_cry(file: UploadFile = File(...)) -> dict:
    """Определить причину плача по загруженному аудио."""
    model = STATE.get("model")
    if model is None:
        raise HTTPException(status_code=503, detail="Модель ещё не обучена/не загружена")

    data = await file.read()
    if not data:
        raise HTTPException(status_code=400, detail="Пустой файл")
    if len(data) > MAX_UPLOAD_BYTES:
        raise HTTPException(status_code=413, detail="Файл слишком большой (макс. 5 МБ)")

    audio = _decode_to_pcm(data)
    features = extract_features(audio, SAMPLE_RATE).reshape(1, -1)

    classes: list[str] = STATE["classes"]  # type: ignore[assignment]
    proba = model.predict_proba(features)[0]  # type: ignore[union-attr]

    # Полное распределение по ВСЕМ известным классам (даже с нулём), в процентах.
    prob_by_class = {cls: 0 for cls in CLASSES}
    for cls, p in zip(classes, proba):
        prob_by_class[cls] = int(round(float(p) * 100))

    top_idx = int(np.argmax(proba))
    primary = classes[top_idx]
    confidence = round(float(proba[top_idx]), 4)

    return {
        "status": "success",
        "primary_reason": primary,
        "confidence": confidence,
        "probabilities": prob_by_class,
        "recommendation_ru": recommendation_for(primary),
    }
