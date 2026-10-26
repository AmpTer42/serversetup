# pkg.nu — generic package-manager helpers.
# Поддерживаются: apt (apt-get), dnf, pacman, zypper.

# Таблица пакетов по менеджерам (внутренняя, не экспортируется).
def pm-table []: nothing -> table<name: string, cmd: string, used: bool, ctk-pkgs: list<string>> {
    [
        {
            name: apt,
            cmd:  apt-get,
            used: (which apt-get | is-not-empty),
            ctk-pkgs: [
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
            ctk-pkgs: [
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
            used: (which pacman | is-not-empty),
            ctk-pkgs: [
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
            ctk-pkgs: [
                nvidia-container-toolkit
                nvidia-container-toolkit-base
                libnvidia-container-tools
                libnvidia-container1
                nvidia-utils
                ]
        }
        {
            name: snapd,
            cmd: snap,
            used: (which snap | is-not-empty),
            ctk-pkgs: []
        }
    ]
}

# Определить доступные  менеджеры пакетов.
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

# Список пакетов nvidia-ctk для каждого из доступных менеджеров.
export def ctk-pkgs [...pmc: string]: nothing -> record {
    mut x = []
    for i in $pmc {
        $x ++= (pm-table | where name == $i | select name ctk-pkgs)
    }
    return ($x | transpose --header-row --as-record)
}

# Проверить, установлен ли пакет.
export def pkg-installed [pmc: string, pkg: string]: nothing -> bool {
    match $pmc {
        "apt" => {
            let r = (do { dpkg-query -W -f='${Status}' $pkg } | complete)
            ($r.exit_code == 0) and ($r.stdout =~ "install ok installed")
        }
        "pacman" => { (do { pacman -Q $pkg } | complete).exit_code == 0 }
        "dnf"    => { (do { dnf -q list installed $pkg } | complete).exit_code == 0 }
        "zypper" => { (do { rpm -q --quiet $pkg } | complete).exit_code == 0 }
    }
}

# Установить один пакет.
export def pkg-install [pmc: string, pkg: string]: nothing -> nothing {
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

# Установить пакет, если его ещё нет.
export def ensure-installed [pmc: string, pkg: string]: nothing -> nothing {
    if (pkg-installed $pmc $pkg) { return }
    pkg-install $pmc $pkg
}
