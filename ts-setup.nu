#!/usr/bin/env nu
use modules/pkg.nu [detect-pm ensure-installed]
use modules/system.nu [sudocheck nsudo start-services]
use modules/users.nu [used-os os-info]

let used_os = used-os
let os_name = ($used_os | get name)
let os_id = ($used_os | get ID)
let pm = (detect-pm | first)

# add Tailscale repo to OS repos
def ts-repo [os: string]: nothing -> nothing {
    try {
        match $os {
            "Arch" => {
                # Do nothing
            }
            "OpenSUSE" => {
                if ($os_id == opensuse-tumbleweed) {
                    sudo -n zypper addrepo obs://network:vpn/openSUSE_Factory network:vpn-factory
                } else {
                    let ver = (os-info | get VERSION_ID | str trim '"')
                    let url_ver = ($ver | replace ' ' _)
                    let repo_url = ($"obs://network:vpn/($url_ver)")
                    sudo -n zypper addrepo $repo_url network:vpn
                }
            }
            "Ubuntu" => {
                let codename = (lsb_release -cs)
                let key_url = $"https://pkgs.tailscale.com/stable/ubuntu/($codename).noarmor.gpg"
                let url = $"https://pkgs.tailscale.com/stable/ubuntu/($codename).tailscale-keyring.list"
                http get --raw $key_url | nsudo --sudo-flags [-n] 'save --raw /usr/share/keyrings/tailscale-archive-keyring.gpg'
                http get --raw $url | nsudo --sudo-flags [-n] 'save --raw /etc/apt/sources.list.d/tailscale.list'
            }
            "Debian" => {
                let codename = (lsb_release -cs)
                let key_url = $"https://pkgs.tailscale.com/stable/debian/($codename).noarmor.gpg"
                let url = $"https://pkgs.tailscale.com/stable/debian/($codename).tailscale-keyring.list"
                http get --raw $key_url | nsudo --sudo-flags [-n] 'save --raw /usr/share/keyrings/tailscale-archive-keyring.gpg'
                http get --raw $url | nsudo --sudo-flags [-n] 'save --raw /etc/apt/sources.list.d/tailscale.list'
            }
            "RHEL" => {
                let version_id = (os-info | get VERSION_ID | str trim '"')
                let ind = (($version_id | str index-of .) - 1)
                let major_ver = ($version_id | str substring 0..$ind)
                let url = $"https://pkgs.tailscale.com/stable/rhel/($major_ver)/tailscale.repo"
                sudo dnf config-manager --add-repo $url
            }
            "Fedora" => {
                # Do nothing
            }
            "FreeBSD" => {
                # Do nothing
            }
        }
    } catch {|e|
        msg: $"couldn't add repo on ($os)"
        label: {
            text: $"failed with error code: ($e.details.code)"
            span: (metadata $e.debug).span
        }
    }
}

# This script setups Tailscale on host
def main [
    key: string # the key to set up tailscale ($env.TS_AUTHKEY as you can say)
]: nothing -> nothing {
    sudocheck
    ts-repo $os_name
    ensure-installed [$pm] tailscale
    start-services tailscaled
    try {
        sudo -n tailscale up --auth-key $key
    } catch {|e|
        error make {
            msg: $"can't set up tailscale with ($key)"
            label: {
                text: $"failed with error_code: ($e.details.code)"
                span: (metadata $e.debug).span
            }
        }
    }
}
