"""Скачивание и подготовка датасета плача младенцев.

Основной источник — корпус **Donate-a-Cry** (gveres/donateacry-corpus): открытые
записи по пяти классам, имена папок совпадают с нашими метками (hungry, tired,
belly_pain, discomfort, burping). Скрипт клонирует репозиторий (или скачивает
zip, если git недоступен) и раскладывает .wav по папкам ``data/<class>/``.

Запуск:
    python download_data.py                # в ./data
    python download_data.py --out ./data   # явно указать папку

После этого структура:
    data/
      hungry/*.wav
      tired/*.wav
      belly_pain/*.wav
      discomfort/*.wav
      burping/*.wav

Замечание про Baby Cry Sound Database (Kaggle): у Kaggle нет анонимного прямого
скачивания без API-токена, поэтому автоматизировать его надёжно нельзя. Если он
у вас есть локально — просто доложите файлы в соответствующие папки data/<class>,
train.py подхватит всё, что там лежит.
"""

from __future__ import annotations

import argparse
import io
import shutil
import subprocess
import sys
import tempfile
import urllib.request
import zipfile
from pathlib import Path

from cry_labels import CLASSES

REPO_GIT = "https://github.com/gveres/donateacry-corpus.git"
REPO_ZIP = "https://github.com/gveres/donateacry-corpus/archive/refs/heads/master.zip"

# Внутри репозитория очищенные данные лежат здесь, по подпапкам-классам.
CORPUS_SUBDIR = "donateacry_corpus_cleaned_and_updated_data"


def _clone_with_git(dest: Path) -> bool:
    """Попробовать клонировать через git (быстро, поверхностно). True при успехе."""
    if shutil.which("git") is None:
        return False
    try:
        subprocess.run(
            ["git", "clone", "--depth", "1", REPO_GIT, str(dest)],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        return True
    except subprocess.CalledProcessError:
        return False


def _download_zip(dest: Path) -> bool:
    """Запасной путь: скачать zip ветки master и распаковать в ``dest``."""
    try:
        print(f"Скачиваю zip: {REPO_ZIP}")
        with urllib.request.urlopen(REPO_ZIP, timeout=60) as resp:  # noqa: S310
            raw = resp.read()
    except Exception as exc:  # pragma: no cover - зависит от сети
        print(f"Не удалось скачать zip: {exc}", file=sys.stderr)
        return False

    with zipfile.ZipFile(io.BytesIO(raw)) as zf:
        zf.extractall(dest)
    return True


def _find_corpus_root(base: Path) -> Path | None:
    """Найти папку с подпапками-классами внутри распакованного/склонированного дерева."""
    # Прямое совпадение.
    for candidate in base.rglob(CORPUS_SUBDIR):
        if candidate.is_dir():
            return candidate
    # Фолбэк: любая папка, где есть хотя бы одна наша метка-подпапка.
    for candidate in base.rglob("*"):
        if candidate.is_dir() and any((candidate / c).is_dir() for c in CLASSES):
            return candidate
    return None


def organize(corpus_root: Path, out: Path) -> dict[str, int]:
    """Скопировать .wav из корпуса в ``out/<class>/`` и вернуть счётчики по классам."""
    counts: dict[str, int] = {c: 0 for c in CLASSES}
    for cls in CLASSES:
        src = corpus_root / cls
        dst = out / cls
        dst.mkdir(parents=True, exist_ok=True)
        if not src.is_dir():
            print(f"[!] В корпусе нет папки класса '{cls}' — пропускаю")
            continue
        for wav in src.glob("*.wav"):
            target = dst / wav.name
            if not target.exists():
                shutil.copy2(wav, target)
            counts[cls] += 1
    return counts


def main() -> int:
    parser = argparse.ArgumentParser(description="Скачать и подготовить датасет плача")
    parser.add_argument("--out", default="data", help="Куда сложить data/<class>/ (по умолчанию ./data)")
    args = parser.parse_args()

    out = Path(args.out).resolve()
    out.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        clone_dir = tmp_path / "donateacry"

        print("Получаю корпус Donate-a-Cry…")
        ok = _clone_with_git(clone_dir)
        if not ok:
            print("git недоступен или клонирование не удалось — пробую zip")
            ok = _download_zip(tmp_path)
        if not ok:
            print(
                "Не удалось получить датасет автоматически.\n"
                f"Скачайте вручную {REPO_GIT} и разложите .wav по папкам "
                f"{out}/<class>/, затем запустите train.py.",
                file=sys.stderr,
            )
            return 1

        corpus_root = _find_corpus_root(tmp_path)
        if corpus_root is None:
            print("Не нашёл папки классов внутри загруженного корпуса.", file=sys.stderr)
            return 1

        print(f"Корпус найден: {corpus_root}")
        counts = organize(corpus_root, out)

    total = sum(counts.values())
    print("\nГотово. Файлов по классам:")
    for cls, n in counts.items():
        print(f"  {cls:12s} {n}")
    print(f"  {'ИТОГО':12s} {total}")
    if total == 0:
        print("\n[!] Данных не найдено — проверьте источник.", file=sys.stderr)
        return 1
    print(f"\nДанные готовы в: {out}\nДальше: python train.py --data {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
