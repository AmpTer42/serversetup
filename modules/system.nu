# system.nu - generic work with system

# Extract the exit code (or unknown) from a caught error
def err-code []: record -> string { get --optional exit_code | default unknown }

# Check if the current user is root
export def is-root []: nothing -> bool {
    (id -u | str trim | into int) == 0
}

# Check if sudo is present in this environment
export def sudocheck []: nothing -> nothing {
    try {
        sudo -v
    } catch {|e|
        error make {
            msg: $"can't use sudo: ($e.msg)"
            label: {
                text: "sudo failed"
                span: (metadata $e.debug).span
            }
        }
    }
}

# Check if doas is present without pasword in this environment
export def doascheck []: nothing -> nothing {
    try {
        doas -nu root true
    } catch {|e|
        error make {
            msg: $"can't use doas with no password: ($e.msg)"
            label: {
                text: "doas failed"
                span: (metadata $e.debug).span
            }
        }
    }
}

# Parse /etc/os-release (values are unquoted)
export def os-info []: nothing -> record {
    try {
        open /etc/os-release | lines | parse '{key}={value}' | reduce --fold {} {|it, acc| $acc | insert $it.key ($it.value | str trim --char (char dq)) } | into record
    } catch {|e|
        error make {
            msg: $"can't open /etc/os-release: ($e.msg)"
            label: {
                text: $"can't open /etc/os-release"
                span: (metadata $e.debug).span
            }
            help: "Check if /etc/os-release is present on your system"
        }
    }
}

# Run a command or closure in an elevated shell via sudo.
# Pipeline input is serialized and piped to the root Nu process via stdin,
# so the elevated command can consume it (e.g. 'save /path' from a pipe).
export def nsudo [
    command?: string,                      # Command to execute
    --closure (-c) : closure,                # Closure to execute if not command is given
    --sudo-flags (-s): list<string> = [],   # Flags to pass to sudo
]: any -> string {
    let nu_path = (which nu).0?.path
    try {
        let script = (
            if $command != null { $command }
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

# Run a command or closure in an elevated shell via doas.
# Pipeline input is serialized and piped to the root Nu process via stdin,
# so the elevated command can consume it (e.g. 'save /path' from a pipe).
export def ndoas [
    command?: string,                      # Command to execute
    --closure (-c): closure,               # Closure to execute if no command is given
    --doas-flags (-s): list<string> = [],  # Flags to pass to doas
]: any -> string {
    let nu_path = (which nu).0?.path
    try {
        let script = (
            if $command != null { $command }
            else if $closure != null { $'from nuon | do ($closure | to nuon --serialize | from nuon)' }
            else { error make "a command or closure must be provided" }
        )
        $in | to nuon | doas ...$doas_flags $nu_path --stdin --commands $script
    } catch {|e|
        error make {
            msg: "can't execute ndoas with given command"
            label: {
                text: "see script"
                span: (metadata $command).span
            }
        }
    }
}

# check services status via systemctl is-active
export def check-services [...services: string]: nothing -> table<name: string, status: string> {
    if ($services | is-empty) {
        return []
    }
    try {
        let states = (systemctl is-active ...$services | lines)
        $services | zip $states | each {|x| {name: ($x | get 0), status: ($x | get 1)} }
    } catch {|e|
        error make {
            msg: "can't parse states of services from input"
            label: {
                text: $"failed with error code: ($e | err-code)"
                span: (metadata $e.debug).span
            }
        }
    }
}

# start (enable --now) services that aren't active yet
export def start-services [...services: string]: nothing -> nothing {
    if ($services | is-empty) {
        return
    }
    let status = (check-services ...$services)
    let start = ($status | where status != active | get name)
    if ($start | is-empty) {
        return
    }
    try {
        sudo -n systemctl enable --now ...$start
    } catch {|e|
        error make {
            msg: "can't start services from input"
            label: {
                text: $"failed with error code: ($e | err-code)"
                span: (metadata $e.debug).span
            }
        }
    }
}

# stop (disable --now) services that are currently active
export def stop-services [...services: string]: nothing -> nothing {
    if ($services | is-empty) {
        return
    }
    let status = (check-services ...$services)
    let stop = ($status | where status == active | get name)
    if ($stop | is-empty) {
        return
    }
    try {
        sudo -n systemctl disable --now ...$stop
    } catch {|e|
        error make {
            msg: "can't stop services from input"
            label: {
                text: $"failed with error code: ($e | err-code)"
                span: (metadata $e.debug).span
            }
        }
    }
}

# restart active services
export def restart-services [...services: string]: nothing -> nothing {
    if ($services | is-empty) {
        return
    }
    try {
        sudo -n systemctl restart ...$services
    } catch {|e|
        error make {
            msg: "can't restart services from input"
            label: {
                text: $"failed with error code: ($e | err-code)"
                span: (metadata $e.debug).span
            }
        }
    }
}
