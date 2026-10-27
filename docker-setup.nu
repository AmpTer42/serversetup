#!/usr/bin/env nu
use modules/pkg.nu [ensure-installed detect-pm]
use modules/system.nu [nsudo start-services os-info sudocheck]

# import /etc/os-release contents
let os_info = os-info

# os table with used os calculation
let os = [
    {
        name: Debian
        used: (($os_info | get --optional ID) == debian)
    }
    {
        name: Arch
        used: (($os_info | get --optional ID_LIKE) == arch or ($os_info | get --optional ID) == arch)
    }
    {
        name: RHEL
        used: (($os_info | get --optional ID) == rhel)
    }
    {
        name: Fedora
        used: (($os_info | get --optional ID) == fedora)
    }
    {
        name: OpenSUSE
        used: (($os_info | get --optional ID_LIKE) == suse or ($os_info | get ID_LIKE) == "opensuse suse")
    }
    {
        name: Ubuntu
        used: (($os_info | get --optional ID) == ubuntu)
    }
]

# docker packages for non-Arch distros
let docker_std = [
    docker-ce
    docker-ce-cli
    containerd.io
    docker-buildx-plugin
    docker-compose-plugin
]

# docker packages for Arch-based distros
let docker_arch = [
    docker
    docker-compose
    docker-buildx
]

# calculate candidate of os on computer
let candidates = ($os | where used)

# check if it's empty
if ($candidates | is-empty) {
    error make {
        msg: $"using unsupported OS: ($candidates | get ID)"
        label: {
            text: $"unsupported OS: ($candidates| get ID)"
            span: (metadata $candidates).span
        }
    }
}

# check if there's more than one candidate
if (($candidates | length) > 1) {
    error make {
        msg: $"More than one OS candidate"
        label: {
            text: ($candidates)
            span: (metadata $candidates).span
        }
    }
}

# calculate installed os on computer
let used_os = $candidates.0?

# create a list of available package managers
let pmc = detect-pm

# add docker repo for your OS
def docker-repo [os: string]: nothing -> nothing {
    try {
        match $os {
            "OpenSUSE" => {
                let url = https://download.docker.com/linux/sles/docker-ce.repo
                let currentrepos = (zypper --xmlout lr -u =~ $url)
                if (not $currentrepos) {
                    sudo -n zypper --quiet addrepo -f $url
                    sudo -n zypper --gpg-auto-import-keys refresh
                }
                return
            }
            "Debian" => {
                let url = https://download.docker.com/linux/debian
                let keyrings = "/etc/apt/keyrings"
                let source = [
                    "Types: deb"
                    $"URIs: ($url)"
                    $"Suites: (os-info | get --optional VERSION_CODENAME)"
                    "Components: stable"
                    $"Architectures: (dpkg --print-architecture)"
                    $"Signed-By: ($keyrings)/docker.asc" 
                ] | str join "\n" # parse list as string with \n between elements of original list
                ensure-installed $pmc gpg ca-certificates
                sudo -n install -m 0755 -d $keyrings
                http get --raw $"($url)/gpg" | nsudo --sudo-flags [-n] $'save ($keyrings)/docker.asc' # nsudo is used to provide input from pipeline
                sudo -n chmod a+r $"($keyrings)/docker.asc"
                $source | nsudo --sudo-flags [-n] 'save /etc/apt/sources.list.d/docker.sources'
                return
            }
            "Ubuntu" => {
                let url = https://download.docker.com/linux/ubuntu
                let keyrings = "/etc/apt/keyrings"
                let source = [
                    "Types: deb"
                    $"URIs: ($url)"
                    $"Suites: (os-info | get --optional UBUNTU_CODENAME | default (os-info | get --optional VERSION_CODENAME))"
                    "Components: stable"
                    $"Architectures: (dpkg --print-architecture)"
                    $"Signed-By: ($keyrings)/docker.asc" 
                ] | str join "\n"
                ensure-installed $pmc gpg ca-certificates
                sudo -n install -m 0755 -d $keyrings
                http get --raw https://download.docker.com/linux/ubuntu/gpg | nsudo --sudo-flags [-n] $'save ($keyrings)/docker.asc'
                sudo -n chmod a+r $"($keyrings)/docker.asc"
                $source | nsudo --sudo-flags [-n] 'save /etc/apt/sources.list.d/docker.sources'
                return
            }
            "Fedora" => {
                sudo -n dnf config-manager addrepo --from-repofile https://download.docker.com/linux/fedora/docker-ce.repo
                return
            }
            "RHEL" => {
                ensure-installed $pmc dnf-plugins-core
                sudo -n dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
                return
            }
            "Arch" => {
                # Docker already exists in extra repo
                return
            }
        }
    } catch {|e|
        error make {
            msg: $"can't set up docker repo on your OS: ($os)"
            label: {
                text: $"failed to set up docker repo: ($e.details.code)"
                span: (metadata $e.debug).span
            }
        }
    }
}

# the full instruction to install docker and plugins
def main []: nothing -> nothing {
    sudocheck
    docker-repo $used_os.name
    if ($used_os.name != Arch) {
        ensure-installed $pmc ...$docker_std
   } else {
        ensure-installed $pmc ...$docker_arch
   }
    start-services docker
}
