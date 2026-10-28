#!/usr/bin/env nu
use modules/pkg.nu [ensure-installed detect-pm]
use modules/system.nu [nsudo sudocheck]

# table of package managers and their packages for nvidia-ctk
let ctkpm = [
    {
    name: apt,
    pkgs: [
    nvidia-container-toolkit
    nvidia-container-toolkit-base
    libnvidia-container-tools
    libnvidia-container1
    nvidia-utils
    ]
    }
    {
    name: dnf,
    pkgs: [
    nvidia-container-toolkit
    nvidia-container-toolkit-base
    libnvidia-container-tools
    libnvidia-container1
    libnvidia-compute
    nvidia-utils
    ]
    }
    {
    name: pacman,
    pkgs: [
    nvidia-container-toolkit
    libnvidia-container-tools
    libnvidia-container
    nvidia-utils
    ]
    }
    {
    name: zypper,
    pkgs: [
    nvidia-container-toolkit
    nvidia-container-toolkit-base
    libnvidia-container-tools
    libnvidia-container1
    nvidia-utils
    ]
    }
]

# calculate list of package managers
let pmc = detect-pm

# install nvidia-ctk repo on your OS
def ctk-repo-install [...pms: string]: nothing -> list<string> {
    mut inst = []
    for i in $pms {
        match ($i) {
            "pacman" => {
                # nvidia-ctk is already in extra repo
                $inst ++= [pacman]
            }
            "apt" => {
                ensure-installed [$i] gpg
                try {
                    http get --raw https://nvidia.github.io/libnvidia-container/gpgkey | nsudo --sudo-flags [-n] 'gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg' # used nsudo for correct pipelines
                    http get --raw https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | str replace --all 'deb https://' 'deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://' | nsudo --sudo-flags [-n] 'save /etc/apt/sources.list.d/nvidia-container-toolkit.list'
                    sudo -n env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a APT_LISTCHANGES_FRONTEND=none apt-get update -y -qq -o Dpkg::Use-Pty=0 -o DPkg::Lock::Timeout=60 -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold
                    $inst ++= [apt]
                }
            }
            "dnf" => {
                try {
                    http get --raw https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo | nsudo --sudo-flags [-n] 'save /etc/yum.repos.d/nvidia-container-toolkit.repo'
                    $inst ++= [dnf]
                }
            }
            "zypper" => {
                let zypperrepo = https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo
                let currentrepos = (zypper --xmlout lr -u =~ $zypperrepo)
                try {
                    if (not $currentrepos) {
                        sudo -n zypper --quiet ar -f $zypperrepo
                        sudo -n zypper --gpg-auto-import-keys refresh
                    }
                    $inst ++= [zypper]
                }
            }
        }
    }
    if ($inst | is-not-empty) {
        return $inst
    } else {
        error make {
            msg: "failed to setup nvidia-ctk on every pm"
            labels: [
                {text: $"inst returned empty list: ($inst)", span: (metadata $inst).span}
                {text: $"input was ($pms)", span: (metadata $pms).span}
            ]
        }
    }
}

# install packages from ctkpm table
def ctk-install [...pms: string]: nothing -> nothing {
    for i in $pms {
        let utils = ($ctkpm | where name == $i | get --optional pkgs | first)
        ensure-installed [$i] $utils
    }
}

# configure nvidia-ctk
def ctk-config []: nothing -> nothing {
    try {
        nvidia-smi
    } catch {|e|
        error make {
            msg: $"Can't find nvidia-smi binary: error code ($e.details.code)"
            label: {
                text: $"can't check videocard info"
                span: (metadata $e.debug).span
            }
            help: $"Try to install NVIDIA drivers with your PM"
        }
    }
    try {
        sudo -n install -d /etc/cdi
        sudo -n nvidia-ctk cdi generate --quiet --output="/etc/cdi/nvidia.yaml"
        sudo -n nvidia-ctk runtime configure --runtime=docker --config=/etc/docker/daemon.json
    } catch {|e|
        error make {
            msg: $"nvidia-ctk configuration failed: ($e.details.code)"
            label: {
                text: "can't configure nvidia-ctk"
                span: (metadata $e.debug).span
            }
        }
    }
}

# whole instruction
def main []: nothing -> nothing {
    sudocheck
    let packages = [ca-certificates]
    ensure-installed $pmc ...$packages
    let cpm = ctk-repo-install ...$pmc
    ctk-install ...$cpm
    ctk-config
}
