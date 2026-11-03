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
I don't want to update README.md whenever I add new script, so you can find description of every script above `def main`.

You can run `<script> --help` to get info about script.
## Modules
Shared logic lives in `modules/` and is reused by the setup scripts.

Full information about functions is above function definitions in code, so I don't need to update README.md and it's used by LSP servers.
## Requirements
- One of the supported distributions (see your script's code)
- `sudo` access (scripts run commands non-interactively via `sudo -n`, but `sudo -v` is executed inside script), some scripts work with passwordless `doas` and even root access
- Run `install-nu.sh` first — everything else depends on Nushell
- Brain to read and analyze code comments (optional)
