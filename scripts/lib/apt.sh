#!/usr/bin/env bash

apt_preseed_postfix() {
    local mailname
    local mailer_type

    command -v debconf-set-selections >/dev/null 2>&1 || return 0

    mailer_type="${POSTFIX_MAIN_MAILER_TYPE:-Local only}"
    mailname="${POSTFIX_MAILNAME:-}"
    if [ -z "$mailname" ]; then
        mailname="$(hostname -f 2>/dev/null || hostname 2>/dev/null || true)"
    fi
    mailname="${mailname:-localhost}"

    sudo debconf-set-selections <<EOF
postfix postfix/mailname string $mailname
postfix postfix/main_mailer_type select $mailer_type
EOF
}

apt_run() {
    sudo env \
        DEBIAN_FRONTEND=noninteractive \
        DEBCONF_NONINTERACTIVE_SEEN=true \
        apt-get "$@"
}

apt_update() {
    apt_run update
}

apt_install() {
    apt_preseed_postfix
    apt_run install -y \
        -o Dpkg::Options::=--force-confdef \
        -o Dpkg::Options::=--force-confold \
        "$@"
}

apt_install_no_recommends() {
    apt_install --no-install-recommends "$@"
}
