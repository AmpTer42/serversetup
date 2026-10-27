# users.nu - create and configure users and their groups
export use ./system.nu *


def os []: nothing -> table<name: string, used: bool> {
    let os_info = os-info
    [
        {
            name: Debian,
            used: (($os_info | get ID) == debian)
        }
        {
            name: Arch
            used: (($os_info | get ID_LIKE) == arch or ($os_info | get ID) == arch)
        }
        {
            name: FreeBSD
            used: (($os_info | get ID) == freebsd)
        }
        {
            name: RHEL
            used: (($os_info | get ID_LIKE) == fedora or ($os_info | get ID) == fedora or ($os_info | get ID) == rhel)
        }
        {
            name: OpenSUSE
            used: (($os_info | get ID_LIKE) == suse or ($os_info | get ID_LIKE) == "opensuse suse")
        }
        {
            name: Ubuntu
            used: (($os_info | get ID) == ubuntu)
        }
    ]
}

def used-os []: nothing -> table<name: string, used: bool> {
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

# create user(s)
export def newusers [...users: string]: nothing -> nothing {
    let usertable = ($users | wrap user | insert created false | sort-by user)
    mut usertable2 = $usertable
    for i in ($usertable | get user) {
        if (sys users | where name == $i | is-empty) {
            $usertable2 = ($usertable | where user == $i | update created true | prepend ($usertable2 | where user != $i))
        }
    }
    $usertable2 = $usertable2 | sort-by user
    let new_users = ($usertable2 | where (not (created)) | get user)
    if ($new_users | is-empty) { return }
    let cuser = (do { id -u } | complete)
    for user in $new_users {
      if ((used-os | get --optional name) != FreeBSD) {
          sudocheck
          try {
              sudo -n useradd -m --shell (which nu | get path.0) -U $user
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
      } else if ($cuser.stdout == 0 and $cuser.exit_code == 0) {
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
}

# add user(s) to groups
export def bgroupmod [
    users: list<string> 
    ...groups: string   
    ]: nothing -> nothing {
    let userdata = (sys users)
    for u in $users {
        if ($userdata | where name == $u | is-empty) {
            error make $"can't find user ($u)"
        }
    }
}
