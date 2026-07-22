"""Обучение лёгкого классификатора причины плача.

Пайплайн:
  1. Пройти по data/<class>/*.wav.
  2. Из каждой записи извлечь вектор признаков (cry_features.extract_features).
     На ОБУЧАЮЩИХ примерах дополнительно добавить аугментации (шум/pitch/сдвиг),
     чтобы увеличить объём и устойчивость. Тест — только «чистые» записи.
  3. Обучить RandomForest (class_weight='balanced' — корпус несбалансирован:
     hungry сильно преобладает).
  4. Вывести Accuracy, per-class отчёт и confusion matrix.
  5. Сохранить модель + метаданные в model.pkl (joblib).

Почему RandomForest, а не CNN: цель — обычный VPS (1–2 CPU, 2 ГБ RAM, без GPU).
На агрегированных признаках RF обучается за секунды, весит мегабайты и на
инференсе отвечает мгновенно. Каркас под CNN описан в README как альтернатива.

Запуск:
    python train.py --data data --out model.pkl
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import joblib
import numpy as np
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import accuracy_score, classification_report, confusion_matrix
from sklearn.model_selection import train_test_split

from cry_features import (
    FEATURE_VERSION,
    SAMPLE_RATE,
    augmentations,
    extract_features,
    feature_length,
    load_audio,
)
from cry_labels import CLASSES

# Фиксируем seed ради воспроизводимости прогонов.
SEED = 42


def _gather_files(data_dir: Path) -> list[tuple[Path, str]]:
    """Собрать (путь, класс) по папкам data/<class>/*.wav."""
    items: list[tuple[Path, str]] = []
    for cls in CLASSES:
        for wav in sorted((data_dir / cls).glob("*.wav")):
            items.append((wav, cls))
    return items


def _featurize(files: list[tuple[Path, str]]) -> tuple[np.ndarray, np.ndarray, list[Path]]:
    """Извлечь признаки из «чистых» записей. Битые файлы пропускаются с предупреждением."""
    X: list[np.ndarray] = []
    y: list[str] = []
    paths: list[Path] = []
    for path, cls in files:
        try:
            audio = load_audio(str(path))
            X.append(extract_features(audio))
            y.append(cls)
            paths.append(path)
        except Exception as exc:  # noqa: BLE001 - один битый файл не должен ронять обучение
            print(f"[!] пропускаю {path.name}: {exc}", file=sys.stderr)
    if not X:
        raise SystemExit("Не удалось извлечь ни одного признака — проверьте данные.")
    return np.vstack(X), np.array(y), paths


def _augment_training(
    train_paths: list[Path], train_labels: np.ndarray, rng: np.random.Generator
) -> tuple[np.ndarray, np.ndarray]:
    """Добавить аугментированные признаки для обучающей выборки."""
    extra_X: list[np.ndarray] = []
    extra_y: list[str] = []
    for path, cls in zip(train_paths, train_labels):
        try:
            audio = load_audio(str(path))
            for variant in augmentations(audio, SAMPLE_RATE, rng):
                extra_X.append(extract_features(variant))
                extra_y.append(cls)
        except Exception as exc:  # noqa: BLE001
            print(f"[!] аугментация пропущена для {path.name}: {exc}", file=sys.stderr)
    if not extra_X:
        return np.empty((0, feature_length()), dtype=np.float32), np.array([], dtype=object)
    return np.vstack(extra_X), np.array(extra_y)


def main() -> int:
    parser = argparse.ArgumentParser(description="Обучить классификатор причины плача")
    parser.add_argument("--data", default="data", help="Папка data/<class>/*.wav")
    parser.add_argument("--out", default="model.pkl", help="Куда сохранить модель")
    parser.add_argument("--test-size", type=float, default=0.2, help="Доля теста (по умолчанию 0.2)")
    parser.add_argument("--trees", type=int, default=300, help="Число деревьев RandomForest")
    parser.add_argument("--no-augment", action="store_true", help="Отключить аугментацию")
    args = parser.parse_args()

    data_dir = Path(args.data).resolve()
    files = _gather_files(data_dir)
    if not files:
        print(f"В {data_dir} нет данных. Сначала: python download_data.py --out {data_dir}", file=sys.stderr)
        return 1

    print(f"Найдено записей: {len(files)}")
    counts: dict[str, int] = {c: 0 for c in CLASSES}
    for _, cls in files:
        counts[cls] += 1
    for cls, n in counts.items():
        print(f"  {cls:12s} {n}")

    present = [c for c, n in counts.items() if n > 0]
    if len(present) < 2:
        print("Нужно минимум 2 класса с данными для обучения.", file=sys.stderr)
        return 1

    print("\nИзвлекаю признаки…")
    X, y, paths = _featurize(files)
    print(f"Матрица признаков: {X.shape}")

    # Стратифицированное разбиение — сохраняет пропорции классов в train/test.
    idx = np.arange(len(y))
    train_idx, test_idx = train_test_split(
        idx, test_size=args.test_size, random_state=SEED, stratify=y
    )
    X_train, y_train = X[train_idx], y[train_idx]
    X_test, y_test = X[test_idx], y[test_idx]

    # Аугментация — ТОЛЬКО на train, чтобы тест оставался честным.
    if not args.no_augment:
        print("Аугментирую обучающую выборку (шум / pitch / сдвиг)…")
        rng = np.random.default_rng(SEED)
        aug_X, aug_y = _augment_training([paths[i] for i in train_idx], y_train, rng)
        if len(aug_X):
            X_train = np.vstack([X_train, aug_X])
            y_train = np.concatenate([y_train, aug_y])
        print(f"Размер train после аугментации: {X_train.shape}")

    print(f"\nОбучаю RandomForest ({args.trees} деревьев)…")
    clf = RandomForestClassifier(
        n_estimators=args.trees,
        class_weight="balanced",  # компенсирует перекос по классам
        n_jobs=-1,
        random_state=SEED,
    )
    clf.fit(X_train, y_train)

    # ---- Метрики ----
    y_pred = clf.predict(X_test)
    acc = accuracy_score(y_test, y_pred)
    print(f"\n=== Результаты на тесте ===\nAccuracy: {acc:.3f}\n")
    labels_present = sorted(set(y_test) | set(y_pred))
    print(classification_report(y_test, y_pred, labels=labels_present, zero_division=0))
    print("Confusion matrix (строки — истина, столбцы — предсказание):")
    print("labels:", labels_present)
    print(confusion_matrix(y_test, y_pred, labels=labels_present))

    # ---- Сохранение ----
    bundle = {
        "model": clf,
        "classes": list(clf.classes_),
        "feature_version": FEATURE_VERSION,
        "feature_length": feature_length(),
        "sample_rate": SAMPLE_RATE,
        "accuracy": float(acc),
    }
    out_path = Path(args.out).resolve()
    joblib.dump(bundle, out_path, compress=3)
    print(f"\nМодель сохранена: {out_path}  ({out_path.stat().st_size / 1024:.0f} КБ)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
