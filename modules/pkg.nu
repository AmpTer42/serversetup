# pkg.nu — generic package-manager helpers.
# Supports: apt (apt-get), dnf, pacman, zypper, snap.

# Package managers table
def pm-table []: nothing -> table<name: string, cmd: string, used: bool> {
    [
        {
            name: apt,
            cmd:  apt-get,
            used: (which apt-get | is-not-empty),
        }
        {
            name: dnf,
            cmd:  dnf,
            used: (which dnf | is-not-empty),
        }
        {
            name: pacman,
            cmd:  pacman,
            used: (which pacman | is-not-empty),
        }
        {
            name: zypper,
            cmd:  zypper,
            used: (which zypper | is-not-empty),
        }
        {
            name: snap,
            cmd: snap,
            used: (which snap | is-not-empty),
        }
    ]
}

# Select available package managers
export def detect-pm []: nothing -> list<string> {
    let found = (pm-table | where used | get name)
    if ($found | is-empty) {
        error make {
            msg: "no supported package manager"
            label: {
                text: "needs apt-get, dnf, zypper or pacman"
                span: (metadata $found).span
            }
        }
    }
    return $found
}

# Check if the package is already installed
def pkg-installed [pmc: string, pkg: string]: nothing -> bool {
    match $pmc {
        "apt" => {
            let r = (do { dpkg-query -W -f='${Status}' $pkg } | complete)
            ($r.exit_code == 0) and ($r.stdout =~ "install ok installed")
        }
        "pacman" => { (do { pacman -Q $pkg } | complete).exit_code == 0 }
        "dnf"    => { (do { dnf -q list installed $pkg } | complete).exit_code == 0 }
        "zypper" => { (do { rpm -q --quiet $pkg } | complete).exit_code == 0 }
        "snap" => { (do { snap list $pkg } | complete).exit_code == 0 }
        _ => {
            error make {
                msg: "using non-matched package manager"
                label: {
                    text: $"Using ($pmc)"
                    span: (metadata $pmc).span
                }
            }
        }
    }
}

# Install one package
def pkg-install [pmc: string, pkg: string]: nothing -> nothing {
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
            "snap" => {
                try {
                    sudo -n snap install $pkg
                } catch {
                    sudo -n snap install --classic $pkg
                }
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

# Install packages if they aren't already installed
export def ensure-installed [pmc: list<string>, ...pkg: string]: nothing -> nothing {
    for i in $pmc {
        for j in $pkg {
            if (pkg-installed $i $j) { continue } else {
                pkg-install $i $j
            }
        }
    }
}
