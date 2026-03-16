import shutil
import tempfile
from pathlib import Path
from typing import Iterable, Tuple

FIXTURES_DIR = Path(__file__).parent / "fixtures" / "sessions"


def make_fixture_directory(file_names: Iterable[str]) -> Tuple[tempfile.TemporaryDirectory, Path]:
    temp_dir = tempfile.TemporaryDirectory()
    temp_path = Path(temp_dir.name)
    for name in file_names:
        shutil.copy(FIXTURES_DIR / name, temp_path / name)
    return temp_dir, temp_path
