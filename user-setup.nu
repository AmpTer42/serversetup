#!/usr/bin/env nu
use std/log *
use modules/system.nu *

let os_info = os-info

let os = [
  {
      name: Debian,
      group: sudo
      used: (($os_info | get ID) == debian)
  }
  {
      name: Arch
      group: wheel
      used: (($os_info | get ID_LIKE) == arch or ($os_info | get ID) == arch)
  }
  {
      name: FreeBSD
      group: wheel
      used: (($os_info | get ID) == freebsd)
  }
  {
      name: RHEL
      group: wheel
      used: (($os_info | get ID_LIKE) == fedora or ($os_info | get ID) == fedora or ($os_info | get ID) == rhel)
  }
  {
      name: OpenSUSE
      group: wheel
      used: (($os_info | get ID_LIKE) == suse or ($os_info | get ID_LIKE) == "opensuse suse")
  }
  {
      name: Ubuntu
      group: sudo
      used: (($os_info | get ID) == ubuntu)
  }
]

let used_os = $os | where used

if ($used_os | is-empty) {
  error make {
    msg: $"using unsupported OS: ($os_info | get ID)"
    label: {
      text: $"unsupported OS: ($os_info | get ID)"
      span: (metadata $os_info).span
    }
  }
}

def newuser [user: string]: nothing -> nothing {
    if ((sys users | where name == $user) != []) {
        return
    }
    if (($used_os | get --optional name.0) != FreeBSD) {
        sudocheck
        try {
            sudo -n useradd -m --shell (which nu | get path.0) -U $user
            let passwd = (openssl rand -base64 32)
            let hash   = ($passwd | openssl passwd -6 -stdin)
            sudo usermod -p $hash $user
            sudo -n chage -d 0 $user
            $"Your one-time password: ($passwd)" | save --raw --append /dev/tty
        } catch {|e|
            error make {
                msg: $"can't add user ($user): error code ($e.details.code)"
                label: {
                    text: $"can't create user ($user)"
                    span: (metadata $e.debug).span
                }
            }
        }
    } else if ((id -u) == 0) {
        try {
            pw useradd -n $user -m -s (which nu | get path.0)
        } catch {|e|
            error make {
                msg: $"can't add user ($user): error code ($e.details.code)"
                label: {
                    text: $"can't create user ($user)"
                    span: (metadata $e.debug).span
                }
            }
        }
    } else {
        error make {
            msg: "login as root and execute this script again"
            label: {
                text: $"can't create user ($user) without root permissions"
                span: (metadata $user).span
            }
        }
    }
}

def addtosudo [user: string]: nothing -> nothing {
    if ((sys users | where name == $user | get groups | flatten | find ($os | where used | get group)) != []) {
        return
    }
    let groupadd = ($os | where used | get --optional group.0)
    if (($used_os | get --optional name.0) != FreeBSD) {
        sudocheck
        try {
            sudo -n usermod -aG $groupadd $user
        } catch {|e|
            error make {
                msg: $"can't set ($groupadd) group for ($user): error code ($e.details.code)"
                label: {
                    text: $"can't add ($user) to ($groupadd)"
                    span: (metadata $e.debug).span
                }
            }
        }
    } else if ((id -u) == 0) {
        try {
            pw groupmod $groupadd -m $user
        } catch {|e|
            error make {
                msg: $"can't add ($user) to group: error code ($e.details.code)"
                label: {
                    text: $"can't add ($user) to ($groupadd)"
                    span: (metadata $e.debug).span
                }
            }
        }
    } else {
        error make {
            msg: "login as root and execute this script again"
            label: {
                text: $"can't create user ($user) without root permissions"
                span: (metadata $user).span
            }
        }
    }
}

def main [
    user: string # User that must be set up
]: nothing -> nothing {
    sudocheck
    newuser $user
    addtosudo $user
}
