# shellcheck shell=sh
# Offer to run the Pangolin setup wizard on interactive login until Pangolin
# has been configured (either from user-data or by a previous run).

pangolin_setup_prompt() {
    [ -t 0 ] && [ -t 1 ] || return 0
    [ -z "${PANGOLIN_SETUP_SKIP:-}" ] || return 0
    [ -x /usr/local/sbin/pangolin-setup ] || return 0

    pangolin_state=$(cat /var/lib/pangolin-ami/state 2>/dev/null || echo pending)
    case "$pangolin_state" in
        needs-input | failed) ;;
        *) return 0 ;;
    esac

    printf '\nPangolin is not configured yet.\n'
    printf 'Run the setup wizard now? [Y/n] '
    read -r pangolin_reply
    case "$pangolin_reply" in
        [Nn]*) printf "Run 'sudo pangolin-setup' when you are ready.\n\n" ;;
        *) sudo /usr/local/sbin/pangolin-setup ;;
    esac
}

pangolin_setup_prompt
unset -f pangolin_setup_prompt
unset pangolin_state pangolin_reply
