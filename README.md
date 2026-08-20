# 🧬 GROMACS Installation

<p align="center">
  <strong>Reproducible GROMACS 2026.3 installation for Conda, Linux/WSL2, and NVIDIA GPU acceleration</strong>
</p>

<p align="center">
  <em>One environment. One installer. A working <code>gmx</code> command.</em>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/GROMACS-2026.3-blue?style=for-the-badge" alt="GROMACS 2026.3">
  <img src="https://img.shields.io/badge/NVIDIA-CUDA%20Auto--Detect-76B900?style=for-the-badge&logo=nvidia" alt="NVIDIA CUDA">
  <img src="https://img.shields.io/badge/Linux%20%2F%20WSL2-Supported-orange?style=for-the-badge&logo=linux" alt="Linux and WSL2">
  <img src="https://img.shields.io/badge/Conda-Environment--Local-44A833?style=for-the-badge&logo=anaconda" alt="Conda">
</p>

---

## 🚀 Overview

This repository provides a **copy-and-paste installation workflow for GROMACS 2026.3**.

The installer is designed for molecular-dynamics workflows such as **PyMACS**:

> https://github.com/schurerlab/Pymacs

The goal is to avoid the common situation where a Python/MDAnalysis Conda environment is active but:

```text
gmx: command not found
```

The installer builds GROMACS from the official source release and installs it **directly inside the active Conda environment**.

That means:

- no system-wide GROMACS installation is required
- no `sudo make install` is required
- `gmx` is associated with the Conda environment
- different Conda environments can carry different GROMACS installations
- the environment remains straightforward to reproduce
- PyMACS can use the standard `gmx` executable
- an NVIDIA GPU is used when CUDA is available

---

## ⚡ Super Quick Start

Activate the Conda environment that should own GROMACS.

For PyMACS this is commonly:

```bash
conda activate mdanalysis
```

Confirm that you are **not** in `base`:

```bash
echo "$CONDA_DEFAULT_ENV"
```

Then copy and paste the complete installer below.

> **Important:** this installer intentionally refuses to install into Conda `base`.

```bash
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

```

---

## ✅ Verify the installation

After the installer completes:

```bash
gmx --version
```

For an NVIDIA/CUDA build, the output should include information similar to:

```text
GROMACS version:    2026.3
GPU support:        CUDA
```

You can also check that the executable comes from the active environment:

```bash
which gmx
```

Expected pattern:

```text
.../anaconda3/envs/mdanalysis/bin/gmx
```

---

## 🎮 GPU behavior

The installer uses the following logic:

| Hardware state | Result |
|---|---|
| NVIDIA GPU visible through `nvidia-smi` | Build GROMACS with `GMX_GPU=CUDA` |
| NVIDIA GPU visible but CUDA Toolkit is missing | Install CUDA Toolkit in the active Conda environment, then build with CUDA |
| CUDA Toolkit older than the GROMACS 2026 requirement | Install a current CUDA Toolkit in the environment |
| No NVIDIA GPU visible | Build CPU + OpenMP + thread-MPI GROMACS |
| NVIDIA GPU expected but `nvidia-smi` fails | Fix GPU/driver visibility, then rerun this installer |

GROMACS 2026 requires **CUDA 12.1 or newer** for the CUDA backend.

The installer uses:

```text
GMX_GPU=CUDA
GMX_OPENMP=ON
GMX_THREAD_MPI=ON
GMX_MPI=OFF
GMX_BUILD_OWN_FFTW=ON
CMAKE_BUILD_TYPE=Release
```

This configuration is intended for a **single Linux/WSL workstation**, including GPU workstations used for local PyMACS simulations.

External MPI/HPC installations are intentionally outside the scope of this simple installer.

---

## 🪟 WSL2 + NVIDIA note

When using WSL2, NVIDIA GPU support comes from the **Windows NVIDIA driver**.

Do **not** install a Linux NVIDIA display driver inside WSL.

The expected workflow is:

```text
Windows NVIDIA Driver
        ↓
WSL2 sees GPU through nvidia-smi
        ↓
CUDA Toolkit inside Linux/Conda
        ↓
CUDA-enabled GROMACS build
```

Before installing GROMACS, check:

```bash
nvidia-smi
```

If the GPU appears there, the installer can build the CUDA version.

If `nvidia-smi` does not work in WSL, fix the Windows/WSL NVIDIA setup before expecting GROMACS GPU acceleration.

---

## 🧠 Why install into the Conda environment?

A normal source installation often uses a prefix such as:

```text
/usr/local/gromacs
```

That works, but it creates a separate system dependency that users must remember to load.

This installer instead uses:

```bash
-DCMAKE_INSTALL_PREFIX="$CONDA_PREFIX"
```

So when the `mdanalysis` environment is active, GROMACS is installed under that same environment:

```text
$CONDA_PREFIX/bin/gmx
$CONDA_PREFIX/bin/GMXRC
$CONDA_PREFIX/share/gromacs/
```

The active Conda environment already places:

```text
$CONDA_PREFIX/bin
```

on `PATH`, so `gmx` becomes available as part of that environment.

No system-wide shell configuration is required.

---

## 🔄 Do I need to restart the shell?

Normally, **no**.

Because `gmx` is installed directly into:

```text
$CONDA_PREFIX/bin
```

and that directory is already on `PATH`, the current activated environment can normally find `gmx` immediately.

Check:

```bash
gmx --version
```

If the shell still has stale state, reactivate the environment:

```bash
conda deactivate
conda activate mdanalysis
gmx --version
```

---

## 🧪 PyMACS usage

Once the installation succeeds:

```bash
conda activate mdanalysis
gmx --version
```

PyMACS standard scripts can then use:

```text
gmx
```

directly.

Example:

```bash
python 2_AutomateGromacs.py
```

or:

```bash
python 3A_AutomateGromacs.py
```

For a batch analysis wrapper:

```bash
./run_maddison_3A_batch.sh
```

The key requirement is simply:

```bash
command -v gmx
```

returning a valid executable while the environment is active.

---

## 🛠️ What the installer does

The script performs these steps automatically:

1. Confirms that Conda is available.
2. Requires a dedicated active Conda environment.
3. Refuses to modify Conda `base`.
4. Installs CMake, Make, GCC/G++, `curl`, and `pkg-config` into the active environment.
5. Checks whether an NVIDIA GPU is visible.
6. Installs the NVIDIA CUDA Toolkit into the environment when CUDA compilation is required.
7. Downloads the official GROMACS 2026.3 source archive.
8. Verifies the official MD5 checksum.
9. Configures a Release build.
10. Enables CUDA automatically for NVIDIA systems.
11. Enables OpenMP and thread-MPI.
12. Builds GROMACS' recommended single-precision FFTW dependency.
13. Compiles GROMACS.
14. Installs GROMACS into the active Conda environment.
15. Runs `gmx --version`.
16. Verifies that a GPU build actually reports CUDA support.
17. Writes a reproducibility record into the Conda environment.

---

## 📄 Build record

Every successful installation writes:

```text
$CONDA_PREFIX/GROMACS_2026.3_BUILD_INFO.txt
```

This records information including:

- GROMACS source URL
- source checksum
- installation date
- Conda environment
- installation prefix
- whether CUDA was enabled
- CUDA version, when applicable
- full `gmx --version` output

Example:

```bash
cat "$CONDA_PREFIX/GROMACS_2026.3_BUILD_INFO.txt"
```

---

## 🧯 Troubleshooting

### `nvidia-smi: command not found`

If this is WSL2 and the machine has an NVIDIA GPU, verify that the Windows NVIDIA driver supports WSL GPU computing.

Do not solve this by installing a Linux display driver inside WSL.

---

### GROMACS installs but reports no CUDA support

Run:

```bash
gmx --version
```

If you expected GPU support, look for:

```text
GPU support: CUDA
```

Also check:

```bash
nvidia-smi
nvcc --version
```

If the GPU was not visible when the installer started, the installer intentionally generated a CPU build.

Fix GPU visibility and rerun the installer.

---

### Check the active Conda environment

```bash
echo "$CONDA_DEFAULT_ENV"
echo "$CONDA_PREFIX"
which python
which gmx
```

For PyMACS, a typical result is:

```text
mdanalysis
/home/USER/anaconda3/envs/mdanalysis
/home/USER/anaconda3/envs/mdanalysis/bin/python
/home/USER/anaconda3/envs/mdanalysis/bin/gmx
```

---

### Limit compilation threads

By default, the installer uses:

```bash
nproc
```

build threads.

To reduce build load:

```bash
GMX_BUILD_JOBS=8 bash install_gromacs.sh
```

or edit:

```bash
BUILD_JOBS=8
```

inside the installer.

---

## 🧹 Reinstalling

The installer can be rerun in the same environment.

It rebuilds GROMACS from verified source and installs the requested version back into the active Conda prefix.

For a completely clean environment-level reinstall, the most reproducible approach is often to recreate the Conda environment and run this installer again.

---

## 📚 Official sources

GROMACS 2026.3 documentation:

https://manual.gromacs.org/current/

GROMACS 2026.3 source:

https://ftp.gromacs.org/gromacs/gromacs-2026.3.tar.gz

GROMACS installation guide:

https://manual.gromacs.org/documentation/current/install-guide/index.html

NVIDIA CUDA Linux installation guide:

https://docs.nvidia.com/cuda/cuda-installation-guide-linux/

NVIDIA CUDA on WSL guide:

https://docs.nvidia.com/cuda/wsl-user-guide/

---

## 🔗 PyMACS

This installer is designed to provide the GROMACS dependency expected by:

**PyMACS — A Python-Based Automation Suite for GROMACS Molecular Dynamics Setup, Simulation, Analysis, and Figurebook Generation**

https://github.com/schurerlab/Pymacs

Once the Conda environment contains a working `gmx` executable, standard PyMACS scripts can call GROMACS directly.

---

## 🧬 GROMACS citation and release provenance

This repository installs **GROMACS 2026.3** from the official GROMACS source archive.

Official documentation DOI:

```text
10.5281/zenodo.20845233
```

Official source-code DOI for GROMACS 2026.3:

```text
10.5281/zenodo.20845217
```

Official source MD5:

```text
7987af0c6ab939ab6e639f32d0dd260f
```

---

## 🙌 Practical takeaway

For a new PyMACS workstation:

```bash
conda activate mdanalysis
```

run the installer once, then verify:

```bash
gmx --version
```

After that, GROMACS is available whenever that environment is used.
# gromacs-installation
