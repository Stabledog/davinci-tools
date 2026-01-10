#!/bin/bash
# doc-tools-install.sh - Install/check documentation processing tools via Scoop
# AI agents: be sure to check ../AGENTS.md and make changes that conform to ../SHELL_SCRIPT_TEMPLATE.md as a standard.
# 
# Usage:
#   doc-tools-install.sh           # Install all required tools
#   doc-tools-install.sh --check   # Check if tools are installed (returns 0 if all present)
#
# Required tools:
#   - poppler (pdftotext, pdfinfo)
#   - qpdf (PDF manipulation)
#   - python (3.13+)
#   - jq (JSON processing)

set -euo pipefail  # Be strict about error handling


# PS4 provides good diagnostics when -x is turned on
#shellcheck disable=2154
PS4='$( _0=$?; exec 2>/dev/null; realpath -- "${BASH_SOURCE[0]:-?}:${LINENO} ^$_0 ${FUNCNAME[0]:-?}()=>" ) '
[[ -n "${DEBUGSH:-}" ]] && set -x # Allows the user to enable debugging output via environment

scriptName="${scriptName:-"$(command readlink -f -- "$0")"}"


# Color output helpers
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color


die() {
    # Logic which aborts should do so by calling 'die "message text"'
    builtin echo "ERROR($(basename "${scriptName}")): $*" >&2
    builtin exit 1
}

{  # "outer scope braces" -- this block contains all functions except die() and main()

    log_info() {
        echo -e "${GREEN}[INFO]${NC} $*"
    }

    log_warn() {
        echo -e "${YELLOW}[WARN]${NC} $*"
    }

    log_error() {
        echo -e "${RED}[ERROR]${NC} $*" >&2
    }

    # Check if command exists
    command_exists() {
        command -v "$1" &>/dev/null
    }

    # Check if Scoop is installed
    check_scoop() {
        if ! command_exists scoop; then
            log_error "Scoop package manager not found"
            log_error "Install from: https://scoop.sh/"
            log_error "Run: iwr -useb get.scoop.sh | iex"
            return 1
        fi
        return 0
    }

    # Check tool version
    check_tool_version() {
        local tool=$1
        local cmd=$2
        
        if command_exists "$tool"; then
            local version
            version=$($cmd 2>&1 | head -n1 || echo "unknown")
            echo "  ✓ $tool: $version"
            return 0
        else
            echo "  ✗ $tool: NOT FOUND"
            return 1
        fi
    }

    # Check all required tools
    check_all_tools() {
        local all_present=0
        
        echo "Checking required tools..."
        echo
        
        # Check poppler (pdftotext, pdfinfo)
        check_tool_version "pdftotext" "pdftotext -v" || all_present=1
        check_tool_version "pdfinfo" "pdfinfo -v" || all_present=1
        
        # Check qpdf
        check_tool_version "qpdf" "qpdf --version" || all_present=1
        
        # Check Python (require 3.13+)
        if command_exists python; then
            local py_version
            py_version=$(python --version 2>&1 | cut -d' ' -f2)
            local py_major py_minor
            py_major=$(echo "$py_version" | cut -d. -f1)
            py_minor=$(echo "$py_version" | cut -d. -f2)
            
            if [[ $py_major -ge 3 ]] && [[ $py_minor -ge 13 ]]; then
                echo "  ✓ python: $py_version"
            else
                echo "  ✗ python: $py_version (require 3.13+)"
                all_present=1
            fi
        else
            echo "  ✗ python: NOT FOUND"
            all_present=1
        fi
        
        # Check jq
        check_tool_version "jq" "jq --version" || all_present=1
        
        echo
        return $all_present
    }

    # Install tools via Scoop
    install_tools() {
        log_info "Installing documentation processing tools via Scoop..."
        echo
        
        if ! check_scoop; then
            return 1
        fi
        
        # Install poppler
        if ! command_exists pdftotext; then
            log_info "Installing poppler..."
            scoop install poppler
        else
            log_info "poppler already installed"
        fi
        
        # Install qpdf
        if ! command_exists qpdf; then
            log_info "Installing qpdf..."
            scoop install qpdf
        else
            log_info "qpdf already installed"
        fi
        
        # Install Python
        if ! command_exists python; then
            log_info "Installing python..."
            scoop install python
        else
            local py_version
            py_version=$(python --version 2>&1 | cut -d' ' -f2)
            local py_major py_minor
            py_major=$(echo "$py_version" | cut -d. -f1)
            py_minor=$(echo "$py_version" | cut -d. -f2)
            
            if [[ $py_major -lt 3 ]] || [[ $py_minor -lt 13 ]]; then
                log_warn "Python $py_version found, but 3.13+ required"
                log_info "Updating python..."
                scoop update python
            else
                log_info "python $py_version already installed"
            fi
        fi
        
        # Install jq
        if ! command_exists jq; then
            log_info "Installing jq..."
            scoop install jq
        else
            log_info "jq already installed"
        fi
        
        echo
        log_info "Installation complete!"
        echo
        
        # Show final status
        check_all_tools
    }

}  # End outer scope braces

# Main logic
main() {
    set -ue
    local check_mode=0
    
    # Parse arguments
    if [[ $# -gt 0 ]] && [[ "$1" == "--check" ]]; then
        check_mode=1
    fi
    
    if [[ $check_mode -eq 1 ]]; then
        # Check mode: verify all tools present
        if check_all_tools; then
            log_info "All required tools are installed"
        else
            die "Some required tools are missing. Run 'bin/doc-tools-install.sh' to install them"
        fi
    else
        # Install mode
        install_tools
    fi
}

#  The "sourceMe" conditional allows the user to source the script into their current shell
#  to work with the individual helper functions, overwrite global vars, etc.
if [[ -z "${sourceMe:-}" ]]; then
    main "$@"
    builtin exit
fi
command true
