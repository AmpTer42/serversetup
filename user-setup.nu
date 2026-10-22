#!/usr/bin/env -S nu --stdin
# usage: ./add-sudo-user.nu <username> [--nopasswd]
# requires nushell >= 0.90

# ---- helpers ---------------------------------------------------------------

def is-freebsd []: nothing -> bool {
    (^uname -s | complete | get stdout | str trim) == FreeBSD
}

def sudo-rule-present [group: string]: nothing -> bool {
    let needle = $"%($group) ALL="
    let in_main = (try {
        open --raw /etc/sudoers | str contains $needle
    } catch { false })
    if $in_main { return true }
    try {
        ls /etc/sudoers.d
        | where type == file
        | get name
        | any {|f| open --raw $f =~ $needle }
    } catch { false }
}

def write-sudoers-file [path: path, content: string]: any -> error {
    $"($content)\n" | save --force $path
    chmod 0440 $path
    chown root:root $path
    let chk = (visudo -cf $path | complete)
    if $chk.exit_code != 0 {
        let path_span = (metadata $path).span
        error make {
            msg: $"visudo rejected ($path):\n($chk.stderr)"
            label: {
                text: "this sudoers file is invalid"
                span: $path_span
            }
            help: "check the syntax of the generated sudoers content"
        }
    }
}

def ensure-sudo-tooling []: any -> error {
    if ((^which sudo   | complete | get exit_code) != 0) {
        error make {msg: "sudo is not installed (on Arch: pacman -S sudo)"}
    }
    if ((^which visudo | complete | get exit_code) != 0) {
        error make {msg: "visudo is missing (install the sudo package)"}
    }
    let includes_dropin = (
        try { open --raw /etc/sudoers | str contains "@includedir /etc/sudoers.d" }
        catch { false }
    )
    if not $includes_dropin {
        error make {
    msg: "/etc/sudoers has no '@includedir /etc/sudoers.d' — drop-in files will be ignored"
}
    }
}

# ---- main ------------------------------------------------------------------

def main [user_name: string, --nopasswd (-n)]: any -> string {
    if not ((id -u | complete | get stdout | str trim | into int) == 0) {
        error make {msg: "must run as root"}
    }
    ensure-sudo-tooling
    if not ((id $user_name | complete | get exit_code) == 0) {
        error make {msg: $"user ($user_name) does not exist"}
    }

    let sudo_group = (if ("/etc/debian_version" | path exists) {
        "sudo"
    } else if (("/etc/redhat-release" | path exists) or ("/etc/fedora-release" | path exists)) {
        "wheel"
    } else if ("/etc/arch-release" | path exists) {          # ← Arch
        "wheel"
    } else if (is-freebsd) {
        "wheel"
    } else {
        let hits = (
            try {
                open --raw /etc/sudoers
                | lines
                | where $it =~ '^%[a-zA-Z0-9_-]+\s+ALL='
            } catch { [] }
        )
        if ($hits | is-empty) { "" } else {
            $hits | parse --regex '^%(?P<g>[a-zA-Z0-9_-]+)' | get g | first
        }
    })
    if ($sudo_group | is-empty) {
        error make {msg: "cannot detect sudo group"}
    }
    print $"detected sudo group: ($sudo_group)"

    if not (if (is-freebsd) {
        (pw groupshow $sudo_group | complete | get exit_code) == 0
    } else {
        (getent group $sudo_group | complete | get exit_code) == 0
    }) {
        if (is-freebsd) { pw groupadd $sudo_group } else { groupadd $sudo_group }
    }

    if ($sudo_group in [sudo wheel]) and not (sudo-rule-present $sudo_group) {
        write-sudoers-file $"/etc/sudoers.d/10-($sudo_group)" $"%($sudo_group) ALL=(ALL:ALL) ALL"
    }

    if (is-freebsd) {
        pw groupmod $sudo_group -m $user_name
    } else {
        usermod -aG $sudo_group $user_name
    }

    if $nopasswd {
        write-sudoers-file $"/etc/sudoers.d/90-($user_name)-nopasswd" $"($user_name) ALL=(ALL:ALL) NOPASSWD: ALL"
    }

    print $"OK: ($user_name) -> group ($sudo_group)"
    sudo -l -U $user_name
}
