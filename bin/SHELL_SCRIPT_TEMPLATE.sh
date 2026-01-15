#!/bin/bash
# SHELL_SCRIPT_TEMPLATE.sh
# AI instructions:  
#  - AI agents: be sure to check ../AGENTS.md and make changes that conform to ../SHELL_SCRIPT_TEMPLATE.md as a standard.
#  - shell scripts should be patterned after this file.
#  - read the comments for additional standard coding instructions and principles
#  - run shellcheck after all changes, it must pass.  It is OK to suppress violations that are difficult to resolve otherwise.

set -euo pipefail  # Be strict about error handling


# PS4 provides good diagnostics when -x is turned on
#shellcheck disable=2154
PS4='$( _0=$?; exec 2>/dev/null; realpath -- "${BASH_SOURCE[0]:-?}:${LINENO} ^$_0 ${FUNCNAME[0]:-?}()=>" ) '
[[ -n "${DEBUGSH:-}" ]] && set -x # Allows the user to enable debugging output via environment

scriptName="${scriptName:-"$(command readlink -f -- "$0")"}"
# (if needed) scriptDir="$(command dirname -- "${scriptName}")"


# In most cases, global vars should be initialized to some reasonable default based on how the code uses it, but
# allow the user to provide the initial value in the environment
export MY_GLOBAL_VAR=${MY_GLOBAL_VAR:-default_value}

# ============================================================================
# OUTPUT DISCIPLINE: Critical for functions whose output is captured
# ============================================================================
# Scripts often need to separate three types of output:
#   1. DATA OUTPUT (stdout)    - For piping/capturing: ai_result=$(my_function)
#   2. USER MESSAGES (stderr)  - Progress, warnings, errors for human consumption
#   3. LOG FILES              - Persistent record, written directly to file
#
# RULE: Functions whose output will be captured MUST NOT write user messages to stdout.
#       All user-facing messages must go to stderr or directly to log files.
#
# Example of WRONG approach:
#   log() { echo "$*" | tee -a "$LOGFILE"; }  # BAD: tee writes to stdout!
#
# Example of CORRECT approach:
#   log() { echo "$*" >> "$LOGFILE"; }         # GOOD: only writes to file
#   msg() { echo "$*" >&2; }                   # GOOD: user message to stderr
#
# When building a function that returns data:
#   - Use 'echo' or 'printf' for data output (stdout)
#   - Use '>&2' redirect for all user messages
#   - Write logs directly to file with '>>' or use process substitution
#
# This prevents contamination when doing: result=$(function_call)
# ============================================================================

die() {
    # Logic which aborts should do so by calling 'die "message text"'
    builtin echo "ERROR($(basename "${scriptName}")): $*" >&2
    builtin exit 1
}

{  # "outer scope braces" -- this block may be very long, but it contains all functions except die() and main() 

    # Example: Logging function that ONLY writes to log file (not stdout)
    log_to_file() {
        local level="$1"
        shift
        local timestamp
        timestamp=$(date +"%Y-%m-%d %H:%M:%S")
        echo "[$timestamp] [$level] $*" >> "${LOGFILE:-/dev/null}"
    }

    # Example: User message function that writes to stderr (not stdout)
    msg() {
        echo "$*" >&2
    }

    # Example: Data-producing function that returns clean output
    get_config_value() {
        local key="$1"
        # User messages go to stderr
        msg "Looking up key: $key"
        log_to_file "DEBUG" "Config lookup: $key"
        # ONLY the data goes to stdout
        echo "value_for_$key"
    }

    sample_makefile() {
        # If you need to print lots of text or create file from templates, don't 
        # use long sequences of 'echo' commands (the code is less maintainable and harder to read)
        # A heredoc with some creative 'cut' works well:
        #shellcheck disable=2116
        cut -c 12- > /tmp/myfile <<- EOF
            This text will be trimmed on the left by 12 chars
            because of the cut -c 12- command.  But notice how
            well formatted it can be
                and we can indent, and have the indentation show up
                in the output file.
            We can also expand vars and do $(echo "shell substitution")
EOF
    }

    helper_1() {
        local arg1="$1"
        local arg2="$2"
    }

    helper_2() {
        echo
        helper_1 "$@" &>/dev/null # when redirecting or piping, prefer the bashisms "&>" and "|&" if we're doing both stdout+stderr
        # or...
        helper_1 "$@" |& awk '...'
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

