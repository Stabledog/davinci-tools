#!/bin/bash
# color-digest.sh
# Extract and digest a section from DaVinci Resolve manual
#
# Pipeline stages:
#   1. Validate inputs (manual exists, tools available)
#   2. Load page boundaries (from environment or metadata file)
#   3. Slice manual (extract pages to separate PDF)
#   4. Extract text (PDF to layout-preserved text)
#   5. Generate digest stub (markdown with placeholders and page refs)
#   6. Logging (reproducible run log with all metadata)

set -ue

#shellcheck disable=2154
PS4='$( _0=$?; exec 2>/dev/null; realpath -- "${BASH_SOURCE[0]:-?}:${LINENO} ^$_0 ${FUNCNAME[0]:-?}()=>" ) '
[[ -n "${DEBUGSH:-}" ]] && set -x

scriptName="$(command readlink -f -- "$0")"
scriptDir="$(command dirname -- "${scriptName}")"

# Global configuration with overrideable defaults
export REPO_ROOT="${REPO_ROOT:-"$(cd "${scriptDir}/.." && pwd)"}"
export DOCS_DIR="${DOCS_DIR:-"${REPO_ROOT}/docs"}"
export LOGS_DIR="${LOGS_DIR:-"${REPO_ROOT}/logs"}"
export BIN_DIR="${BIN_DIR:-"${REPO_ROOT}/bin"}"

export RESOLVE_MANUAL="${RESOLVE_MANUAL:-"${DOCS_DIR}/DaVinci_Resolve_Manual.pdf"}"
export CONFIG_FILE="${CONFIG_FILE:-"${BIN_DIR}/color-keywords.toml"}"
export CONFIG_READER="${CONFIG_READER:-"${BIN_DIR}/config-reader.py"}"
export INSTALL_SCRIPT="${INSTALL_SCRIPT:-"${BIN_DIR}/color-tools-install.sh"}"

# Output files
export COLOR_PDF="${COLOR_PDF:-"${DOCS_DIR}/DaVinci_Resolve_Manual.color-grading.pdf"}"
export COLOR_TXT="${COLOR_TXT:-"${DOCS_DIR}/DaVinci_Resolve_Manual.color-grading.txt"}"
export DIGEST_MD="${DIGEST_MD:-"${DOCS_DIR}/DaVinci_Resolve_Manual.digest.color-grading.md"}"

# Page boundary configuration (must be provided externally)
export START_PAGE="${START_PAGE:-}"
export END_PAGE="${END_PAGE:-}"

# Timestamp for this run
RUN_TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
export LOG_FILE="${LOG_FILE:-"${LOGS_DIR}/color-digest-run-${RUN_TIMESTAMP}.log"}"

# Temp files for detection
TEMP_DIR=""

die() {
    log_message "ERROR" "main" "$*"
    builtin echo "ERROR($(basename "${scriptName}")): $*" >&2
    cleanup
    builtin exit 1
}

{  # outer scope braces

    log_message() {
        # Unix-style log format: YYYY-MM-DD HH:MM:SS [category] [severity] message
        local severity="$1"
        local category="$2"
        shift 2
        local message="$*"
        local timestamp
        timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
        
        # Append to log file (create if needed)
        if [[ -n "${LOG_FILE:-}" ]]; then
            echo "${timestamp} [${category}] [${severity}] ${message}" >> "${LOG_FILE}"
        fi
        
        # Also echo to stdout for INFO, stderr for ERROR
        if [[ "$severity" == "ERROR" ]]; then
            echo "${timestamp} [${category}] [${severity}] ${message}" >&2
        elif [[ "$severity" == "INFO" ]]; then
            echo "${timestamp} [${category}] [${severity}] ${message}"
        fi
    }

    cleanup() {
        if [[ -n "${TEMP_DIR:-}" ]] && [[ -d "${TEMP_DIR}" ]]; then
            rm -rf "${TEMP_DIR}"
        fi
    }

    validate_prerequisites() {
        log_message "INFO" "validate" "Checking tool dependencies..."
        
        # Run install script in --check mode
        if ! "${INSTALL_SCRIPT}" --check; then
            die "Tool dependencies not satisfied. Run: ${INSTALL_SCRIPT}"
        fi
        
        log_message "INFO" "validate" "All tools present"
    }

    validate_inputs() {
        log_message "INFO" "validate" "Validating input files..."
        
        # Check manual exists
        if [[ ! -f "${RESOLVE_MANUAL}" ]] && [[ ! -L "${RESOLVE_MANUAL}" ]]; then
            die "Manual not found: ${RESOLVE_MANUAL}. Run bin/setup-kb.sh first?"
        fi
        
        # Resolve symlinks to get real path (needed for tools that don't follow symlinks)
        RESOLVE_MANUAL="$(readlink -f "${RESOLVE_MANUAL}")"
        log_message "INFO" "validate" "Resolved manual path: ${RESOLVE_MANUAL}"
        
        # Check config exists
        if [[ ! -f "${CONFIG_FILE}" ]]; then
            die "Config file not found: ${CONFIG_FILE}"
        fi
        
        # Check config reader
        if [[ ! -x "${CONFIG_READER}" ]]; then
            die "Config reader not found or not executable: ${CONFIG_READER}"
        fi
        
        # Get manual metadata
        log_message "INFO" "validate" "Reading manual metadata..."
        local manual_size
        manual_size="$(stat --format='%s' "${RESOLVE_MANUAL}" 2>/dev/null || stat -f%z "${RESOLVE_MANUAL}")"
        log_message "INFO" "validate" "Manual size: ${manual_size} bytes"
        
        # Get PDF info
        pdfinfo "${RESOLVE_MANUAL}" |& while IFS= read -r line; do
            log_message "INFO" "pdfinfo" "$line"
        done
        
        log_message "INFO" "validate" "Input validation complete"
    }

    log_tool_versions() {
        log_message "INFO" "versions" "Recording tool versions..."
        
        python --version 2>&1 | while IFS= read -r line; do
            log_message "INFO" "versions" "Python: $line"
        done
        
        pdftotext -v 2>&1 | head -n1 | while IFS= read -r line; do
            log_message "INFO" "versions" "pdftotext: $line"
        done
        
        qpdf --version 2>&1 | head -n1 | while IFS= read -r line; do
            log_message "INFO" "versions" "qpdf: $line"
        done
    }

    # ==============================================================================
    # AUTOMATIC BOUNDARY DETECTION - REMOVED
    # ==============================================================================
    # The detect_color_section() function was removed as part of strategy shift.
    # Previously this function performed:
    #   - TOC parsing and grep-based section discovery
    #   - Keyword density sliding window analysis
    #   - Ripgrep-based page content scanning
    #
    # These features were experimental and insufficiently smart to handle the general problem
    #
    # REPLACEMENT: Page boundaries must now be provided explicitly.
    # See AGENTS.md for rationale (failures are first-class data).
    # ==============================================================================

    load_page_boundaries() {
        log_message "INFO" "boundaries" "Loading page boundaries..."
        
        # Create temp directory for intermediate files
        TEMP_DIR="$(mktemp -d)"
        log_message "INFO" "boundaries" "Temp directory: ${TEMP_DIR}"
        
        # TODO: Support loading from metadata file (TOML/JSON)
        # For now, require environment variables
        if [[ -z "${START_PAGE:-}" ]] || [[ -z "${END_PAGE:-}" ]]; then
            die "Page boundaries required. Set START_PAGE and END_PAGE environment variables."
        fi
        
        # Validate page numbers are integers
        if ! [[ "${START_PAGE}" =~ ^[0-9]+$ ]] || ! [[ "${END_PAGE}" =~ ^[0-9]+$ ]]; then
            die "START_PAGE and END_PAGE must be positive integers"
        fi
        
        # Validate START_PAGE <= END_PAGE
        if [[ "${START_PAGE}" -gt "${END_PAGE}" ]]; then
            die "START_PAGE (${START_PAGE}) must be <= END_PAGE (${END_PAGE})"
        fi
        
        # Get total page count and validate bounds
        local total_pages
        total_pages="$(pdfinfo "${RESOLVE_MANUAL}" | grep '^Pages:' | awk '{print $2}')"
        log_message "INFO" "boundaries" "Total pages in manual: ${total_pages}"
        
        if [[ "${END_PAGE}" -gt "${total_pages}" ]]; then
            die "END_PAGE (${END_PAGE}) exceeds total pages (${total_pages})"
        fi
        
        log_message "INFO" "boundaries" "Using provided page boundaries: ${START_PAGE}-${END_PAGE}"
        
        # Export for use in next stages (compatible with existing slice_manual)
        echo "${START_PAGE}" > "${TEMP_DIR}/start_page"
        echo "${END_PAGE}" > "${TEMP_DIR}/end_page"
    }

    slice_manual() {
        log_message "INFO" "slice" "Slicing section from manual..."
        
        local start_page
        local end_page
        start_page="$(cat "${TEMP_DIR}/start_page")"
        end_page="$(cat "${TEMP_DIR}/end_page")"
        
        log_message "INFO" "slice" "Extracting pages ${start_page}-${end_page} to ${COLOR_PDF}"
        
        if ! qpdf "${RESOLVE_MANUAL}" --pages . "${start_page}-${end_page}" -- "${COLOR_PDF}"; then
            die "Failed to slice PDF with qpdf"
        fi
        
        local output_size
        output_size="$(stat --format='%s' "${COLOR_PDF}" 2>/dev/null || stat -f%z "${COLOR_PDF}")"
        log_message "INFO" "slice" "Created ${COLOR_PDF} (${output_size} bytes)"
    }

    extract_text() {
        log_message "INFO" "extract" "Extracting text from section PDF..."
        
        if ! pdftotext -layout "${COLOR_PDF}" "${COLOR_TXT}"; then
            die "Failed to extract text with pdftotext"
        fi
        
        local line_count
        line_count="$(wc -l < "${COLOR_TXT}")"
        log_message "INFO" "extract" "Created ${COLOR_TXT} (${line_count} lines)"
    }

    generate_digest() {
        log_message "INFO" "digest" "Generating digest stub..."
        
        local start_page
        local end_page
        start_page="$(cat "${TEMP_DIR}/start_page")"
        end_page="$(cat "${TEMP_DIR}/end_page")"
        
        # Get sections and glossary from config
        local sections
        sections=$("${CONFIG_READER}" --format json --config "${CONFIG_FILE}" | python -c "
import sys, json
config = json.load(sys.stdin)
if 'digest' in config and 'sections' in config['digest']:
    for section in config['digest']['sections']:
        print(section)
" 2>/dev/null || echo "Introduction
Color Page Layout
Primary Correction Tools
Secondary Correction Tools
Node System
Curves and Advanced Tools
Scopes and Measurement
LUTs and Color Management
ACES Workflow
HDR Grading
Practical Workflows
Troubleshooting")
        
        # Generate digest markdown
        cat > "${DIGEST_MD}" <<'DIGEST_HEADER'
# DaVinci Resolve Color Grading Digest

**Auto-generated digest stub with page references and diagram placeholders**

This document provides a structured overview of DaVinci Resolve's Color page, extracted from the official manual. Page references are to the Color section PDF (relative numbering within the extracted pages).

---

DIGEST_HEADER
        
        {
            echo "## Document Information"
            echo ""
            echo "- **Source:** DaVinci Resolve Manual (Color section)"
            echo "- **Extracted pages:** ${start_page}-${end_page} (PDF numbering)"
            echo "- **Generated:** $(date '+%Y-%m-%d %H:%M:%S')"
            echo "- **Total pages in section:** $((end_page - start_page + 1))"
            echo ""
            echo "---"
            echo ""
        } >> "${DIGEST_MD}"
        
        # Add sections with placeholders
        while IFS= read -r section; do
            [[ -z "$section" ]] && continue
            {
                echo "## ${section}"
                echo ""
                echo "*TODO: Summarize key concepts and workflows from this section.*"
                echo ""
                echo "**Page references:** (To be filled during manual review)"
                echo ""
                echo "---"
                echo ""
            } >> "${DIGEST_MD}"
        done <<< "$sections"
        
        # Add mermaid diagram placeholders
        {
            echo "## Diagrams"
            echo ""
            
            echo "### Node Graph Architecture"
            echo ""
            echo "<!-- TODO: Generate mermaid flowchart showing:"
            echo "     - Serial vs parallel node connections"
            echo "     - Input/output signal flow"
            echo "     - Node types and their relationships"
            echo "     See pages TBD -->"
            echo ""
            
            echo "### Color Pipeline"
            echo ""
            echo "<!-- TODO: Generate mermaid diagram showing:"
            echo "     - Input → Color Space Transform → Grading → Output Transform"
            echo "     - Where LUTs fit in the pipeline"
            echo "     See pages TBD -->"
            echo ""
            
            echo "### Scopes Decision Helper"
            echo ""
            echo "<!-- TODO: Generate decision tree/flowchart:"
            echo "     - Which scope for which task (Waveform vs Parade vs Vectorscope)"
            echo "     - When to use Histogram vs Waveform"
            echo "     See pages TBD -->"
            echo ""
            
            echo "### LUT Placement Options"
            echo ""
            echo "<!-- TODO: Generate diagram showing:"
            echo "     - Timeline vs Clip vs Node LUT placement"
            echo "     - Order of operations"
            echo "     See pages TBD -->"
            echo ""
            
            echo "---"
            echo ""
            
            echo "## Glossary"
            echo ""
        } >> "${DIGEST_MD}"
        
        local terms
        terms=$("${CONFIG_READER}" --format json --config "${CONFIG_FILE}" | python -c "
import sys, json
config = json.load(sys.stdin)
if 'glossary' in config and 'terms' in config['glossary']:
    for term in config['glossary']['terms']:
        print(term)
" 2>/dev/null || echo "Node
Primary
Secondary
Qualifier
Power Window
Tracker
LUT
ACES
HDR
PQ
HLG
Color Warper
Gallery
CDL")
        
        while IFS= read -r term; do
            [[ -z "$term" ]] && continue
            {
                echo "### ${term}"
                echo ""
                echo "*Definition and usage notes to be filled. Page references: TBD*"
                echo ""
            } >> "${DIGEST_MD}"
        done <<< "$terms"
        
        log_message "INFO" "digest" "Created ${DIGEST_MD}"
    }

}

main() {
    log_message "INFO" "main" "Starting color-digest pipeline"
    log_message "INFO" "main" "Log file: ${LOG_FILE}"
    
    # Ensure logs directory exists
    mkdir -p "${LOGS_DIR}"
    
    # Stage 1: Validate
    validate_prerequisites
    validate_inputs
    log_tool_versions
    
    # Stage 2: Load page boundaries (provided externally, not auto-detected)
    load_page_boundaries
    
    # Stage 3: Slice
    slice_manual
    
    # Stage 4: Extract text
    extract_text
    
    # Stage 5: Generate digest
    generate_digest
    
    # Stage 6: Logging complete
    log_message "INFO" "main" "Pipeline complete!"
    log_message "INFO" "main" "Outputs:"
    log_message "INFO" "main" "  - ${COLOR_PDF}"
    log_message "INFO" "main" "  - ${COLOR_TXT}"
    log_message "INFO" "main" "  - ${DIGEST_MD}"
    log_message "INFO" "main" "  - ${LOG_FILE}"
    
    cleanup
}

if [[ -z "${sourceMe:-}" ]]; then
    main "$@"
    builtin exit
fi
command true
