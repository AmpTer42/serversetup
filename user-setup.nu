#!/usr/bin/env nu
use modules/system.nu [is-root os-info sudocheck]
use modules/users.nu [newusers abgroupmod used-os os]

let used_os = used-os

# add existing user to sudo if they weren't already added
def addtosudo [user: string]: nothing -> nothing {
    let groupadd = (os | where used | get --optional sudogroup.0)
    if ((sys users | where name == $user | get groups | flatten | find $groupadd) != []) {
        return
    }
    if (($used_os | get --optional name.0) != FreeBSD) {
        sudocheck
    } else if (not (is-root)) {
        error make {
            msg: "login as root and execute this script again"
            label: {
                text: $"can't add user ($user) to ($groupadd) without root permissions"
                span: (metadata $user).span
            }
        }
    }
    abgroupmod [$user] $groupadd
}

# setup user
def main [
    user: string # User that must be set up
]: nothing -> nothing {
    sudocheck
    newusers $user
    addtosudo $user
}
