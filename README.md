# 🧬 GROMACS Installation

<p align="center">
  <strong>System-Wide GROMACS 2026.3 Installation for Linux / WSL2 with NVIDIA CUDA GPU Acceleration</strong>
</p>

<p align="center">
  <em>One system installation. Every Conda environment. One <code>gmx</code> command.</em>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/GROMACS-2026.3-blue?style=for-the-badge" alt="GROMACS 2026.3">
  <img src="https://img.shields.io/badge/Install-System--Wide-success?style=for-the-badge&logo=linux" alt="System-wide">
  <img src="https://img.shields.io/badge/NVIDIA-CUDA%20GPU-76B900?style=for-the-badge&logo=nvidia" alt="NVIDIA CUDA GPU">
  <img src="https://img.shields.io/badge/Linux%20%2F%20WSL2-Supported-orange?style=for-the-badge&logo=ubuntu" alt="Linux / WSL2">
</p>

---

## 🚀 Overview

This repository provides a reproducible installer for **GROMACS 2026.3** that installs GROMACS at the **system level**, not inside Conda.

It is designed for molecular-dynamics workflows such as:

**PyMACS — A Python-Based Automation Suite for GROMACS Molecular Dynamics Setup, Simulation, Analysis, and Figurebook Generation**

https://github.com/schurerlab/Pymacs

The goal is simple:

```text
base          ─┐
mdanalysis     ├──> /usr/local/bin/gmx
cgenff         │
other Conda env├──> same GROMACS installation
no Conda       ┘
```

After installation, `gmx` is available independently of which Conda environment is active.

---

## ⚡ Super Quick Start

Clone the repository:

```bash
git clone https://github.com/Joey305/gromacs-installation.git
cd gromacs-installation
```

Run:

```bash
chmod +x install_gromacs.sh
./install_gromacs.sh
hash -r
source /etc/profile.d/gromacs.sh
gmx --version
```

You may run the installer while `base`, `mdanalysis`, `cgenff`, another Conda environment, or no Conda environment is active.

**The active Conda environment does not own the installation.**

That means `gmx` is not copied into:

```text
$CONDA_PREFIX/bin/gmx
```

Instead, every environment uses the same system executable:

```text
/usr/local/bin/gmx
```

The installer requires `sudo` because GROMACS is installed under `/usr/local`.

---

## 📍 Where GROMACS is installed

The versioned installation is:

```text
/usr/local/gromacs-2026.3
```

A stable symlink points to the current version:

```text
/usr/local/gromacs
    -> /usr/local/gromacs-2026.3
```

The global command is exposed as:

```text
/usr/local/bin/gmx
```

The complete layout is therefore:

```text
/usr/local/
├── gromacs-2026.3/
│   ├── bin/
│   │   ├── gmx
│   │   └── GMXRC
│   ├── lib/
│   ├── share/
│   └── ...
├── gromacs -> gromacs-2026.3
└── bin/
    └── gmx -> /usr/local/gromacs/bin/gmx
```

This follows the standard GROMACS source-install model while retaining a versioned installation for reproducibility.

If `/usr/local/gromacs` already exists from an older manual install, the installer moves it aside with a timestamped backup name before creating the stable symlink. This prevents broken links such as:

```text
/usr/local/bin/gmx -> /usr/local/gromacs/bin/gmx
```

when `/usr/local/gromacs/bin/gmx` does not actually exist.

---

## ✅ Verify the installation

Refresh Bash command lookup:

```bash
hash -r
```

Then:

```bash
gmx --version
```

Check where it comes from:

```bash
which gmx
```

Expected:

```text
/usr/local/bin/gmx
```

For an NVIDIA CUDA build, `gmx --version` should report:

```text
GROMACS version:    2026.3
GPU support:        CUDA
```

---

## 🧪 Test across Conda environments

The entire point of this repository is that GROMACS is **not** tied to a Python environment.

Test it:

```bash
conda activate base
which gmx
gmx --version
```

Then:

```bash
conda activate mdanalysis
which gmx
gmx --version
```

This is the important test for Maddison's analysis workflow: `mdanalysis` should still see `gmx`, but it should see the system copy.

Then:

```bash
conda activate cgenff
which gmx
gmx --version
```

All three should resolve to:

```text
/usr/local/bin/gmx
```

You can also test without Conda:

```bash
conda deactivate
which gmx
gmx --version
```

---

## 🎮 NVIDIA GPU support

For NVIDIA systems, GROMACS is compiled with:

```text
GMX_GPU=CUDA
GMX_OPENMP=ON
GMX_THREAD_MPI=ON
GMX_MPI=OFF
GMX_DOUBLE=OFF
GMX_BUILD_OWN_FFTW=ON
CMAKE_BUILD_TYPE=Release
```

This is intended for a normal single-node Linux/WSL workstation.

The installer checks:

```bash
nvidia-smi
```

If an NVIDIA GPU is visible, it looks for a system CUDA Toolkit.

GROMACS 2026.3 requires:

```text
CUDA >= 12.1
```

If a suitable CUDA Toolkit is already available, it is reused.

If the GPU is visible but CUDA development tools are missing, the installer can install the **system CUDA Toolkit** on supported Ubuntu/WSL2 systems.

The default preferred package is:

```text
cuda-toolkit-12-6
```

because CUDA 12.6 is among the CUDA versions reported in the GROMACS 2026 tested-platform configuration.

You can request NVIDIA's current toolkit package instead:

```bash
GMX_CUDA_PACKAGE=cuda-toolkit ./install_gromacs.sh
```

---

## 🪟 WSL2 + NVIDIA

For WSL2, the NVIDIA architecture is:

```text
Windows NVIDIA Driver
        ↓
WSL2 GPU interface
        ↓
Linux CUDA Toolkit
        ↓
GROMACS CUDA build
```

The Windows NVIDIA driver is the GPU driver.

**Do not install a Linux NVIDIA display driver inside WSL2.**

The installer uses the NVIDIA CUDA Toolkit repository appropriate for WSL and installs toolkit components rather than a Linux display driver.

Before installation:

```bash
nvidia-smi
```

If the GPU is visible there, the installer can build CUDA-enabled GROMACS.

---

## 🧠 Why system-wide instead of Conda?

Python dependencies and GROMACS solve different problems.

A PyMACS workstation may use:

```text
cgenff
```

for preparation and parameterization, then:

```text
mdanalysis
```

for trajectory analysis.

GROMACS itself should not need to be duplicated into every environment.

Instead:

```text
                       ┌── base
                       ├── cgenff
/usr/local/bin/gmx <───┼── mdanalysis
                       ├── future-env
                       └── ordinary Linux shell
```

This keeps GROMACS independent from Python package management.

---

## ⚠️ Conda shadowing

Conda normally leaves `/usr/local/bin` on `PATH`, so the system GROMACS remains available.

However, if someone later installs another package named `gromacs` **inside a specific Conda environment**, that environment may contain its own:

```text
$CONDA_PREFIX/bin/gmx
```

and that executable can take precedence over `/usr/local/bin/gmx`.

Check all visible copies with:

```bash
type -a gmx
```

For the workflow documented here, do **not** install a separate Conda GROMACS package.

The desired executable is:

```text
/usr/local/bin/gmx
```

---

## 🛠️ What the installer does

The installer:

1. Verifies Linux / WSL2 and x86_64.
2. Requests `sudo` only because `/usr/local` is a system location.
3. Installs build dependencies using APT.
4. Ensures GROMACS' required CMake version is available.
5. Uses the **system GCC/G++**, not Conda compilers.
6. Runs CMake in a clean system-oriented build environment.
7. Detects NVIDIA GPU availability.
8. Detects or installs a system CUDA Toolkit when required.
9. Downloads the official GROMACS 2026.3 source archive.
10. Verifies the official source MD5 checksum.
11. Builds FFTW automatically.
12. Compiles GROMACS with CUDA on NVIDIA systems.
13. Installs to `/usr/local/gromacs-2026.3`.
14. Creates `/usr/local/gromacs`.
15. Creates `/usr/local/bin/gmx`.
16. Creates `/etc/profile.d/gromacs.sh`.
17. Verifies the final system binary.
18. Writes a reproducibility record.

---

## 🧼 Conda isolation during the build

The installer may be launched from a terminal where Conda is active.

That is okay.

The build explicitly uses:

```text
/usr/bin/gcc
/usr/bin/g++
/usr/bin/cmake
```

and runs configuration without Conda's compiler, CMake, or library paths.

This prevents an active Python environment from becoming an accidental runtime dependency of the system GROMACS build.

---

## 🔄 Shell setup

A stable executable is created at:

```text
/usr/local/bin/gmx
```

so `gmx` should be callable immediately from normal Linux PATH configurations.

The installer also creates:

```text
/etc/profile.d/gromacs.sh
```

which loads:

```text
/usr/local/gromacs/bin/GMXRC
```

for new login shells.

For the current shell:

```bash
hash -r
source /etc/profile.d/gromacs.sh
gmx --version
```

Opening a new terminal also loads the system setup.

The installer cannot literally restart your terminal for you, but `source /etc/profile.d/gromacs.sh` gives the current shell the same GROMACS setup immediately.

---

## 📄 Reproducibility record

Every successful installation writes:

```text
/usr/local/share/GROMACS_2026.3_BUILD_INFO.txt
```

It records:

- GROMACS source URL
- official source MD5
- installation timestamp
- versioned prefix
- stable prefix
- system GCC version
- system CMake version
- CUDA status
- CUDA version and location when applicable
- complete `gmx --version` output

View it with:

```bash
cat /usr/local/share/GROMACS_2026.3_BUILD_INFO.txt
```

---

## 🧪 PyMACS

After installing:

```bash
which gmx
gmx --version
```

should work before or after:

```bash
conda activate mdanalysis
```

PyMACS can therefore call standard GROMACS commands directly:

```bash
python 1_AutomateGromacs.py
python 2_AutomateGromacs.py
python 3A_AutomateGromacs.py
```

For example:

```bash
conda activate mdanalysis
python 3A_AutomateGromacs.py
```

uses the same system:

```text
/usr/local/bin/gmx
```

as every other environment.

---

## 🧯 Troubleshooting

### `gmx: command not found`

Run:

```bash
hash -r
source /etc/profile.d/gromacs.sh
which gmx
```

Expected:

```text
/usr/local/bin/gmx
```

If `/usr/local/bin/gmx` exists but points to a missing file, rerun the latest installer. It repairs stale system links automatically after the build.

---

### Check all GROMACS executables

```bash
type -a gmx
```

The preferred one is:

```text
/usr/local/bin/gmx
```

If a Conda environment contains another `gmx`, remove the Conda GROMACS package or call the system executable explicitly:

```bash
/usr/local/bin/gmx --version
```

---

### NVIDIA GPU expected but no CUDA build

Check:

```bash
nvidia-smi
```

and:

```bash
gmx --version
```

For the GPU build, GROMACS should report:

```text
GPU support: CUDA
```

---

### CUDA compiler

Check:

```bash
nvcc --version
```

If CUDA was just installed and `nvcc` is not visible in the current shell yet, open a new terminal or try:

```bash
export PATH=/usr/local/cuda/bin:$PATH
nvcc --version
```

---

### Limit compilation threads

The default is:

```text
nproc
```

To limit compilation load:

```bash
GMX_BUILD_JOBS=8 ./install_gromacs.sh
```

---

## 📚 Official sources

GROMACS documentation:

https://manual.gromacs.org/current/

GROMACS 2026.3 source:

https://ftp.gromacs.org/gromacs/gromacs-2026.3.tar.gz

GROMACS installation guide:

https://manual.gromacs.org/documentation/current/install-guide/index.html

NVIDIA CUDA installation guide:

https://docs.nvidia.com/cuda/cuda-installation-guide-linux/

Kitware CMake APT repository:

https://apt.kitware.com/

---

## 🧬 Release provenance

This installer targets:

```text
GROMACS 2026.3
```

Official source:

```text
https://ftp.gromacs.org/gromacs/gromacs-2026.3.tar.gz
```

Official MD5:

```text
7987af0c6ab939ab6e639f32d0dd260f
```

Official documentation DOI:

```text
10.5281/zenodo.20845233
```

Official source-code DOI:

```text
10.5281/zenodo.20845217
```

---

## 🔗 PyMACS

**PyMACS: A Python-Based Automation Suite for GROMACS Molecular Dynamics Setup, Simulation, Analysis, and Figurebook Generation**

https://github.com/schurerlab/Pymacs

---

## 🙌 Practical takeaway

Install GROMACS once:

```bash
./install_gromacs.sh
```

Then use the same `gmx` everywhere:

```bash
conda activate base
gmx --version

conda activate mdanalysis
gmx --version

conda activate cgenff
gmx --version
```

The intended result is always:

```text
/usr/local/bin/gmx
```
