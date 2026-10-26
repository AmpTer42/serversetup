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
