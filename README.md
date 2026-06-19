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

The script will:

1. Update the system.
2. Install prerequisites.
3. Configure the CachyOS repositories.
4. Configure the Chaotic-AUR repositories.
5. Install `yay`.
6. Install packages listed in `package-pacman.txt`.
7. Install packages listed in `aur-packages.txt`.
8. Log failed packages to:

- `pacman-failed.txt`
- `aur-failed.txt`

## Requirements

- Fresh Arch Linux installation.
- Internet connection.
- Sudo privileges.
