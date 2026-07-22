"""Быстрые тесты без датасета — запуск: `pytest -q`.

Проверяют инварианты, на которых держится корректность сервиса: длина вектора
признаков фиксирована и детерминирована, аугментации не ломают форму, а
рекомендации есть для каждого класса. Модель тут не нужна — используем
синтетический сигнал.
"""

import numpy as np

from cry_features import (
    DURATION_SEC,
    SAMPLE_RATE,
    augmentations,
    extract_features,
    feature_length,
    fix_length,
)
from cry_labels import CLASSES, recommendation_for


def _tone(seconds: float = DURATION_SEC, freq: float = 440.0) -> np.ndarray:
    t = np.linspace(0, seconds, int(SAMPLE_RATE * seconds), endpoint=False)
    return (0.5 * np.sin(2 * np.pi * freq * t)).astype(np.float32)


def test_feature_length_is_stable_regardless_of_duration():
    expected = feature_length()
    short = extract_features(_tone(1.0))  # короткая запись → дополняется нулями
    long = extract_features(_tone(9.0))   # длинная → обрезается до 5 c
    assert short.shape == (expected,)
    assert long.shape == (expected,)


def test_features_are_deterministic():
    y = _tone()
    a = extract_features(y)
    b = extract_features(y.copy())
    assert np.allclose(a, b)


def test_fix_length_pads_and_trims():
    target = int(SAMPLE_RATE * DURATION_SEC)
    assert len(fix_length(_tone(1.0))) == target
    assert len(fix_length(_tone(9.0))) == target


def test_augmentations_preserve_feature_shape():
    y = _tone()
    rng = np.random.default_rng(0)
    for variant in augmentations(y, SAMPLE_RATE, rng):
        assert extract_features(variant).shape == (feature_length(),)


def test_every_class_has_a_recommendation():
    for cls in CLASSES:
        rec = recommendation_for(cls)
        assert isinstance(rec, str) and rec.strip()


def test_unknown_class_falls_back():
    assert recommendation_for("definitely-not-a-class").strip()
