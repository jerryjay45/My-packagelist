# My-packagelist

Personal Arch Linux package lists and bootstrap script. The lists are a trimmed-down set aimed at a fresh install that is ready for **gaming, development and video editing**.

## Contents

- `package-pacman.txt`
  - Packages installed with `pacman`
  - Includes packages from:
    - Official Arch repositories (including `multilib`)
    - CachyOS repositories
    - Chaotic-AUR repositories

- `aur-packages.txt`
  - Packages installed with `yay`

- `repo-install.sh`
  - Bootstraps a fresh Arch Linux installation.

A package only needs to appear in one of the two lists. The script doesn't rely on which file a package is in: it checks what the enabled repositories actually provide and sends everything else to `yay`.

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

1. Enable the `[multilib]` repository (always; the lists contain `lib32-*` packages, Steam and Wine).
2. Optionally set up the CachyOS repositories.
3. Optionally set up the Chaotic-AUR repository.
4. Verify `pacman.conf` is valid, then run a full system update.
5. Optionally install `yay` (after the update, so there is no partial upgrade). `yay` is required, so the script stops if it isn't installed.
6. Load `package-pacman.txt` and `aur-packages.txt`, either from GitHub or from the local cloned copy (your choice).
7. Install kernel headers for every installed kernel if the lists contain any `-dkms` package.
8. Install everything: one `pacman` transaction for packages in the enabled repos, then one `yay` run for the AUR packages. If a bulk run fails, it retries one package at a time so a single bad package doesn't block the rest.
9. Optionally set up DaVinci Resolve with Rusticl OpenCL support (for AMD Polaris-generation GPUs like the RX 470/480/570/580/590, which are no longer supported by current ROCm).
10. Log everything to a timestamped `install-<YYYYMMDD>-<HHMMSS>.log`, and log any packages that failed to install to `failed-packages.txt`.

sudo is authenticated once at the start and kept alive in the background, so long AUR builds don't stop to ask for your password again.

### CachyOS repositories

The script checks which x86-64 level your CPU supports and adds **only** the matching repos, following the [CachyOS instructions](https://wiki.cachyos.org/features/optimized_repos/):

| CPU support | Repos added |
|---|---|
| x86-64-v4 | `cachyos-v4`, `cachyos-core-v4`, `cachyos-extra-v4`, `cachyos` |
| x86-64-v3 | `cachyos-v3`, `cachyos-core-v3`, `cachyos-extra-v3`, `cachyos` |
| neither | `cachyos` only |

They are inserted **above** `[core]` in `pacman.conf` (required, otherwise the Arch packages win), and a timestamped backup `pacman.conf.bak-<date>` is made first.

Not handled: the separate `znver4` repos for AMD Zen 4/5. Those use the v4 level here.

> The `[cachyos]` repo ships CachyOS's patched `pacman`. If you'd rather keep Arch's `pacman`, skip the CachyOS prompt and add only the `-v3`/`-v4` repos yourself.

### DaVinci Resolve step (optional)

If enabled, this step:

- Installs `opencl-mesa`, `ocl-icd` and `clinfo` (Rusticl OpenCL support, plus the tool used to verify it).
- Removes `rocm-opencl-runtime` if present, since it conflicts with Rusticl detection on pre-Vega AMD GPUs.
- Adds your user to the `render` and `video` groups.
- Installs `davinci-resolve` and `davinci-resolve-checker` from the AUR via `yay`.
- Patches the DaVinci Resolve `.desktop` launcher so it always runs with `RUSTICL_ENABLE=radeonsi`, so it works from your app menu without manual environment variables.

This step assumes an AMD GPU. If run on a machine with an NVIDIA or Intel-only GPU, just answer "no" to the prompt.

## Notes on the package list

- It targets an **AMD GPU**: it includes `mesa`, `vulkan-radeon` and `lib32-vulkan-radeon` (Steam needs a 32-bit Vulkan driver), plus `xf86-video-amdgpu`, `amdgpu_top` and `lact-git`. Swap these for the right driver packages on NVIDIA or Intel.
- No kernel is listed. Install one (`linux`, `linux-zen`, `linux-cachyos`, …) during the base install; the script then installs the matching `-headers` package automatically when a DKMS package is in the list.
- Several `-git` packages come from Chaotic-AUR. If you decline the Chaotic prompt, `yay` builds them from source instead, which works but takes much longer.

## Requirements

- Fresh Arch Linux installation (x86_64).
- Internet connection.
- Sudo privileges (the script refuses to run as root).
