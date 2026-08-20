#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# GROMACS 2026.3 — Reproducible Conda + NVIDIA CUDA Installer
# Linux / WSL2, x86_64
#
# Installs GROMACS directly into the ACTIVE Conda environment.
# If an NVIDIA GPU is visible, builds with CUDA GPU support.
# Otherwise, builds a CPU/OpenMP/thread-MPI version.
# ============================================================

GROMACS_VERSION="2026.3"
GROMACS_URL="https://ftp.gromacs.org/gromacs/gromacs-${GROMACS_VERSION}.tar.gz"
GROMACS_MD5="7987af0c6ab939ab6e639f32d0dd260f"
MIN_CUDA_VERSION="12.1"
GCC_VERSION="14"

# Override if desired, e.g.:
#   GMX_BUILD_JOBS=8 bash install_gromacs.sh
BUILD_JOBS="${GMX_BUILD_JOBS:-$(nproc)}"

banner() {
    echo
    echo "============================================================"
    echo " $1"
    echo "============================================================"
}

die() {
    echo
    echo "ERROR: $*" >&2
    exit 1
}

version_ge() {
    python - "$1" "$2" <<'PY'
import sys
def parts(v):
    return tuple(int(x) for x in v.split(".") if x.isdigit())
sys.exit(0 if parts(sys.argv[1]) >= parts(sys.argv[2]) else 1)
PY
}

banner "GROMACS ${GROMACS_VERSION} Installer"

# ------------------------------------------------------------
# 1. Require an active, non-base Conda environment
# ------------------------------------------------------------

command -v conda >/dev/null 2>&1 || \
    die "Conda is not available. Install Miniconda/Anaconda first."

[[ -n "${CONDA_PREFIX:-}" ]] || \
    die "No Conda environment is active. Run: conda activate <environment>"

[[ "${CONDA_DEFAULT_ENV:-}" != "base" ]] || \
    die "Refusing to install into Conda base. Activate a dedicated environment first."

[[ "$(uname -s)" == "Linux" ]] || \
    die "This installer is intended for Linux or WSL2."

[[ "$(uname -m)" == "x86_64" ]] || \
    die "This simple installer currently targets x86_64 Linux/WSL2."

echo "Active Conda environment : ${CONDA_DEFAULT_ENV}"
echo "Conda prefix             : ${CONDA_PREFIX}"
echo "Build threads            : ${BUILD_JOBS}"

# Prefer mamba if it is already installed.
if command -v mamba >/dev/null 2>&1; then
    PKG_MGR="mamba"
else
    PKG_MGR="conda"
fi

# ------------------------------------------------------------
# 2. Install reproducible build tools inside this environment
# ------------------------------------------------------------

banner "Installing build dependencies"

"${PKG_MGR}" install -y -c conda-forge \
    "cmake>=3.28" \
    make \
    "gcc_linux-64=${GCC_VERSION}" \
    "gxx_linux-64=${GCC_VERSION}" \
    curl \
    pkg-config

CC_BIN="$(command -v x86_64-conda-linux-gnu-cc || true)"
CXX_BIN="$(command -v x86_64-conda-linux-gnu-c++ || true)"

[[ -n "${CC_BIN}" ]] || die "Conda C compiler was not found after installation."
[[ -n "${CXX_BIN}" ]] || die "Conda C++ compiler was not found after installation."

echo
echo "C compiler   : ${CC_BIN}"
echo "C++ compiler : ${CXX_BIN}"
echo "CMake        : $(cmake --version | head -n 1)"

# ------------------------------------------------------------
# 3. Detect NVIDIA GPU and install CUDA Toolkit when needed
# ------------------------------------------------------------

GPU_BUILD=0
CUDA_ROOT=""

banner "Detecting GPU"

if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1; then
    GPU_BUILD=1

    echo "NVIDIA GPU detected:"
    nvidia-smi -L
    echo

    CUDA_VERSION=""

    if command -v nvcc >/dev/null 2>&1; then
        CUDA_VERSION="$(
            nvcc --version |
            sed -n 's/.*release \([0-9][0-9.]*\).*/\1/p' |
            head -n 1
        )"
    fi

    if [[ -z "${CUDA_VERSION}" ]] || ! version_ge "${CUDA_VERSION}" "${MIN_CUDA_VERSION}"; then
        echo "CUDA Toolkit ${MIN_CUDA_VERSION}+ was not found."
        echo "Installing the current NVIDIA CUDA Toolkit into this Conda environment..."
        echo

        # NVIDIA documents this as the Conda installation method for CUDA Toolkit.
        "${PKG_MGR}" install -y -c nvidia cuda

        hash -r

        command -v nvcc >/dev/null 2>&1 || \
            die "CUDA Toolkit installation finished, but nvcc is not available."

        CUDA_VERSION="$(
            nvcc --version |
            sed -n 's/.*release \([0-9][0-9.]*\).*/\1/p' |
            head -n 1
        )"
    fi

    version_ge "${CUDA_VERSION}" "${MIN_CUDA_VERSION}" || \
        die "GROMACS ${GROMACS_VERSION} requires CUDA ${MIN_CUDA_VERSION}+; found ${CUDA_VERSION}."

    CUDA_ROOT="$(dirname "$(dirname "$(readlink -f "$(command -v nvcc)")")")"

    echo "CUDA compiler : $(command -v nvcc)"
    echo "CUDA version  : ${CUDA_VERSION}"
    echo "CUDA root     : ${CUDA_ROOT}"
else
    echo "No NVIDIA GPU is visible through nvidia-smi."
    echo "GROMACS will be built with CPU + OpenMP + thread-MPI support."
    echo
    echo "If this machine has an NVIDIA GPU, fix NVIDIA/WSL GPU visibility"
    echo "first and rerun this installer to obtain a CUDA-enabled build."
fi

# ------------------------------------------------------------
# 4. Download and verify official GROMACS 2026.3 source
# ------------------------------------------------------------

banner "Downloading GROMACS ${GROMACS_VERSION}"

WORK_ROOT="$(mktemp -d -t gromacs-${GROMACS_VERSION}-XXXXXX)"
TARBALL="${WORK_ROOT}/gromacs-${GROMACS_VERSION}.tar.gz"
SOURCE_DIR="${WORK_ROOT}/gromacs-${GROMACS_VERSION}"
BUILD_DIR="${SOURCE_DIR}/build"

cleanup() {
    rm -rf "${WORK_ROOT}"
}
trap cleanup EXIT

curl -fL \
    --retry 3 \
    --retry-delay 2 \
    "${GROMACS_URL}" \
    -o "${TARBALL}"

python - "${TARBALL}" "${GROMACS_MD5}" <<'PY'
import hashlib
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
expected = sys.argv[2].lower()

digest = hashlib.md5()
with path.open("rb") as handle:
    for chunk in iter(lambda: handle.read(1024 * 1024), b""):
        digest.update(chunk)

actual = digest.hexdigest().lower()

print(f"Expected MD5 : {expected}")
print(f"Actual MD5   : {actual}")

if actual != expected:
    raise SystemExit("ERROR: GROMACS source checksum does not match.")
PY

tar -xzf "${TARBALL}" -C "${WORK_ROOT}"

[[ -d "${SOURCE_DIR}" ]] || \
    die "Source directory was not created after extraction."

# ------------------------------------------------------------
# 5. Configure GROMACS
# ------------------------------------------------------------

banner "Configuring GROMACS"

CMAKE_ARGS=(
    -S "${SOURCE_DIR}"
    -B "${BUILD_DIR}"
    "-DCMAKE_INSTALL_PREFIX=${CONDA_PREFIX}"
    "-DCMAKE_BUILD_TYPE=Release"
    "-DCMAKE_C_COMPILER=${CC_BIN}"
    "-DCMAKE_CXX_COMPILER=${CXX_BIN}"
    "-DGMX_BUILD_OWN_FFTW=ON"
    "-DGMX_MPI=OFF"
    "-DGMX_THREAD_MPI=ON"
    "-DGMX_OPENMP=ON"
)

if [[ "${GPU_BUILD}" -eq 1 ]]; then
    CMAKE_ARGS+=(
        "-DGMX_GPU=CUDA"
        "-DCUDAToolkit_ROOT=${CUDA_ROOT}"
        "-DCMAKE_CUDA_HOST_COMPILER=${CXX_BIN}"
    )
else
    CMAKE_ARGS+=(
        "-DGMX_GPU=OFF"
    )
fi

cmake "${CMAKE_ARGS[@]}"

# ------------------------------------------------------------
# 6. Compile and install directly into the active Conda env
# ------------------------------------------------------------

banner "Building GROMACS"

cmake --build "${BUILD_DIR}" --parallel "${BUILD_JOBS}"

banner "Installing into ${CONDA_DEFAULT_ENV}"

cmake --install "${BUILD_DIR}"

# Clear any shell executable lookup cache in this installer shell.
hash -r

[[ -x "${CONDA_PREFIX}/bin/gmx" ]] || \
    die "Installation completed but ${CONDA_PREFIX}/bin/gmx does not exist."

# Source GMXRC for this installer process so verification uses the
# complete GROMACS runtime environment.
if [[ -f "${CONDA_PREFIX}/bin/GMXRC" ]]; then
    # shellcheck disable=SC1090
    source "${CONDA_PREFIX}/bin/GMXRC"
fi

# ------------------------------------------------------------
# 7. Verify installation
# ------------------------------------------------------------

banner "Verifying GROMACS"

GMX_VERSION_OUTPUT="$("${CONDA_PREFIX}/bin/gmx" --version)"
printf '%s\n' "${GMX_VERSION_OUTPUT}"

echo
if ! grep -q "GROMACS version:.*${GROMACS_VERSION}" <<< "${GMX_VERSION_OUTPUT}"; then
    die "gmx is installed, but the reported version is not ${GROMACS_VERSION}."
fi

if [[ "${GPU_BUILD}" -eq 1 ]]; then
    if grep -qi "GPU support:.*CUDA" <<< "${GMX_VERSION_OUTPUT}"; then
        echo "SUCCESS: GROMACS ${GROMACS_VERSION} was built with CUDA GPU support."
    else
        die "An NVIDIA GPU was detected, but gmx --version does not report CUDA GPU support."
    fi
else
    echo "SUCCESS: GROMACS ${GROMACS_VERSION} was installed as a CPU build."
fi

# Save reproducibility information inside the Conda environment.
{
    echo "GROMACS source: ${GROMACS_URL}"
    echo "GROMACS MD5: ${GROMACS_MD5}"
    echo "Installed: $(date -Is)"
    echo "Conda environment: ${CONDA_DEFAULT_ENV}"
    echo "Conda prefix: ${CONDA_PREFIX}"
    echo "GPU build requested: ${GPU_BUILD}"
    if [[ "${GPU_BUILD}" -eq 1 ]]; then
        echo "CUDA version: ${CUDA_VERSION}"
        echo "CUDA root: ${CUDA_ROOT}"
    fi
    echo
    printf '%s\n' "${GMX_VERSION_OUTPUT}"
} > "${CONDA_PREFIX}/GROMACS_${GROMACS_VERSION}_BUILD_INFO.txt"

echo
echo "Build record:"
echo "  ${CONDA_PREFIX}/GROMACS_${GROMACS_VERSION}_BUILD_INFO.txt"
echo
echo "GROMACS executable:"
echo "  ${CONDA_PREFIX}/bin/gmx"
echo
echo "Because GROMACS was installed directly into the active Conda"
echo "environment, no system-wide installation and no sudo are required."
echo
echo "After this installer returns, verify from your current shell with:"
echo
echo "  gmx --version"
echo
echo "If your shell has stale state, simply reactivate the environment:"
echo
echo "  conda deactivate"
echo "  conda activate ${CONDA_DEFAULT_ENV}"
echo
echo "Then:"
echo
echo "  gmx --version"
echo
echo "Installation complete."
