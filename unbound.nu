#!/usr/bin/env nu

# these functions are needed for function `method`, see below. `nsudo` and `ndoas` are needed for piping with $in variable
use modules/system.nu [is-root sudocheck doascheck nsudo ndoas]

# Install chroot directories
def chroot_inst [chroot_dir: string, method: string]: nothing -> nothing {
    let dirs = ["($chroot_dir)" "($chroot_dir)/etc/unbound" "($chroot_dir)/var/lib/unbound" "($chroot_dir)/var/log"]
    try {
        match $method {
            "sudo" => {
                for dir in $dirs {
                    sudo -n install -d -m 0755 -o root -g root $dir
                }
                sudo -n install -d -m 0755 -o unbound -g unbound ($chroot_dir)/run
            }
            "doas" => {
                for dir in $dirs {
                    sudo -n install -d -m 0755 -o root -g root $dir
                }
                doas -n install -d -m 0755 -o unbound -g unbound ($chroot_dir)/run
            }
            "root" => {
                for dir in $dirs {
                    install -d -m 0755 -o root -g root $dir
                }
                install -d -m 0755 -o unbound -g unbound ($chroot_dir)/run
            }
        }
    } catch {|e|
        error make {
            msg: $"can't get root.hints file with method ($method)"
            label: {
                text: $"script failed: ($e | get --optional exit_code)"
                span: (metadata $e.debug).span
            }
        }
    }
}

# Install root.hints in chroot
def root_hints [chroot_dir: string, method: string]: nothing -> nothing {
    try {
        match $method {
            "sudo" => {
                http get --raw https://www.iana.org/domains/root/files/root.hints | nsudo --sudo-flags [-n] 'save --raw ($chroot_dir)/var/lib/unbound/root.hints'
            }
            "doas" => {
                http get --raw https://www.iana.org/domains/root/files/root.hints | ndoas --doas-flags [-n] 'save --raw ($chroot_dir)/var/lib/unbound/root.hints'
            }
            "root" => {
                http get --raw https://www.iana.org/domains/root/files/root.hints | save --raw ($chroot_dir)/var/lib/unbound/root.hints
            }
        }
    } catch {|e|
        error make {
            msg: $"can't get root.hints file with method ($method)"
            label: {
                text: $"script failed: ($e | get --optional exit_code)"
                span: (metadata $e.debug).span
            }
        }
    }
}

# Install root.key in chroot
def anchor_key [chroot_dir: string, method: string]: nothing -> nothing {
    let root_key = $"($chroot_dir)/var/lib/unbound/root.key" # path to root.key
    try {
        match $method {
            "sudo" => {
                sudo -n unbound-anchor -a $root_key
                sudo -n chown unbound:unbound $root_key
            }
            "doas" => {
                doas -n unbound-anchor -a $root_key
                doas -n chown unbound:unbound $root_key
            }
            "root" => {
                unbound-anchor -a $root_key
                chown unbound:unbound $root_key
            }
        }
    } catch {|e|
        error make {
            msg: $"can't get root.hints file with method ($method)"
            label: {
                text: $"script failed: ($e | get --optional exit_code)"
                span: (metadata $e.debug).span
            }
        }
    }
}

# Checks what methods to gain root privileges could be used
def method []: nothing -> string {
    if (which sudo | is-not-empty) { sudocheck; return "sudo" # sudo has the highest priority
    } else if (which doas | is-not-empty) { doascheck; return "doas" # doas has second priority
    } else if (is-root) { return 'root' # root user has least priority
    } else { error make "No sudo, doas or root privileges were found, aborting" }
}

# Set up everything for Unbound in chroot directory
def main [
    chroot_dir: string = /var/lib/unbound/chroot # directory for chroot
    --no-anchor # Don't use unbound-anchor and don't get root.key (use if you haven't installed unbound package)
    --no-hints # Don't create root.hints file
    --no-chroot # Don't try to create new chroot
]: nothing -> nothing {
    let method = (method)
    if (not $no_chroot) {
        chroot_inst $chroot_dir $method
    }
    if (not $no_hints) {
        root_hints $chroot_dir $method
    }
    if (not $no_anchor) {
        anchor_key $chroot_dir $method
    }
}
