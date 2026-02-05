#!/usr/bin/env bash
set -euo pipefail

ENV_NAME="${CP_CONDA_ENV:-cp-dev}"
PY_VER="${CP_PYTHON_VERSION:-3.9}"

if ! command -v conda >/dev/null 2>&1; then
  echo "conda is required but was not found on PATH." >&2
  exit 1
fi

if ! conda env list | awk '{print $1}' | grep -Fxq "${ENV_NAME}"; then
  conda create -n "${ENV_NAME}" python="${PY_VER}" -y
fi

conda install -n "${ENV_NAME}" -c conda-forge openjdk wxpython -y
conda run -n "${ENV_NAME}" python -m pip install -e ".[test]"

conda run -n "${ENV_NAME}" python -m cellprofiler "$@"
