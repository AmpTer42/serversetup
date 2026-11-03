#!/usr/bin/sh

# You must run this script as root
# Script is intended for use in air-gapped environments where you wouldn't install Nushell for security or other reasons, like Alpine Linux
# In any other situations consider using .nu script (if it isn't present, try to use `git pull`, or it may be added later)
# This scirpt doesn't check any exit_codes, errors, user's permissions or anything else
# Script doesn't support using $JAIL environment variable or stdin for setting up $JAIL

JAIL=/var/lib/unbound/chroot

install -d -m 0755 -o root -g root "$JAIL"
install -d -m 0755 -o root -g root "$JAIL/etc/unbound"
install -d -m 0755 -o root -g root "$JAIL/var/lib/unbound"
install -d -m 0755 -o root -g root "$JAIL/var/log"
install -d -m 0755 -o unbound -g unbound "$JAIL/run"

install -m 0644 -o root -g root \
  /usr/share/dns/root.hints \
  "$JAIL/etc/unbound/root.hints"

unbound-anchor -a "$JAIL/var/lib/unbound/root.key"
chown unbound:unbound "$JAIL/var/lib/unbound/root.key"
