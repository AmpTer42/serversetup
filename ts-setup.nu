#!/usr/bin/env nu
# ts-setup.nu - install Tailscale, enable tailscaled
# and authenticate the node with an auth key.

use modules/pkg.nu [detect-pm ensure-installed]
use modules/system.nu [sudocheck nsudo start-services]
use modules/users.nu [used-os os-info]

let used_os = used-os
let os_name = ($used_os | get name)
let os_id = ($used_os | get ID)
let pmc = detect-pm

# add Tailscale repo to OS repos
def ts-repo [
    os: string
]: nothing -> nothing {
    try {
        match $os {
            # tailscale is in the main repos, nothing to add
            "Arch" => {
                # Do nothing
            }
            # openSUSE: use the OBS network:vpn repo matching the release
            "OpenSUSE" => {
                if ($os_id == opensuse-tumbleweed) {
                    sudo -n zypper addrepo obs://network:vpn/openSUSE_Factory network:vpn-factory
                } else {
                    # replace spaces in the version with underscores for the OBS URL
                    let ver = (os-info | get VERSION_ID | str replace --all _ ' ')
                    let repo_url = ($"obs://network:vpn/($ver | str replace --all ' ' _)")
                    sudo -n zypper addrepo $repo_url network:vpn
                }
            }
            # Ubuntu/Debian: download the Tailscale keyring and source list
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
            # RHEL: the repo URL needs the major version only (e.g. 9 from 9.4)
            "RHEL" => {
                let version_id = (os-info | get VERSION_ID)
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
        error make {
            msg: $"couldn't add repo on ($os)"
            label: {
                text: $"failed with error code: ($e.details.code)"
                span: (metadata $e.debug).span
            }
        }
    }
}

# This script setups Tailscale on host
def main [
    key: string # the key to set up tailscale ($env.TS_AUTHKEY as you can say)
    --login-server: string = "https://controlplane.tailscale.com" # login server to use
]: nothing -> nothing {
    sudocheck
    ts-repo $os_name
    ensure-installed $pmc tailscale
    start-services tailscaled
    # bring the node up with the given auth key
    try {
        sudo -n tailscale up --auth-key $key --login-server $login_server
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
