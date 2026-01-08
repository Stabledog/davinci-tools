#!/bin/bash
# SHELL_SCRIPT_TEMPLATE.sh
# AI instructions:  
#  - shell scripts should be patterned after this file.
#  - read the comments for additional standard coding instructions and principles
#  - run shellcheck after all changes, it must pass.  It is OK to suppress violations that are difficult to resolve otherwise.

set -ue  # Always default to strict -ue

# PS4 provides good diagnostics when -x is turned on
#shellcheck disable=2154
PS4='$( _0=$?; exec 2>/dev/null; realpath -- "${BASH_SOURCE[0]:-?}:${LINENO} ^$_0 ${FUNCNAME[0]:-?}()=>" ) '
[[ -n "$DEBUGSH" ]] && set -x # Allows the user to enable debugging output via environment

scriptName="${scriptName:-"$(command readlink -f -- "$0")"}"
# (if needed) scriptDir="$(command dirname -- "${scriptName}")"


# In most cases, global vars should be initialized to some reasonable default based on how the code uses it, but
# allow the user to provide the initial value in the environment
export MY_GLOBAL_VAR=${MY_GLOBAL_VAR:-default_value}


die() {
    # Logic which aborts should do so by calling 'die "message text"'
    builtin echo "ERROR($(basename "${scriptName}")): $*" >&2
    builtin exit 1
}

{  # "outer scope braces" -- this block may be very long, but it contains all functions except die() and main() 

    helper_1() {
        local arg1="$1"
        local arg2="$2"
    }

    helper_2() {
        echo
    }
}

main() {
    set -ue
    set -x
    echo This script needs some content.
}

#  The "sourceMe" conditional allows the user to source the script into their current shell
#  to work with the individual helper functions, overwrite global vars, etc.
if [[ -z "${sourceMe}" ]]; then
    main "$@"
    builtin exit
fi
command true

