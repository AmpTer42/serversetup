# The auto setup for servers

![badge](https://gitea-ts.axolotl-rohu.ts.net/main-team/serversetup/actions/workflows/ci.yml/badge.svg)

1. Firstly, use the `install-nu.sh` file to install Nushell (it's a bootstrap script because everything else uses Nu)
2. Add user with sudo: `nu setup-user.nu vlodik`
3. Copy one-time password from TTY and login with it (system will force you to change password)
