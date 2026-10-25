#!/usr/bin/env nu

let pm = [
    {
    name: apt,
    cmd:  apt-get,
    used: (which apt-get | is-not-empty),
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
    cmd:  dnf,
    used: (which dnf | is-not-empty),
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
    cmd:  pacman,
    used: (which zypper | is-not-empty),
    pkgs: [
    nvidia-container-toolkit
    libnvidia-container-tools
    libnvidia-container
    nvidia-utils
    ]
    }
    {
    name: zypper,
    cmd:  zypper,
    used: (which zypper | is-not-empty),
    pkgs: [
    nvidia-container-toolkit
    nvidia-container-toolkit-base
    libnvidia-container-tools
    libnvidia-container1
    nvidia-utils
    ]
    }
]

let pmc = ($pm | where used | get --optional name | first)

if ($pmc == []) {
    error make {
        msg: "no supported package manager"
        label: {
            text: "needs apt-get, dnf, zypper or pacman"
            span: (metadata $pmc).span
        }
    }
}

def pkg-installed [pkg: string]: nothing -> bool {
    match ($pmc) {
        "apt" => {
            let r = (do { dpkg-query -W -f='${Status}' $pkg } | complete)
            $r.exit_code == 0 and ($r.stdout =~ "install ok installed")
        }
        "pacman" => {
            let r = (do { pacman -Q $pkg } | complete)
            $r.exit_code == 0
        }
        "dnf" => {
            let r = (do { dnf -q list installed $pkg } | complete)
            $r.exit_code == 0
        }
        "zypper" => {
            let r = (do { rpm -q --quiet $pkg } | complete)
            $r.exit_code == 0
        }
    }
}

def pkg-install [pkg: string]: nothing -> nothing {
    try {
        match $pmc {
            "apt" => {
                sudo -n env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a APT_LISTCHANGES_FRONTEND=none apt-get install -y -qq --no-install-recommends -o Dpkg::Use-Pty=0 -o DPkg::Lock::Timeout=60 -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold $pkg
            }
            "dnf" => {
                sudo -n dnf install -y --setopt=install_weak_deps=False --setopt=exit_on_lock=True $pkg
            }
            "pacman" => {
                sudo -n pacman -Sq --noconfirm --needed --noprogressbar $pkg
            }
            "zypper" => {
                sudo -n zypper install --non-interactive --gpg-auto-import-keys -y --auto-agree-with-licenses --download-in-advance $pkg
            }
        }
    } catch {|e|
        error make {
            msg: $"install ($pkg) failed: error code ($e.details.code)"
            label: {
                text: "can't install this package"
                span: (metadata $e.debug).span
            }
        }
    }
}

def ctk-install []: nothing -> nothing {
    match ($pmc) {
        "pacman" => {
        # nvidia-ctk и так есть в extra
        }
        "apt" => {
            ensure-installed gpg
            try {
                # nu-lint-ignore dangerous_file_operations
                http get --raw https://nvidia.github.io/libnvidia-container/gpgkey | sudo -n gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
                http get --raw https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | str replace --all 'deb https://' 'deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://' | sudo -n tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
                sudo -n env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a APT_LISTCHANGES_FRONTEND=none apt-get update -y -qq -o Dpkg::Use-Pty=0 -o DPkg::Lock::Timeout=60 -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold
            } catch {|e|
                error make {
                    msg: $"gpg keys installation for nvidia-ctk failed with exit code ($e.details.code)"
                    label: {
                        text: $"gpg keys installation failed on OS with ($pmc)"
                        span: (metadata $e.debug).span
                    }
                }
            }
        }
        "dnf" => {
            try {
                http get --raw https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo | sudo -n tee /etc/yum.repos.d/nvidia-container-toolkit.repo
            } catch {|e|
                error make {
                    msg: $"nvidia-ctk repo installation failed with exit code ($e.details.code)"
                    label: {
                        text: $"repo installation failed on OS with ($pmc)"
                        span: (metadata $e.debug).span
                    }
                }
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
            } catch {|e|
                error make {
                    msg: $"nvidia-ctk repo installation failed with exit code ($e.details.code)"
                    labels: [
                    {text: $"repo installation failed with ($pmc)", span: (metadata $pmc).span}
                    {text: $"failed to install ($zypperrepo)", span: (metadata $e.debug).span}
                    ]
                }
            }
        }
    }
    let utils = ($pm | where name == $pmc | get --optional pkgs | first)
    for x in $utils {
        ensure-installed $x
    }
    try {
        nvidia-smi
    } catch {|e|
        error make {
            msg: $"Can't find nvidia-smi binary: error code ($e.details.code)"
            label: {
                text: $"can't configure nvidia-ctk on OS with ($pmc)"
                span: (metadata $e.debug).span
            }
            help: $"Try to install NVIDIA drivers with ($pmc)"
        }
    }
    try {
        sudo -n install -d /etc/cdi
        sudo -n nvidia-ctk cdi generate --quiet --output="/etc/cdi/nvidia.yaml"
        sudo -n nvidia-ctk runtime configure --runtime=docker --config=/etc/docker/daemon.json
    } catch {|e|
        error make {
            msg: $"nvidia-ctk configuration failed: ($e.msg)"
            label: {
                text: $"can't configure nvidia-ctk on OS with ($pmc)"
                span: (metadata $pmc).span
            }
        }
    }
}

def ensure-installed [pkg: string]: nothing -> nothing {
    if (pkg-installed $pkg) { return }
    pkg-install $pkg
    return
}

try {
    sudo -v
} catch {|e|
    error make {
        msg: $"can't use sudo: error code ($e.details.code)"
        label: {
            text: "can't execute sudo -v"
            span: (metadata $e.debug).span
        }
        help: "try to install sudo with your package manager"
    }
}

let packages = [ca-certificates]
for i in $packages {
    ensure-installed $i
}
ctk-install
