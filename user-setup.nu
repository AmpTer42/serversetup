#!/usr/bin/env nu
# usage: ./add-sudo-user.nu <username> [--nopasswd]
# requires nushell >= 0.90

# ---- helpers ---------------------------------------------------------------

def is-root []: nothing -> bool {
    (^id -u | complete | get stdout | str trim | into int) == 0
}

def user-exists [name: string]: nothing -> bool {
    (^id $name | complete | get exit_code) == 0
}

def is-freebsd []: nothing -> bool {
    (^uname -s | complete | get stdout | str trim) == "FreeBSD"
}

def group-exists [name: string]: nothing -> bool {
    if (is-freebsd) {
        (^pw groupshow $name | complete | get exit_code) == 0
    } else {
        (^getent group $name | complete | get exit_code) == 0
    }
}

def ensure-group [name: string] {
    if not (group-exists $name) {
        if (is-freebsd) { ^pw groupadd $name } else { ^groupadd $name }
    }
}

def add-user-to-group [user: string, group: string] {
    if (is-freebsd) {
        ^pw groupmod $group -m $user
    } else {
        ^usermod -aG $group $user
    }
}

def sudo-rule-present [group: string]: nothing -> bool {
    let needle = $"%($group) ALL="
    let in_main = (try {
        open --raw /etc/sudoers | str contains $needle
    } catch { false })
    if $in_main { return true }
    try {
        ls /etc/sudoers.d
        | where type == "file"
        | get name
        | any { |f| (open --raw $f | str contains $needle) }
    } catch { false }
}

def write-sudoers-file [path: string, content: string] {
    $"($content)\n" | save --force $path
    ^chmod 0440 $path
    ^chown root:root $path
    let chk = (^visudo -cf $path | complete)
    if $chk.exit_code != 0 {
        error make { msg: $"visudo rejected ($path):\n($chk.stderr)" }
    }
}

def detect-sudo-group []: nothing -> string {
    if ("/etc/debian_version" | path exists) {
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
                | where { |l| $l =~ '^%[a-zA-Z0-9_-]+\s+ALL=' }
            } catch { [] }
        )
        if ($hits | is-empty) { "" } else {
            $hits | parse -r '^%(?P<g>[a-zA-Z0-9_-]+)' | get g | first
        }
    }
}

def ensure-sudo-tooling [] {
    if ((^which sudo   | complete | get exit_code) != 0) {
        error make { msg: "sudo is not installed (on Arch: pacman -S sudo)" }
    }
    if ((^which visudo | complete | get exit_code) != 0) {
        error make { msg: "visudo is missing (install the sudo package)" }
    }
    let includes_dropin = (
        try { open --raw /etc/sudoers | str contains "@includedir /etc/sudoers.d" }
        catch { false }
    )
    if not $includes_dropin {
        error make { msg: "/etc/sudoers has no '@includedir /etc/sudoers.d' — drop-in files will be ignored" }
    }
}

# ---- main ------------------------------------------------------------------

def main [
    user_name: string        # имя пользователя
    --nopasswd (-n)          # разрешить sudo без пароля
] {
    if not (is-root) {
        error make { msg: "must run as root" }
    }
    ensure-sudo-tooling
    if not (user-exists $user_name) {
        error make { msg: $"user ($user_name) does not exist" }
    }

    let sudo_group = (detect-sudo-group)
    if ($sudo_group | is-empty) {
        error make { msg: "cannot detect sudo group" }
    }
    print $"detected sudo group: ($sudo_group)"

    ensure-group $sudo_group

    if ($sudo_group in [sudo wheel]) and not (sudo-rule-present $sudo_group) {
        write-sudoers-file $"/etc/sudoers.d/10-($sudo_group)" $"%($sudo_group) ALL=(ALL:ALL) ALL"
    }

    add-user-to-group $user_name $sudo_group

    if $nopasswd {
        write-sudoers-file $"/etc/sudoers.d/90-($user_name)-nopasswd" $"($user_name) ALL=(ALL:ALL) NOPASSWD: ALL"
    }

    print $"OK: ($user_name) -> group ($sudo_group)"
    ^sudo -l -U $user_name
}
