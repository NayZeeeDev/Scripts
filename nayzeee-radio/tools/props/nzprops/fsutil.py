"""
nzprops.fsutil - atomic file writes and simple cross-process locks.

Several builds run at the same time (one per model engineer, plus renders). Every output file is
written to a unique temporary name next to its destination and moved into place with os.replace,
so a reader (another build collecting manifests, cwtool, the preview renderer) only ever sees a
complete old file or a complete new one. FileLock serialises the few steps that read many files
and write one aggregate (ytyp, manifest tables, layout) so the last writer always saw everything.
"""
from __future__ import annotations

import contextlib
import json
import os
import shutil
import tempfile
import time

try:  # POSIX advisory locks; on Windows the lock is a no-op (builds there are not run concurrently)
    import fcntl
except ImportError:  # pragma: no cover
    fcntl = None


def _umask():
    um = os.umask(0)
    os.umask(um)
    return um


_MODE = 0o666 & ~_umask()


def _tmp_for(path):
    d = os.path.dirname(os.path.abspath(path)) or "."
    os.makedirs(d, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix="." + os.path.basename(path) + ".", suffix=".tmp", dir=d)
    os.close(fd)
    os.chmod(tmp, _MODE)     # mkstemp creates 0600; outputs get the usual rw-r--r--
    return tmp


@contextlib.contextmanager
def atomic_path(path):
    """Yield a temporary path; on success it replaces `path` atomically, on error it is removed."""
    tmp = _tmp_for(path)
    try:
        yield tmp
        os.replace(tmp, path)
    except BaseException:
        with contextlib.suppress(OSError):
            os.remove(tmp)
        raise


def write_bytes(path, data: bytes):
    with atomic_path(path) as tmp:
        with open(tmp, "wb") as f:
            f.write(data)


def write_text(path, text: str):
    with atomic_path(path) as tmp:
        with open(tmp, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)


def write_json(path, obj, indent=1):
    write_text(path, json.dumps(obj, indent=indent) + "\n")


def save_image(img, path, fmt=None):
    """PIL image -> path atomically (format from the extension unless given)."""
    fmt = fmt or {".png": "PNG", ".jpg": "JPEG", ".jpeg": "JPEG"}.get(os.path.splitext(path)[1].lower(), "PNG")
    with atomic_path(path) as tmp:
        img.save(tmp, fmt)


def copy_file(src, dst):
    with atomic_path(dst) as tmp:
        shutil.copyfile(src, tmp)
        shutil.copystat(src, tmp)


def read_json(path, default=None):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


class FileLock:
    """Exclusive advisory lock on `path` (created if missing). Use as a context manager."""

    def __init__(self, path, timeout=900.0):
        self.path = path
        self.timeout = timeout
        self.fh = None

    def __enter__(self):
        os.makedirs(os.path.dirname(os.path.abspath(self.path)) or ".", exist_ok=True)
        self.fh = open(self.path, "a+")
        if fcntl is None:
            return self
        t0 = time.time()
        while True:
            try:
                fcntl.flock(self.fh.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                return self
            except OSError:
                if time.time() - t0 > self.timeout:
                    raise TimeoutError(f"could not lock {self.path} within {self.timeout:.0f}s")
                time.sleep(0.2)

    def __exit__(self, *exc):
        if self.fh is not None:
            if fcntl is not None:
                with contextlib.suppress(OSError):
                    fcntl.flock(self.fh.fileno(), fcntl.LOCK_UN)
            self.fh.close()
            self.fh = None
        return False
