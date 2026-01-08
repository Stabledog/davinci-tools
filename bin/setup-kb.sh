#!/bin/bash
# setup-kb.sh - Environment preparation for davinci-tools knowledge base

set -ue  # Always default to strict -ue

# PS4 provides good diagnostics when -x is turned on
#shellcheck disable=2154
PS4='$( _0=$?; exec 2>/dev/null; realpath -- "${BASH_SOURCE[0]:-?}:${LINENO} ^$_0 ${FUNCNAME[0]:-?}()=>" ) '
[[ -n "${DEBUGSH:-}" ]] && set -x # Allows the user to enable debugging output via environment

scriptName="${scriptName:-"$(command readlink -f -- "$0")"}"
scriptDir="$(command dirname -- "${scriptName}")"

# Global configuration
REPO_ROOT="${REPO_ROOT:-"$(cd "${scriptDir}/.." && pwd)"}"
DOCS_DIR="${DOCS_DIR:-"${REPO_ROOT}/docs"}"
RESOLVE_MANUAL="${RESOLVE_MANUAL:-"/c/Program Files/Blackmagic Design/DaVinci Resolve/Documents/DaVinci Resolve.pdf"}"


die() {
    # Logic which aborts should do so by calling 'die "message text"'
    builtin echo "ERROR($(basename "${scriptName}")): $*" >&2
    builtin exit 1
}

{  # "outer scope braces" -- this block contains all functions except die() and main()

    validate_prerequisites() {
        # Check that we're in a valid repository structure
        [[ -d "$REPO_ROOT" ]] || die "Repository root not found: $REPO_ROOT"
        
        # Check for required tools
        check_scoop || die "scoop is required but not installed"
        check_shellcheck || die "shellcheck is required but not installed"
    }

    check_scoop() {
        if ! command -v scoop &>/dev/null; then
            echo "ERROR: scoop package manager is not installed." >&2
            echo "" >&2
            echo "To install scoop, run the following in PowerShell:" >&2
            echo "  Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser" >&2
            echo "  Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression" >&2
            echo "" >&2
            echo "For more information, visit: https://scoop.sh/" >&2
            return 1
        fi
        echo "✓ scoop is installed"
        return 0
    }

    check_shellcheck() {
        if ! command -v shellcheck &>/dev/null; then
            echo "ERROR: shellcheck is not installed." >&2
            echo "" >&2
            echo "To install shellcheck with scoop, run:" >&2
            echo "  scoop install shellcheck" >&2
            echo "" >&2
            return 1
        fi
        echo "✓ shellcheck is installed"
        return 0
    }

    create_docs_directory() {
        if [[ ! -d "$DOCS_DIR" ]]; then
            mkdir -p "$DOCS_DIR" || die "Failed to create docs directory: $DOCS_DIR"
            echo "Created docs directory: $DOCS_DIR"
        fi
    }

    setup_manual_symlink() {
        local manual_link="${DOCS_DIR}/DaVinci_Resolve_Manual.pdf"

        if [[ -L "$manual_link" ]]; then
            echo "Manual symlink already exists: $manual_link"
            return 0
        fi

        if [[ -f "$RESOLVE_MANUAL" ]]; then
            ln -s "$RESOLVE_MANUAL" "$manual_link" || die "Failed to create symlink: $manual_link"
            echo "Created symlink: $manual_link -> $RESOLVE_MANUAL"
        else
            echo "Warning: DaVinci Resolve manual not found at: $RESOLVE_MANUAL" >&2
            echo "The manual symlink will not be created." >&2
            echo "This is not fatal - you can create it manually later if needed." >&2
        fi
    }
}

main() {
    set -ue
    
    echo "Setting up davinci-tools knowledge base..."

    # Validate prerequisites before making any changes
    validate_prerequisites

    # Execute setup steps
    create_docs_directory
    setup_manual_symlink

    echo "Knowledge base setup complete."
}

# The "sourceMe" conditional allows the user to source the script into their current shell
# to work with the individual helper functions, overwrite global vars, etc.
if [[ -z "${sourceMe:-}" ]]; then
    main "$@"
    builtin exit
fi
command true
