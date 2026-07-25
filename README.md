# My-packagelist

Personal Arch Linux package lists and bootstrap script.

## Contents

- `package-pacman.txt`
  - Packages installed with `pacman`
  - Includes packages from:
    - Official Arch repositories
    - CachyOS repositories
    - Chaotic-AUR repositories

- `aur-packages.txt`
  - Packages installed with `yay`

- `repo-install.sh`
  - Bootstraps a fresh Arch Linux installation.

## Usage

Clone the repository:

```bash
git clone https://github.com/jerryjay45/My-packagelist.git
cd My-packagelist
```

Make the script executable:

```bash
chmod +x repo-install.sh
```

Run the installer:

```bash
./repo-install.sh
```

The script will prompt you interactively, then:

1. Optionally set up the CachyOS repositories.
2. Optionally set up the Chaotic-AUR repository.
3. Optionally install `yay`.
4. Optionally set up DaVinci Resolve with Rusticl OpenCL support (for AMD Polaris-generation GPUs like the RX 470/480/570/580/590, which are no longer supported by current ROCm).
5. Verify `pacman.conf` is valid before continuing.
6. Update the system.
7. Load `package-pacman.txt` and `aur-packages.txt`, either from GitHub or from the local cloned copy (your choice).
8. Install every package in both lists via `yay`.
9. Log everything to a timestamped `install-<date>-<time>.log`, and log any packages that failed to install to `failed-packages.txt`.

### DaVinci Resolve step (optional)

If enabled, this step:

- Installs `opencl-mesa` and `ocl-icd` (Rusticl OpenCL support).
- Removes `rocm-opencl-runtime` if present, since it conflicts with Rusticl detection on pre-Vega AMD GPUs.
- Adds your user to the `render` and `video` groups.
- Installs `davinci-resolve` and `davinci-resolve-checker` from the AUR via `yay`.
- Patches the DaVinci Resolve `.desktop` launcher so it always runs with `RUSTICL_ENABLE=radeonsi`, so it works from your app menu without manual environment variables.

This step assumes an AMD GPU. If run on a machine with an NVIDIA or Intel-only GPU, just answer "no" to the prompt.

## Requirements

- Fresh Arch Linux installation.
- Internet connection.
- Sudo privileges.
