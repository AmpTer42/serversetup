#!/usr/bin/env nu
# user-setup.nu - create users with a one-time password
# and add them to the OS sudo/wheel group.

use modules/system.nu [is-root os-info sudocheck]
use modules/users.nu [newusers abgroupmod used-os os]

let used_os = used-os

# add existing users to sudo if they weren't already added
def addtosudo [...users: string]: nothing -> nothing {
    if ($users | is-empty) { return }
    let groupadd = (os | where used | get --optional sudogroup)
    # find users that are already members of the sudo group
    let sudoers = (sys users | where name in $users | where ($it.groups | any {|g| $g == $groupadd}) | get name)
    let missing = ($users | where $it not-in $sudoers)
    if ($missing | is-empty) { return }
    if (($used_os | get --optional name) != FreeBSD) {
        sudocheck
    } else if (not (is-root)) {
        error make {
            msg: "login as root and execute this script again"
            label: {
                text: $"can't add users to ($groupadd) without root permissions"
                span: (metadata $users).span
            }
        }
    }
    abgroupmod $missing ...$groupadd
}

# setup user(s)
def main [
    ...user: string # Users that must be set up
]: nothing -> nothing {
    if ($user | is-empty) {
        error make {
            msg: "no users provided"
            label: {
                text: "provide at least one username"
                span: (metadata $user).span
            }
        }
    }
    sudocheck
    newusers ...$user
    addtosudo ...$user
}
