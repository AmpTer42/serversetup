# system.nu - generic work with system

# Check if sudo is present in this environment
export def sudocheck []: nothing -> nothing {
    try {
        sudo -v
    } catch {|e|
        error make {
            msg: $"can't use sudo: ($e.details.code)"
            label: {
                text: "sudo failed"
                span: (metadata $e.debug).span
            }
        }
    }
}

# Parse /etc/os-release
export def os-info []: nothing -> record {
    try {
      open /etc/os-release | lines | parse '{key}={value}' | reduce --fold {} {|it, acc| $acc | insert $it.key $it.value } | into record
    } catch {|e|
        error make {
            msg: $"can't open /etc/os-release: error code ($e.details.code)"
            label: {
                text: $"can't open /etc/os-release"
                span: (metadata $e.debug).span
            }
            help: "Check if /etc/os-release is present on your system"
        }
    }
}

# Run a command or closure in an elevated shell
export def nsudo [
    command?: string,                      # Command to execute
    --closure (-c) : closure,                # Closure to execute if not command is given
    --sudo-flags (-s): list<string> = [],   # Flags to pass to sudo
]: any -> string {
    let nu_path = (which nu).0?.path
    try {
        let script = (
            if $command != null { $'from nuon | do { ($command) }' }
            else if $closure != null { $'from nuon | do ($closure | to nuon --serialize | from nuon)' }
            else { error make "a command or closure must be provided" }
        )
        $in | to nuon | sudo ...$sudo_flags $nu_path --stdin --commands $script
    } catch {|e|
        error make {
            msg: "can't execute nsudo with given command"
            label: {
                text: $"see script"
                span: (metadata $command).span
            }
        }
    }
}

# check services status
export def check-services [...services: string]: nothing -> table<name: string, status: string> {
    if ($services | is-empty) {
    return []
    }
    try {
        let states = (systemctl is-active ...$services | lines)
        mut status_table = []
        for i in (0..(($services | length) - 1)) {
            $status_table ++= ([
            {name: ($services | get --optional $i), status: ($states | get --optional $i)}
            ])
            if ($i == ($services | length) - 1) {
                return $status_table
            }
        }
        return $status_table
    } catch {|e|
        error make {
            msg: "can't parse states of services from input"
            label: {
                text: $"failed with error code: ($e.details.code)"
                span: (metadata $e.debug).span
            }
        }
    }
}

# start services from input
export def start-services [...services: string]: nothing -> nothing {
    if ($services | is-empty) {
        return
    }
    let status = (check-services ...$services)
    let start = ($status | where status != running | get name)
    try {
        sudo -n systemctl enable --now ...$start
    } catch {|e|
        error make {
            msg: "can't start services from input"
            label: {
                text: $"failed with error code: ($e.details.code)"
                span: (metadata $e.debug).span
            }
        }
    }
}

# stop services from input
export def stop-services [...services: string]: nothing -> nothing {
    if ($services | is-empty) {
        return
    }
    let status = (check-services ...$services)
    let start = ($status | where status == active | get name)
    try {
        sudo -n systemctl disable --now ...$start
    } catch {|e|
        error make {
            msg: "can't start services from input"
            label: {
                text: $"failed with error code: ($e.exit_code)"
                span: (metadata $e.debug).span
            }
        }
    }
}
