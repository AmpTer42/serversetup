# serversetup

![badge](https://gitea-ts.axolotl-rohu.ts.net/main-team/serversetup/actions/workflows/ci.yml/badge.svg)

Idempotent server provisioning toolkit written in [Nushell](https://www.nushell.sh/).
Supported distributions: Debian, Ubuntu, Arch (and derivatives), Fedora, RHEL, openSUSE, FreeBSD (users only).

## Quick start

1. Bootstrap Nushell (bash installer, registers `nu` in `/etc/shells`):

    ```sh
    sudo bash install-nu.sh
    ```

2. Create a user with sudo access:

    ```sh
    nu user-setup.nu vlodik
    ```

3. Copy the one-time password printed to the TTY and log in with it
   (the system will force a password change on first login).

## Scripts

| Script | Purpose |
|---|---|
| `install-nu.sh` | Bash bootstrap: installs Nushell, adds it to `/etc/shells` |
| `user-setup.nu` | Create a user, set a one-time password, add them to the sudo/wheel group |
| `docker-setup.nu` | Set up the Docker repo, install Docker Engine + plugins, enable the service, add users to the `docker` group |
| `ts-setup.nu` | Set up the Tailscale repo, install and start `tailscaled`, authenticate with an auth key |
| `ctk-setup.nu` | Install the NVIDIA Container Toolkit, generate CDI spec, configure the Docker runtime |

Usage examples:

```sh
nu docker-setup.nu vlodik        # installs Docker and adds vlodik to the docker group
nu ts-setup.nu $TS_AUTHKEY       # installs Tailscale and brings the node up
nu ctk-setup.nu                  # installs and configures NVIDIA Container Toolkit
```

All scripts are idempotent: already-installed packages, existing repos, and existing group memberships are skipped.

## Modules

Shared logic lives in `modules/` and is reused by the setup scripts:

- `pkg.nu` — package-manager abstraction (apt, dnf, pacman, zypper, snap, pkg) with detection, refresh, and idempotent installs
- `system.nu` — `/etc/os-release` parsing, sudo checks, piped elevated commands (`nsudo`), systemd service helpers
- `users.nu` — OS detection table, user creation, group management

## Requirements

- One of the supported distributions listed above
- `sudo` access (scripts run commands non-interactively via `sudo -n`)
- Run `install-nu.sh` first — everything else depends on Nushell
