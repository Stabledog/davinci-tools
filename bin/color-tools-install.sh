#!/bin/bash
# color-tools-install.sh
# Install/validate tools required for color-digest toolchain
#
# Usage:
#   color-tools-install.sh          - Interactive install mode
#   color-tools-install.sh --check  - Validation mode (exit 0 if all present, non-zero otherwise)

set -ue

#shellcheck disable=2154
PS4='$( _0=$?; exec 2>/dev/null; realpath -- "${BASH_SOURCE[0]:-?}:${LINENO} ^$_0 ${FUNCNAME[0]:-?}()=>" ) '
[[ -n "${DEBUGSH:-}" ]] && set -x

scriptName="$(command readlink -f -- "$0")"

CHECK_MODE=false

die() {
    builtin echo "ERROR($(basename "${scriptName}")): $*" >&2
    builtin exit 1
}

{  # outer scope braces

    parse_args() {
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --check)
                    CHECK_MODE=true
                    shift
                    ;;
                -h|--help)
                    show_help
                    exit 0
                    ;;
                *)
                    die "Unknown option: $1"
                    ;;
            esac
        done
    }

    show_help() {
        cat <<EOF
color-tools-install.sh - Install/validate tools for color-digest toolchain

Usage:
    color-tools-install.sh          Install missing tools via Scoop
    color-tools-install.sh --check  Validate all tools present (exit 0 if OK)

Required tools:
    - Python 3.13+
    - poppler (pdftotext, pdfinfo)
    - qpdf
    - coreutils (standard UNIX utilities)

Note: ripgrep was removed (automatic detection disabled)

Install method: Scoop package manager for Windows
EOF
    }

    check_command() {
        local cmd="$1"
        local package="${2:-$1}"
        
        if command -v "$cmd" &>/dev/null; then
            return 0
        else
            if [[ "$CHECK_MODE" == "false" ]]; then
                echo "Missing: $cmd (package: $package)"
            fi
            return 1
        fi
    }

    check_python_version() {
        if ! command -v python &>/dev/null; then
            if [[ "$CHECK_MODE" == "false" ]]; then
                echo "Missing: python (package: python)"
            fi
            return 1
        fi
        
        local version
        version=$(python --version 2>&1 | awk '{print $2}')
        local major minor
        major=$(echo "$version" | cut -d. -f1)
        minor=$(echo "$version" | cut -d. -f2)
        
        if [[ "$major" -lt 3 ]] || { [[ "$major" -eq 3 ]] && [[ "$minor" -lt 13 ]]; }; then
            if [[ "$CHECK_MODE" == "false" ]]; then
                echo "Python version $version found, but 3.13+ required"
            fi
            return 1
        fi
        
        return 0
    }

    check_scoop() {
        if ! command -v scoop &>/dev/null; then
            echo "ERROR: Scoop package manager not found" >&2
            echo "Install Scoop from https://scoop.sh/" >&2
            echo "Run: irm get.scoop.sh | iex" >&2
            return 1
        fi
        return 0
    }

    validate_all_tools() {
        local all_ok=true
        
        # Check Python version first
        if ! check_python_version; then
            all_ok=false
        fi
        
        # Check other tools
        if ! check_command pdftotext poppler; then all_ok=false; fi
        if ! check_command pdfinfo poppler; then all_ok=false; fi
        if ! check_command qpdf qpdf; then all_ok=false; fi
        # NOTE: ripgrep removed (automatic detection disabled)
        
        # coreutils typically present in Git Bash, but check key commands
        if ! check_command awk; then all_ok=false; fi
        if ! check_command sed; then all_ok=false; fi
        
        if [[ "$all_ok" == "true" ]]; then
            return 0
        else
            return 1
        fi
    }

    install_missing_tools() {
        echo "Checking tool dependencies..."
        
        if ! check_scoop; then
            die "Scoop package manager required for installation"
        fi
        
        local needs_install=false
        
        # Python
        if ! check_python_version; then
            echo "Will install: python (3.13+)"
            needs_install=true
        fi
        
        # Poppler
        if ! check_command pdftotext poppler; then
            echo "Will install: poppler"
            needs_install=true
        fi
        
        # qpdf
        if ! check_command qpdf qpdf; then
            echo "Will install: qpdf"
            needs_install=true
        fi
        
        # NOTE: ripgrep removed (automatic detection disabled)
        
        if [[ "$needs_install" == "false" ]]; then
            echo "All tools already installed!"
            show_versions
            return 0
        fi
        
        echo ""
        echo "Installing missing tools via Scoop..."
        echo ""
        
        # Install each missing tool
        if ! check_python_version; then
            echo "Installing Python..."
            scoop install python || die "Failed to install python"
        fi
        
        if ! check_command pdftotext poppler; then
            echo "Installing poppler..."
            scoop install poppler || die "Failed to install poppler"
        fi
        
        if ! check_command qpdf qpdf; then
            echo "Installing qpdf..."
            scoop install qpdf || die "Failed to install qpdf"
        fi
        
        # NOTE: ripgrep removed (automatic detection disabled)
        
        echo ""
        echo "Installation complete!"
        show_versions
    }

    show_versions() {
        echo ""
        echo "Installed tool versions:"
        
        if command -v python &>/dev/null; then
            python --version 2>&1 | sed 's/^/  /'
        fi
        
        if command -v pdftotext &>/dev/null; then
            pdftotext -v 2>&1 | head -n1 | sed 's/^/  /'
        fi
        
        if command -v qpdf &>/dev/null; then
            qpdf --version 2>&1 | head -n1 | sed 's/^/  /'
        fi
        
        # NOTE: ripgrep removed (automatic detection disabled)
    }

}

main() {
    parse_args "$@"
    
    if [[ "$CHECK_MODE" == "true" ]]; then
        # Check mode: silent validation, exit code indicates status
        if validate_all_tools; then
            exit 0
        else
            exit 1
        fi
    else
        # Install mode: interactive, install missing tools
        install_missing_tools
    fi
}

if [[ -z "${sourceMe:-}" ]]; then
    main "$@"
    builtin exit
fi
command true
