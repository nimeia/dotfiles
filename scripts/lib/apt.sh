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
    local apt_proxy_value="${DOTFILES_APT_PROXY:-}"
    local http_proxy_value="${DOTFILES_APT_HTTP_PROXY:-$apt_proxy_value}"
    local https_proxy_value="${DOTFILES_APT_HTTPS_PROXY:-$apt_proxy_value}"
    local apt_options=(
        -o Acquire::ForceIPv4=true
        -o Acquire::Retries=3
        -o Acquire::http::Timeout=30
        -o Acquire::https::Timeout=30
    )
    local env_args=(
        DEBIAN_FRONTEND=noninteractive
        DEBCONF_NONINTERACTIVE_SEEN=true
    )

    if [ -n "$http_proxy_value" ]; then
        apt_options+=("-o" "Acquire::http::Proxy=$http_proxy_value")
        env_args+=("http_proxy=$http_proxy_value" "HTTP_PROXY=$http_proxy_value")
    fi
    if [ -n "$https_proxy_value" ]; then
        apt_options+=("-o" "Acquire::https::Proxy=$https_proxy_value")
        env_args+=("https_proxy=$https_proxy_value" "HTTPS_PROXY=$https_proxy_value")
    fi

    sudo env "${env_args[@]}" apt-get "${apt_options[@]}" "$@"
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
