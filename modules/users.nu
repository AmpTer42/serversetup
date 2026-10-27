# users.nu - create and configure users and their groups

# Add submodules functions as functions from this module
export use ./system.nu [os-info]


# table of OSes
export def os []: nothing -> table<name: string, used: bool> {
    let os_info = os-info
    [
        {
            name: Debian,
            sudogroup: sudo
            used: (($os_info | get ID) == debian)
        }
        {
            name: Arch
            sudogroup: wheel
            used: (($os_info | get ID_LIKE) == arch or ($os_info | get ID) == arch)
        }
        {
            name: FreeBSD
            sudogroup: wheel
            used: (($os_info | get ID) == freebsd)
        }
        {
            name: RHEL
            sudogroup: wheel
            used: (($os_info | get ID_LIKE) == fedora or ($os_info | get ID) == fedora or ($os_info | get ID) == rhel)
        }
        {
            name: OpenSUSE
            sudogroup: wheel
            used: (($os_info | get ID_LIKE) == suse or ($os_info | get ID_LIKE) == "opensuse suse")
        }
        {
            name: Ubuntu
            sudogroup: sudo
            used: (($os_info | get ID) == ubuntu)
        }
    ]
}

# get OS info
export def used-os []: nothing -> table<name: string, used: bool> {
    let used_os = (os | where used | first)
    if ($used_os | is-empty) {
        error make {
            msg: $"using unsupported OS: (os-info | get ID)"
            label: {
              text: $"unsupported OS: (os-info | get ID)"
              span: (metadata (os-info)).span
            }
        }
    }
    return $used_os
}

# Выполнить команду создания пользователя для каждого имени из пайпа,
# обернув сбой в единый текст ошибки (такой же, как в оригинале
# для Linux- и FreeBSD-ветки — они совпадали дословно).
def create-users [cmd: closure]: list<string> -> nothing {
    let users = $in
    for user in $users {
        do $cmd $user
    }
}

# create user(s)
export def newusers [...users: string]: nothing -> nothing {
    let usertable = ($users | wrap user | insert create true | sort-by user)
    let new_users = ($usertable | where create | get user)
    if ($new_users | is-empty) { return }
    let cuser = (do { id -u } | complete)
    if ((used-os | get --optional name) != FreeBSD) {
        # Linux/Unix: create user, set one-time password,
        # print it to /dev/tty.
        $new_users | create-users {|user|
            try {
                sudo -n useradd -m --shell (which nu | get --optional path.0) -U $user
                let passwd = (openssl rand -base64 32)
                let hash   = ($passwd | openssl passwd -6 -stdin)
                sudo -n usermod -p $hash $user
                sudo -n chage -d 0 $user
                $"($user) one-time password: ($passwd)\n" | save --raw --append /dev/tty
            } catch {|e|
                error make {
                    msg: $"can't add user ($user): error code ($e.details.code)"
                    label: {
                        text: $"can't create user ($user)"
                        span: (metadata $e.debug).span
                    }
                }
            }
        }
    } else if ($cuser.stdout == 0 and $cuser.exit_code == 0) {
        # FreeBSD: create user without working with password.
        $new_users | create-users {|user|
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
        }
    } else {
        error make {
            msg: "login as root and execute this script again"
            label: {
                text: $"can't create users without root permissions"
                span: (metadata $cuser).span
            }
        }
    }
}

# add one user to one group using one adder
def add-to-group [
    adder: closure
]: record<user: string, group: string> -> nothing {
    let target = $in
    try {
        do $adder $target.user $target.group
    } catch {|e|
        error make {
            msg: $"can't add ($target.user) to group ($target.group)"
            label: {
                text: $"failed to add user to group"
                span: (metadata $e.debug).span
            }
        }
    }
}

# common cycle: check user, get their groups,
# add to all unexisting groups using OS-specific adder
def process-users [
    spec: record<users: list<string>, groups: list<string>
    adder: closure>
]: table<name: string, id: int, groups: list<string>> -> nothing {
    let userdata = $in
    for u in $spec.users {
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
        for g in $spec.groups {
            if ($g not-in $ug) {
                {user: $u, group: $g} | add-to-group $spec.adder
            }
        }
    }
}

# add user(s) to group(s)
export def abgroupmod [
    users: list<string> # list of users to add to groups
    ...groups: string   # list of groups
]: nothing -> nothing {
    let userdata = (sys users | sort-by id | where name != nobody | where id >= 1000)
    let cuser = (do { id -u } | complete)
    if ((used-os | get --optional name) != FreeBSD) {
        $userdata | process-users {
            users: $users
            groups: $groups
            adder: {|u, g|
                try {
                    sudo -n groupadd --force $g
                    sudo -n usermod --append --groups $g $u
                } catch {|e|
                    error make {
                        msg: "can't use given closure"
                        label: {
                            text: $"failed with error code: ($e.details.code)"
                            span: (metadata $e.debug).span
                        }
                    }
                }
            }
        }
    } else if ($cuser.stdout == 0 and $cuser.stderr == 0) {
        $userdata | process-users {
            users: $users
            groups: $groups
            adder: {|u, g|
                pw groupmod $g -m $u
            }
        }
    } else {
        error make {
            msg: "login as root and execute this script again"
            label: {
                text: $"can't add user to group without root permissions"
                span: (metadata ($cuser)).span
            }
        }
    }
}
