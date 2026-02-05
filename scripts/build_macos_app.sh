#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_PATH="${CP_BUILD_ENV_PATH:-${ROOT_DIR}/.conda-envs/cp-build}"
PKGS_DIR="${CP_CONDA_PKGS_DIRS:-${ROOT_DIR}/.conda-pkgs}"

export CONDA_PKGS_DIRS="${PKGS_DIR}"
export PYTHONPATH="${ROOT_DIR}"

if ! command -v conda >/dev/null 2>&1; then
  echo "conda is required but was not found on PATH." >&2
  exit 1
fi

# Create env if missing
if [ ! -d "${ENV_PATH}" ]; then
  conda create -p "${ENV_PATH}" python=3.9 -y
fi

PYTHON_BIN="${ENV_PATH}/bin/python"

required_conda_pkgs=(
  openjdk
  wxpython
  pyinstaller
  pyinstaller-hooks-contrib
  python
  numpy
  scipy
  scikit-image
  scikit-learn
  h5py
  pillow
  matplotlib
  pyzmq
  docutils
  mahotas
  psutil
)

missing_conda_pkgs=()
for pkg in "${required_conda_pkgs[@]}"; do
  if ! conda list -p "${ENV_PATH}" "${pkg}" >/dev/null 2>&1; then
    missing_conda_pkgs+=("${pkg}")
  fi
done

if [ "${#missing_conda_pkgs[@]}" -gt 0 ]; then
  # Base build tools + Java + wx + scientific stack (binary)
  conda install -p "${ENV_PATH}" -c conda-forge \
    "python=3.9" "numpy<2" "scipy<1.11" "scikit-image==0.18.3" "scikit-learn<1" \
    "h5py<4" "pillow<10" "matplotlib<4" "pyzmq<23" "docutils==0.15.2" \
    openjdk wxpython pyinstaller pyinstaller-hooks-contrib \
    mahotas psutil -y
else
  echo "Conda deps already present; skipping conda install step."
fi

# Prokaryote via pip (not reliably available on conda-forge for osx-arm64)
"${PYTHON_BIN}" -m pip install "prokaryote==2.4.4" --no-build-isolation --no-deps
"${PYTHON_BIN}" - <<'PY'
import importlib
try:
    importlib.import_module("prokaryote")
except Exception as exc:
    raise SystemExit(f"Prokaryote import failed after install: {exc}")
PY

# Sentry SDK via pip
"${PYTHON_BIN}" -m pip install "sentry-sdk==0.18.0" --no-build-isolation --no-deps
"${PYTHON_BIN}" - <<'PY'
import importlib
try:
    importlib.import_module("sentry_sdk")
except Exception as exc:
    raise SystemExit(f"Sentry SDK import failed after install: {exc}")
PY

# Jinja2, inflect, deprecation, and deps via pip (runtime deps)
"${PYTHON_BIN}" -m pip install \
  "jinja2>=2.11.2" \
  "markupsafe>=2.0" \
  "inflect>=2.1,<7" \
  "pydantic<2" \
  "deprecation==2.1.0" \
  --no-build-isolation --no-deps --upgrade --force-reinstall

# Bioformats via pip
conda run -p "${ENV_PATH}" \
  python -m pip install "python-bioformats<5" "python-javabridge<5"

# Centrosome via pip (conda-forge may not provide a compatible build)
"${PYTHON_BIN}" -m pip install "centrosome==1.2.3" --no-build-isolation --no-deps
"${PYTHON_BIN}" - <<'PY'
import importlib
try:
    importlib.import_module("centrosome")
except Exception as exc:
    raise SystemExit(f"Centrosome import failed after install: {exc}")
PY

# Core package via pip (no deps; we already installed them via conda)
conda run -p "${ENV_PATH}" \
  python -m pip install "cellprofiler-core==4.2.8" --no-deps

# Editable install without build isolation to avoid rebuilding numpy
conda run -p "${ENV_PATH}" \
  python -m pip install -e ".[build]" --no-build-isolation --no-deps

# Build the app
conda run -p "${ENV_PATH}" \
  python - <<'PY'
import importlib

mods = [
    "cellprofiler",
    "cellprofiler_core",
    "bioformats",
    "javabridge",
    "h5py",
    "numpy",
    "scipy",
    "skimage",
    "sklearn",
    "mahotas",
    "PIL",
    "matplotlib",
    "pyzmq",
    "centrosome",
    "psutil",
    "docutils",
    "prokaryote",
    "sentry_sdk",
    "jinja2",
    "inflect",
    "deprecation",
    "markupsafe",
    "pydantic",
]

failed = []
for mod in mods:
    try:
        importlib.import_module(mod)
    except Exception as exc:
        failed.append((mod, repr(exc)))

if failed:
    print("Preflight import failures:")
    for mod, exc in failed:
        print(f"- {mod}: {exc}")
    raise SystemExit(1)
print("Preflight import check passed.")
PY

CENTROSOME_PATH="$("${PYTHON_BIN}" - <<'PY'
import centrosome
import os
print(os.path.dirname(centrosome.__file__))
PY
)"

JVM_PATH="${ENV_PATH}/lib/jvm"

"${PYTHON_BIN}" -m PyInstaller \
  --noconfirm \
  --clean \
  --windowed \
  --name CellProfiler \
  --icon "${ROOT_DIR}/cellprofiler/data/icons/CellProfiler.icns" \
  --paths "${ROOT_DIR}" \
  --runtime-hook "${ROOT_DIR}/scripts/pyinstaller_runtime_hook.py" \
  --collect-submodules cellprofiler \
  --collect-submodules cellprofiler_core \
  --collect-submodules javabridge \
  --collect-submodules bioformats \
  --collect-submodules centrosome \
  --collect-submodules skimage \
  --collect-submodules sklearn \
  --collect-submodules mahotas \
  --collect-submodules h5py \
  --collect-submodules matplotlib \
  --collect-submodules PIL \
  --collect-submodules pyzmq \
  --collect-submodules prokaryote \
  --collect-submodules sentry_sdk \
  --collect-submodules jinja2 \
  --collect-submodules inflect \
  --collect-submodules deprecation \
  --collect-submodules markupsafe \
  --collect-submodules pydantic \
  --hidden-import centrosome \
  --hidden-import centrosome.index \
  --add-data "${CENTROSOME_PATH}:centrosome" \
  --collect-all cellprofiler \
  --collect-all cellprofiler_core \
  --collect-all h5py \
  --collect-all numpy \
  --collect-all scipy \
  --collect-all skimage \
  --collect-all sklearn \
  --collect-all mahotas \
  --collect-all PIL \
  --collect-all matplotlib \
  --collect-all pyzmq \
  --collect-all psutil \
  --collect-all docutils \
  --collect-all centrosome \
  --collect-all prokaryote \
  --collect-all sentry_sdk \
  --collect-all jinja2 \
  --collect-all inflect \
  --collect-all deprecation \
  --collect-all markupsafe \
  --collect-all pydantic \
  --collect-all javabridge \
  --collect-all bioformats \
  "${ROOT_DIR}/cellprofiler/__main__.py"

APP_RESOURCES="${ROOT_DIR}/dist/CellProfiler.app/Contents/Resources"
mkdir -p "${APP_RESOURCES}/Home"
rsync -a "${JVM_PATH}/" "${APP_RESOURCES}/Home/"

echo "Build complete: ${ROOT_DIR}/dist/CellProfiler.app"

APP_MACOS="${ROOT_DIR}/dist/CellProfiler.app/Contents/MacOS"
if [ -d "${APP_MACOS}" ] && [ ! -e "${APP_MACOS}/cp" ]; then
  ln -s "CellProfiler" "${APP_MACOS}/cp"
fi

SAVEIMAGES_BUNDLE="${ROOT_DIR}/dist/CellProfiler.app/Contents/Resources/cellprofiler/modules/saveimages.py"
if ! rg -n "pop\\(\"compress\"\\)|pop\\('compress'\\)" "${SAVEIMAGES_BUNDLE}" >/dev/null 2>&1; then
  echo "Bundled SaveImages does not include compress fallback. Expected to find updated code in ${SAVEIMAGES_BUNDLE}." >&2
  exit 1
fi
