#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# GROMACS 2026.3 - System-wide NVIDIA CUDA installer
# Linux / WSL2, x86_64
#
# Installs one shared GROMACS into /usr/local so the same `gmx`
# command works from base, mdanalysis, cgenff, or no Conda env.
# ============================================================

GROMACS_VERSION="2026.3"
GROMACS_URL="https://ftp.gromacs.org/gromacs/gromacs-${GROMACS_VERSION}.tar.gz"
GROMACS_MD5="7987af0c6ab939ab6e639f32d0dd260f"
MIN_CMAKE_VERSION="3.28"
MIN_CUDA_VERSION="12.1"

VERSIONED_PREFIX="/usr/local/gromacs-${GROMACS_VERSION}"
STABLE_PREFIX="/usr/local/gromacs"
GMX_LINK="/usr/local/bin/gmx"
BUILD_INFO="/usr/local/share/GROMACS_${GROMACS_VERSION}_BUILD_INFO.txt"

# Override if desired, for example:
#   GMX_BUILD_JOBS=8 ./install_gromacs.sh
BUILD_JOBS="${GMX_BUILD_JOBS:-$(nproc)}"

# If CUDA is needed but nvcc is missing, this APT package is installed.
# Override with GMX_CUDA_PACKAGE=cuda-toolkit to use NVIDIA's moving package.
CUDA_APT_PACKAGE="${GMX_CUDA_PACKAGE:-cuda-toolkit-12-6}"

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

sudo_cmd() {
    sudo "$@"
}

version_ge() {
    python3 - "$1" "$2" <<'PY'
import re
import sys

def parts(version):
    found = re.findall(r"\d+", version)
    return tuple(int(x) for x in found[:3])

left = parts(sys.argv[1])
right = parts(sys.argv[2])
width = max(len(left), len(right))
left += (0,) * (width - len(left))
right += (0,) * (width - len(right))
sys.exit(0 if left >= right else 1)
PY
}

apt_install() {
    sudo_cmd apt-get update
    sudo_cmd DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
}

is_wsl() {
    grep -qi microsoft /proc/version 2>/dev/null
}

ubuntu_codename() {
    . /etc/os-release
    printf '%s\n' "${VERSION_CODENAME:-}"
}

ensure_platform() {
    [[ "$(uname -s)" == "Linux" ]] || \
        die "This installer is intended for Linux or WSL2."

    [[ "$(uname -m)" == "x86_64" ]] || \
        die "This installer currently targets x86_64 Linux/WSL2."

    command -v sudo >/dev/null 2>&1 || \
        die "sudo is required because GROMACS is installed under /usr/local."

    command -v apt-get >/dev/null 2>&1 || \
        die "This installer uses apt-get and is intended for Ubuntu/Debian systems."
}

ensure_base_dependencies() {
    banner "Installing system build dependencies"

    apt_install \
        build-essential \
        ca-certificates \
        curl \
        gnupg \
        lsb-release \
        make \
        pkg-config \
        python3 \
        tar

    if ! command -v /usr/bin/cmake >/dev/null 2>&1; then
        apt_install cmake
    fi

    if ! version_ge "$(/usr/bin/cmake --version | head -n 1)" "${MIN_CMAKE_VERSION}"; then
        install_kitware_cmake
    fi

    version_ge "$(/usr/bin/cmake --version | head -n 1)" "${MIN_CMAKE_VERSION}" || \
        die "GROMACS ${GROMACS_VERSION} requires CMake ${MIN_CMAKE_VERSION}+."

    [[ -x /usr/bin/gcc && -x /usr/bin/g++ ]] || \
        die "System GCC/G++ were not found after installing build-essential."

    echo "C compiler   : /usr/bin/gcc ($(/usr/bin/gcc -dumpfullversion -dumpversion))"
    echo "C++ compiler : /usr/bin/g++ ($(/usr/bin/g++ -dumpfullversion -dumpversion))"
    echo "CMake        : $(/usr/bin/cmake --version | head -n 1)"
    echo "Build threads: ${BUILD_JOBS}"
}

install_kitware_cmake() {
    banner "Installing newer system CMake"

    local codename
    codename="$(ubuntu_codename)"
    [[ -n "${codename}" ]] || \
        die "Could not determine Ubuntu/Debian codename for Kitware CMake setup."

    apt_install ca-certificates curl gnupg

    sudo_cmd install -d -m 0755 /etc/apt/keyrings
    curl -fsSL https://apt.kitware.com/keys/kitware-archive-latest.asc |
        gpg --dearmor |
        sudo_cmd tee /etc/apt/keyrings/kitware-archive-keyring.gpg >/dev/null

    echo "deb [signed-by=/etc/apt/keyrings/kitware-archive-keyring.gpg] https://apt.kitware.com/ubuntu/ ${codename} main" |
        sudo_cmd tee /etc/apt/sources.list.d/kitware.list >/dev/null

    apt_install cmake
}

install_cuda_repo() {
    banner "Configuring NVIDIA CUDA Toolkit repository"

    local distro
    if is_wsl; then
        distro="wsl-ubuntu"
    else
        . /etc/os-release
        case "${ID:-}-${VERSION_ID:-}" in
            ubuntu-24.04) distro="ubuntu2404" ;;
            ubuntu-22.04) distro="ubuntu2204" ;;
            *)
                die "Automatic CUDA Toolkit setup currently supports Ubuntu 22.04, Ubuntu 24.04, and WSL2 Ubuntu. Install CUDA ${MIN_CUDA_VERSION}+ manually, then rerun."
                ;;
        esac
    fi

    local pin_url="https://developer.download.nvidia.com/compute/cuda/repos/${distro}/x86_64/cuda-${distro}.pin"
    local keyring_url="https://developer.download.nvidia.com/compute/cuda/repos/${distro}/x86_64/cuda-keyring_1.1-1_all.deb"
    local tmp_deb
    tmp_deb="$(mktemp -t cuda-keyring-XXXXXX.deb)"

    curl -fsSL "${pin_url}" -o /tmp/cuda-repository-pin-600
    sudo_cmd mv /tmp/cuda-repository-pin-600 /etc/apt/preferences.d/cuda-repository-pin-600

    curl -fsSL "${keyring_url}" -o "${tmp_deb}"
    sudo_cmd dpkg -i "${tmp_deb}"
    rm -f "${tmp_deb}"

    apt_install "${CUDA_APT_PACKAGE}"
}

cuda_version() {
    "${NVCC_BIN}" --version |
        sed -n 's/.*release \([0-9][0-9.]*\).*/\1/p' |
        head -n 1
}

find_nvcc() {
    if command -v nvcc >/dev/null 2>&1; then
        command -v nvcc
        return 0
    fi

    if [[ -x /usr/local/cuda/bin/nvcc ]]; then
        printf '%s\n' /usr/local/cuda/bin/nvcc
        return 0
    fi

    local candidate
    for candidate in /usr/local/cuda-*/bin/nvcc; do
        if [[ -x "${candidate}" ]]; then
            printf '%s\n' "${candidate}"
            return 0
        fi
    done

    return 1
}

ensure_cuda_if_gpu() {
    GPU_BUILD=0
    CUDA_ROOT=""
    CUDA_VERSION=""
    NVCC_BIN=""

    banner "Detecting GPU"

    if ! command -v nvidia-smi >/dev/null 2>&1 || ! nvidia-smi -L >/dev/null 2>&1; then
        echo "No NVIDIA GPU is visible through nvidia-smi."
        echo "GROMACS will be built with CPU + OpenMP + thread-MPI support."
        return
    fi

    GPU_BUILD=1
    echo "NVIDIA GPU detected:"
    nvidia-smi -L

    if NVCC_BIN="$(find_nvcc)"; then
        CUDA_VERSION="$(cuda_version)"
    fi

    if [[ -z "${CUDA_VERSION}" ]] || ! version_ge "${CUDA_VERSION}" "${MIN_CUDA_VERSION}"; then
        echo
        echo "CUDA Toolkit ${MIN_CUDA_VERSION}+ was not found."
        echo "Installing system CUDA Toolkit package: ${CUDA_APT_PACKAGE}"
        install_cuda_repo
        hash -r
        NVCC_BIN="$(find_nvcc)" || \
            die "CUDA Toolkit installation finished, but nvcc is not available."
        CUDA_VERSION="$(cuda_version)"
    fi

    version_ge "${CUDA_VERSION}" "${MIN_CUDA_VERSION}" || \
        die "GROMACS ${GROMACS_VERSION} requires CUDA ${MIN_CUDA_VERSION}+; found ${CUDA_VERSION}."

    CUDA_ROOT="$(dirname "$(dirname "$(readlink -f "${NVCC_BIN}")")")"

    echo "CUDA compiler : ${NVCC_BIN}"
    echo "CUDA version  : ${CUDA_VERSION}"
    echo "CUDA root     : ${CUDA_ROOT}"
}

download_source() {
    banner "Downloading GROMACS ${GROMACS_VERSION}"

    WORK_ROOT="$(mktemp -d -t gromacs-${GROMACS_VERSION}-XXXXXX)"
    TARBALL="${WORK_ROOT}/gromacs-${GROMACS_VERSION}.tar.gz"
    SOURCE_DIR="${WORK_ROOT}/gromacs-${GROMACS_VERSION}"
    BUILD_DIR="${SOURCE_DIR}/build"

    cleanup() {
        rm -rf "${WORK_ROOT}"
    }
    trap cleanup EXIT

    curl -fL --retry 3 --retry-delay 2 "${GROMACS_URL}" -o "${TARBALL}"

    python3 - "${TARBALL}" "${GROMACS_MD5}" <<'PY'
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
}

configure_build() {
    banner "Configuring GROMACS"

    local clean_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    if [[ -n "${NVCC_BIN:-}" ]]; then
        clean_path="$(dirname "${NVCC_BIN}"):${clean_path}"
    fi

    CMAKE_ARGS=(
        -S "${SOURCE_DIR}"
        -B "${BUILD_DIR}"
        "-DCMAKE_INSTALL_PREFIX=${VERSIONED_PREFIX}"
        "-DCMAKE_BUILD_TYPE=Release"
        "-DCMAKE_C_COMPILER=/usr/bin/gcc"
        "-DCMAKE_CXX_COMPILER=/usr/bin/g++"
        "-DGMX_BUILD_OWN_FFTW=ON"
        "-DGMX_MPI=OFF"
        "-DGMX_THREAD_MPI=ON"
        "-DGMX_OPENMP=ON"
        "-DGMX_DOUBLE=OFF"
    )

    if [[ "${GPU_BUILD}" -eq 1 ]]; then
        CMAKE_ARGS+=(
            "-DGMX_GPU=CUDA"
            "-DCUDAToolkit_ROOT=${CUDA_ROOT}"
            "-DCMAKE_CUDA_HOST_COMPILER=/usr/bin/g++"
        )
    else
        CMAKE_ARGS+=("-DGMX_GPU=OFF")
    fi

    env -i \
        HOME="${HOME}" \
        PATH="${clean_path}" \
        TERM="${TERM:-xterm}" \
        /usr/bin/cmake "${CMAKE_ARGS[@]}"
}

build_and_install() {
    banner "Building GROMACS"
    /usr/bin/cmake --build "${BUILD_DIR}" --parallel "${BUILD_JOBS}"

    banner "Installing system-wide"
    sudo_cmd /usr/bin/cmake --install "${BUILD_DIR}"

    sudo_cmd ln -sfn "${VERSIONED_PREFIX}" "${STABLE_PREFIX}"
    sudo_cmd ln -sfn "${STABLE_PREFIX}/bin/gmx" "${GMX_LINK}"

    sudo_cmd tee /etc/profile.d/gromacs.sh >/dev/null <<EOF
# GROMACS ${GROMACS_VERSION}
if [ -f "${STABLE_PREFIX}/bin/GMXRC" ]; then
    . "${STABLE_PREFIX}/bin/GMXRC"
fi
EOF

    hash -r
}

verify_installation() {
    banner "Verifying GROMACS"

    [[ -x "${VERSIONED_PREFIX}/bin/gmx" ]] || \
        die "Installation completed but ${VERSIONED_PREFIX}/bin/gmx does not exist."

    [[ -x "${GMX_LINK}" ]] || \
        die "Installation completed but ${GMX_LINK} does not exist."

    GMX_VERSION_OUTPUT="$("${GMX_LINK}" --version)"
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
}

write_build_record() {
    banner "Writing reproducibility record"

    local conda_env="${CONDA_DEFAULT_ENV:-none}"
    local conda_prefix="${CONDA_PREFIX:-none}"

    {
        echo "GROMACS source: ${GROMACS_URL}"
        echo "GROMACS MD5: ${GROMACS_MD5}"
        echo "Installed: $(date -Is)"
        echo "Versioned prefix: ${VERSIONED_PREFIX}"
        echo "Stable prefix: ${STABLE_PREFIX}"
        echo "Global executable: ${GMX_LINK}"
        echo "Launched from Conda environment: ${conda_env}"
        echo "Launched from Conda prefix: ${conda_prefix}"
        echo "System GCC: $(/usr/bin/gcc --version | head -n 1)"
        echo "System G++: $(/usr/bin/g++ --version | head -n 1)"
        echo "System CMake: $(/usr/bin/cmake --version | head -n 1)"
        echo "GPU build requested: ${GPU_BUILD}"
        if [[ "${GPU_BUILD}" -eq 1 ]]; then
            echo "CUDA version: ${CUDA_VERSION}"
            echo "CUDA root: ${CUDA_ROOT}"
        fi
        echo
        printf '%s\n' "${GMX_VERSION_OUTPUT}"
    } | sudo_cmd tee "${BUILD_INFO}" >/dev/null

    echo "Build record:"
    echo "  ${BUILD_INFO}"
}

finish_message() {
    banner "Installation complete"

    echo "GROMACS executable:"
    echo "  ${GMX_LINK}"
    echo
    echo "Versioned installation:"
    echo "  ${VERSIONED_PREFIX}"
    echo
    echo "Stable installation:"
    echo "  ${STABLE_PREFIX}"
    echo
    echo "Use it from any shell or Conda environment:"
    echo
    echo "  hash -r"
    echo "  source /etc/profile.d/gromacs.sh"
    echo "  gmx --version"
    echo
    echo "For example:"
    echo
    echo "  conda activate mdanalysis"
    echo "  which gmx"
    echo "  gmx --version"
}

banner "GROMACS ${GROMACS_VERSION} System Installer"

ensure_platform

if [[ -n "${CONDA_PREFIX:-}" ]]; then
    echo "Conda environment detected: ${CONDA_DEFAULT_ENV:-unknown}"
    echo "That is okay. This installer will NOT install into Conda."
    echo "It will install one shared system GROMACS under /usr/local."
else
    echo "No active Conda environment detected."
    echo "That is okay. This installer installs system-wide under /usr/local."
fi

ensure_base_dependencies
ensure_cuda_if_gpu
download_source
configure_build
build_and_install
verify_installation
write_build_record
finish_message
