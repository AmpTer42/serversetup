# users.nu - create and configure users and their groups

# Add submodules functions as functions from this module
export use ./system.nu [os-info is-root]


# table of OSes
export def os []: nothing -> table<name: string, sudogroup: string, used: bool> {
    let os_info = os-info
    [
        {
            name: Debian,
            sudogroup: sudo
            used: (($os_info | get ID) == debian)
        }
        {
            name: Arch,
            sudogroup: wheel
            used: (($os_info | get ID_LIKE) == arch or ($os_info | get ID) == arch)
        }
        {
            name: FreeBSD,
            sudogroup: wheel
            used: (($os_info | get ID) == freebsd)
        }
        {
            name: RHEL,
            sudogroup: wheel
            used: (($os_info | get ID) == rhel)
        }
        {
            name: OpenSUSE,
            sudogroup: wheel
            used: (($os_info | get ID_LIKE) == suse or ($os_info | get ID_LIKE) == "opensuse suse")
        }
        {
            name: Fedora,
            sudogroup: wheel
            used: (($os_info | get ID) == fedora)
        }
        {
            name: Ubuntu,
            sudogroup: sudo
            used: (($os_info | get ID) == ubuntu)
        }
    ]
}

# get OS info
export def used-os []: nothing -> record<name: string, sudogroup: string, used: bool, ID: string> {
    let candidates = (os | where used)
    if ($candidates | is-empty) {
        error make {
            msg: $"using unsupported OS: (os-info | get --optional ID)"
            label: {
              text: $"unsupported OS: (os-info | get --optional ID)"
              span: (metadata (os-info)).span
            }
        }
    }
    return ($candidates | first | insert ID (os-info | get ID))
}

# create user(s)
export def newusers [...users: string]: nothing -> nothing {
    if ($users | is-empty) { return }
    let nupath = (which nu | get --optional path.0)
    let existing = (sys users | get name)
    if ((used-os | get --optional name) != FreeBSD) {
        # Linux/Unix: create user, set one-time password,
        # print it to /dev/tty.
        for user in $users {
            if ($user in $existing) { continue }
            try {
                sudo -n useradd -m --shell $nupath -U $user
                let passwd = (openssl rand -base64 32)
                let hash   = ($passwd | openssl passwd -6 -stdin)
                sudo -n usermod -p $hash $user
                sudo -n chage -d 0 $user
                $"($user) one-time password: ($passwd)\n" | save --raw --append /dev/tty
            } catch {|e|
                error make {
                    msg: $"can't add user ($user): error code ($e | get --optional exit_code | default unknown)"
                    label: {
                        text: $"can't create user ($user)"
                        span: (metadata $e.debug).span
                    }
                }
            }
        }
    } else if (is-root) {
        # FreeBSD: create user without working with password.
        for user in ($users | sort) {
            if ($user in $existing) { continue }
            try {
                pw useradd -n $user -m -s $nupath
            } catch {|e|
                error make {
                    msg: $"can't add user ($user): error code ($e | get --optional exit_code | default unknown)"
                    label: {
                        text: $"can't create user ($user)"
                        span: (metadata $e.debug).span
                    }
                }
            }
        }
    } else {
        error make {
            msg: "login as root and execute this script again"
            label: {
                text: $"can't create users without root permissions"
                span: (metadata $users).span
            }
        }
    }
}

# add user(s) to group(s)
export def abgroupmod [
    users: list<string> # list of users to add to groups
    ...groups: string   # list of groups
]: nothing -> nothing {
    if (($users | is-empty) or ($groups | is-empty)) { return }
    let userdata = (sys users | sort-by id | where name != nobody | where id >= 1000)
    let freebsd = ((used-os | get --optional name) == FreeBSD)
    if ($freebsd and not (is-root)) {
        error make {
            msg: "login as root and execute this script again"
            label: {
                text: $"can't add user to group without root permissions"
                span: (metadata $users).span
            }
        }
    }
    for u in $users {
        let matches = ($userdata | where name == $u)
        if ($matches | is-empty) {
            error make {
                msg: $"can't find matches of userdata and user ($u)"
                label: {
                    text: $"there is no user ($u)"
                    span: (metadata $u).span
                }
            }
        }
        let ug = ($matches | get groups | flatten)
        for g in $groups {
            if ($g not-in $ug) {
                if $freebsd {
                    pw groupmod $g -m $u
                } else {
                    try {
                        sudo -n groupadd --force $g
                        sudo -n usermod --append --groups $g $u
                    } catch {|e|
                        error make {
                            msg: $"can't add ($u) to group ($g)"
                            label: {
                                text: $"failed with error code: ($e | get --optional exit_code | default unknown)"
                                span: (metadata $e.debug).span
                            }
                        }
                    }
                }
            }
        }
    }
}
