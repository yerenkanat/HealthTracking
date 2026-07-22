"""Извлечение аудио-признаков — ОБЩИЙ модуль для обучения и инференса.

Критично: train.py и app/main.py используют РОВНО одну и ту же функцию
``extract_features``. Если признаки на обучении и на инференсе будут считаться
по-разному, модель на проде будет тихо ошибаться. Поэтому вся логика фич живёт
здесь, в одном месте.

Подход — «Опция Б» из ТЗ: агрегированные MFCC + их дельты + набор спектральных
признаков (centroid, bandwidth, rolloff, ZCR, chroma, RMS). Каждый признак
усредняется по времени (mean) и берётся его разброс (std), что даёт
фиксированный по длине вектор независимо от длительности записи. Это быстро,
почти не ест память и отлично заходит в RandomForest / XGBoost на слабом VPS.
"""

from __future__ import annotations

import io
from typing import Union

import numpy as np

try:
    import librosa
except ImportError as exc:  # pragma: no cover - подсказка при отсутствии зависимости
    raise ImportError(
        "librosa не установлен. Установите зависимости: pip install -r requirements.txt"
    ) from exc


# Единые параметры пайплайна. МЕНЯТЬ ТОЛЬКО ВМЕСТЕ с переобучением модели —
# иначе длина/смысл вектора признаков разъедется с сохранёнными весами.
SAMPLE_RATE = 16_000  # 16 кГц моно — стандарт для речи/детского плача
DURATION_SEC = 5.0  # анализируем ровно 5 секунд (ТЗ)
N_MFCC = 40
FEATURE_VERSION = 1  # версия схемы фич; пишется в модель, сверяется при загрузке

AudioSource = Union[str, bytes, bytearray, io.BytesIO]


def load_audio(source: AudioSource, sr: int = SAMPLE_RATE) -> np.ndarray:
    """Загрузить аудио как float32-моно с частотой ``sr``.

    ``source`` — путь к файлу или сырые байты (например, uploaded .wav). Для
    .m4a/.aac из мобильного приложения байты сначала декодируются во фронтенде
    API через pydub/ffmpeg (см. app/main.py), сюда уже приходит PCM.
    """
    if isinstance(source, (bytes, bytearray)):
        source = io.BytesIO(source)
    y, _ = librosa.load(source, sr=sr, mono=True)
    return y.astype(np.float32)


def fix_length(y: np.ndarray, sr: int = SAMPLE_RATE, duration: float = DURATION_SEC) -> np.ndarray:
    """Привести сигнал ровно к ``duration`` секундам: короткий — дополнить нулями,
    длинный — обрезать. Так вектор признаков всегда стабилен."""
    target = int(sr * duration)
    if len(y) < target:
        return np.pad(y, (0, target - len(y)))
    return y[:target]


def _normalize(y: np.ndarray) -> np.ndarray:
    """Пиковая нормализация — убирает разницу в громкости между записями."""
    peak = np.max(np.abs(y)) if y.size else 0.0
    return y / peak if peak > 0 else y


def extract_features(y: np.ndarray, sr: int = SAMPLE_RATE) -> np.ndarray:
    """Аудио → фиксированный вектор признаков (float32).

    Для каждого набора коэффициентов берём среднее и стандартное отклонение по
    оси времени и склеиваем всё в один вектор.
    """
    y = _normalize(fix_length(y, sr))

    mfcc = librosa.feature.mfcc(y=y, sr=sr, n_mfcc=N_MFCC)
    delta1 = librosa.feature.delta(mfcc)
    delta2 = librosa.feature.delta(mfcc, order=2)
    centroid = librosa.feature.spectral_centroid(y=y, sr=sr)
    bandwidth = librosa.feature.spectral_bandwidth(y=y, sr=sr)
    rolloff = librosa.feature.spectral_rolloff(y=y, sr=sr)
    zcr = librosa.feature.zero_crossing_rate(y)
    chroma = librosa.feature.chroma_stft(y=y, sr=sr)
    rms = librosa.feature.rms(y=y)

    blocks = [mfcc, delta1, delta2, centroid, bandwidth, rolloff, zcr, chroma, rms]
    parts: list[np.ndarray] = []
    for block in blocks:
        parts.append(np.mean(block, axis=1))
        parts.append(np.std(block, axis=1))
    return np.concatenate(parts).astype(np.float32)


def feature_length() -> int:
    """Длина вектора признаков (для sanity-check при загрузке модели)."""
    silent = np.zeros(int(SAMPLE_RATE * DURATION_SEC), dtype=np.float32)
    return int(extract_features(silent).shape[0])


# --------------------------------------------------------------------------- #
# Аугментация — применяется ТОЛЬКО к обучающей выборке (см. train.py), чтобы
# увеличить объём данных и устойчивость модели. На инференсе не используется.
# --------------------------------------------------------------------------- #
def augmentations(y: np.ndarray, sr: int, rng: np.random.Generator) -> list[np.ndarray]:
    """Вернуть список аугментированных копий сигнала (без оригинала).

    Три дешёвых приёма из ТЗ: белый шум, сдвиг тональности (pitch shift) и сдвиг
    по времени. ``rng`` передаётся снаружи ради воспроизводимости.
    """
    variants: list[np.ndarray] = []

    # 1. Белый шум малой амплитуды.
    noise_level = 0.005 * float(np.max(np.abs(y)) or 1.0)
    variants.append(y + noise_level * rng.standard_normal(len(y)).astype(np.float32))

    # 2. Небольшой сдвиг тональности (±2 полутона).
    try:
        steps = float(rng.uniform(-2.0, 2.0))
        variants.append(librosa.effects.pitch_shift(y, sr=sr, n_steps=steps))
    except Exception:  # pragma: no cover - на некоторых сборках librosa бывает капризна
        pass

    # 3. Круговой сдвиг по времени (до ±0.2 c).
    shift = int(0.2 * sr * float(rng.uniform(-1.0, 1.0)))
    variants.append(np.roll(y, shift))

    return [v.astype(np.float32) for v in variants]
