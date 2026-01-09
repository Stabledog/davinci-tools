#!/bin/bash
# color-digest.sh
# Automatically extract and digest the Color section from DaVinci Resolve manual
#
# Pipeline stages:
#   1. Validate inputs (manual exists, tools available)
#   2. Outline/keyword detection (find Color section boundaries)
#   3. Slice manual (extract Color pages to separate PDF)
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

# Detection thresholds (experimental, tunable)
MIN_KEYWORD_DENSITY="${MIN_KEYWORD_DENSITY:-5}"
WINDOW_SIZE="${WINDOW_SIZE:-10}"

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
        
        rg --version 2>&1 | head -n1 | while IFS= read -r line; do
            log_message "INFO" "versions" "ripgrep: $line"
        done
    }

    detect_color_section() {
        log_message "INFO" "detect" "Starting Color section detection..."
        
        # Create temp directory
        TEMP_DIR="$(mktemp -d)"
        log_message "INFO" "detect" "Temp directory: ${TEMP_DIR}"
        
        # Extract bookmarks/outline
        log_message "INFO" "detect" "Extracting PDF outline/bookmarks..."
        
        # For a large PDF, qpdf JSON parsing can be slow/complex
        # Instead, extract TOC from first pages to find section boundaries
        log_message "INFO" "detect" "Extracting table of contents..."
        pdftotext -f 1 -l 30 -layout "${RESOLVE_MANUAL}" "${TEMP_DIR}/toc.txt"
        
        # Scan for "Color" bookmark/heading
        local color_start_page=""
        local color_end_page=""
        
        # Simple heuristic: grep for "Color" in TOC and extract page numbers
        # This is a simplified approach; real implementation may need OCR or better outline parsing
        if grep -i "^.*Color.*\\.\\+.*[0-9]\\+$" "${TEMP_DIR}/toc.txt" > "${TEMP_DIR}/color_toc_match.txt" 2>/dev/null; then
            log_message "INFO" "detect" "Found Color references in TOC"
            cat "${TEMP_DIR}/color_toc_match.txt" | while IFS= read -r line; do
                log_message "INFO" "detect" "TOC match: $line"
            done
        fi
        
        # Get total page count
        local total_pages
        total_pages="$(pdfinfo "${RESOLVE_MANUAL}" | grep '^Pages:' | awk '{print $2}')"
        log_message "INFO" "detect" "Total pages in manual: ${total_pages}"
        
        # Try to narrow range using TOC
        local toc_hint_start=""
        local toc_hint_end=""
        
        # Look for main Color Page chapter in TOC
        # Priority: "Using the Color Page" > "Introduction to Color Grading" > generic "Color"
        if grep -E -i "(using the color page|introduction to color grading|color page timeline).*[0-9]{2,4}" "${TEMP_DIR}/toc.txt" > "${TEMP_DIR}/color_toc_match.txt" 2>/dev/null; then
            log_message "INFO" "detect" "Found main Color Page chapter in TOC:"
            cat "${TEMP_DIR}/color_toc_match.txt" | while IFS= read -r line; do
                log_message "INFO" "detect" "  $line"
            done
            
            # Extract first page number from the main Color section
            toc_hint_start=$(grep -E -i -o "(using the color page|introduction to color grading).*[0-9]{2,4}" "${TEMP_DIR}/color_toc_match.txt" | head -n1 | grep -o "[0-9]\{2,4\}$" || echo "")
            if [[ -n "$toc_hint_start" ]]; then
                log_message "INFO" "detect" "TOC indicates main Color section starts around page ${toc_hint_start}"
            fi
        elif grep -E -i "color.*[0-9]{2,4}" "${TEMP_DIR}/toc.txt" > "${TEMP_DIR}/color_toc_lines.txt" 2>/dev/null; then
            log_message "WARN" "detect" "Could not find main Color Page chapter, using generic color matches:"
            cat "${TEMP_DIR}/color_toc_lines.txt" | head -n 5 | while IFS= read -r line; do
                log_message "WARN" "detect" "  $line"
            done
            
            # Fallback: extract first page number (may not be the main Color section)
            toc_hint_start=$(grep -E -i -o "color.*[0-9]{2,4}" "${TEMP_DIR}/color_toc_lines.txt" | head -n1 | grep -o "[0-9]\{2,4\}$" || echo "")
            if [[ -n "$toc_hint_start" ]]; then
                log_message "WARN" "detect" "TOC suggests Color-related content starts around page ${toc_hint_start} (may need manual verification)"
            fi
        fi
        
        # Keyword-based detection: scan manual in chunks
        # If we have a TOC hint, start there; otherwise scan broadly
        local scan_start=1
        local scan_end="$total_pages"
        
        if [[ -n "$toc_hint_start" ]] && [[ "$toc_hint_start" -gt 0 ]]; then
            # Search window around TOC hint
            scan_start=$((toc_hint_start - 50))
            if [[ $scan_start -lt 1 ]]; then scan_start=1; fi
            scan_end=$((toc_hint_start + 500))  # Color section is likely large, search ahead
            if [[ $scan_end -gt $total_pages ]]; then scan_end=$total_pages; fi
            log_message "INFO" "detect" "Narrowing scan range to pages ${scan_start}-${scan_end} based on TOC"
        fi
        
        log_message "INFO" "detect" "Starting keyword-based page scanning (range: ${scan_start}-${scan_end})..."
        log_message "INFO" "detect" "Starting keyword-based page scanning (range: ${scan_start}-${scan_end})..."
        log_message "INFO" "detect" "This may take several minutes for a large manual..."
        
        # Get keywords from config
        local keywords_file="${TEMP_DIR}/keywords.txt"
        "${CONFIG_READER}" --list-keywords --config "${CONFIG_FILE}" > "${keywords_file}"
        local keyword_count
        keyword_count="$(wc -l < "${keywords_file}")"
        log_message "INFO" "detect" "Loaded ${keyword_count} keywords from config"
        
        # Scan pages in chunks to find highest density region
        local best_start=0
        local best_end=0
        local best_density=0
        
        # For efficiency, sample every 10 pages initially
        local sample_stride=10
        for ((page=scan_start; page<=scan_end; page+=sample_stride)); do
            local end_page=$((page + WINDOW_SIZE))
            if [[ $end_page -gt $total_pages ]]; then
                end_page=$total_pages
            fi
            
            # Extract text for this window
            pdftotext -f "$page" -l "$end_page" -layout "${RESOLVE_MANUAL}" "${TEMP_DIR}/window_${page}.txt" 2>/dev/null || continue
            
            # Count keyword hits
            local hits=0
            while IFS= read -r keyword; do
                local count
                count=$(rg -i -c "$keyword" "${TEMP_DIR}/window_${page}.txt" 2>/dev/null || echo "0")
                hits=$((hits + count))
            done < "${keywords_file}"
            
            local density=$((hits / WINDOW_SIZE))
            
            if [[ $density -gt $best_density ]]; then
                best_density=$density
                best_start=$page
                best_end=$end_page
                log_message "INFO" "detect" "New best window: pages ${best_start}-${best_end}, density=${best_density} hits/page"
            fi
        done
        
        if [[ $best_density -lt $MIN_KEYWORD_DENSITY ]]; then
            log_message "WARN" "detect" "Best keyword density ($best_density) below threshold ($MIN_KEYWORD_DENSITY)"
            log_message "WARN" "detect" "Proceeding anyway; may need manual adjustment"
        fi
        
        # Refine boundaries: expand window and find precise start/end
        local refined_start=$((best_start - 50))
        if [[ $refined_start -lt 1 ]]; then refined_start=1; fi
        
        local refined_end=$((best_end + 50))
        if [[ $refined_end -gt $total_pages ]]; then refined_end=$total_pages; fi
        
        # Find first page with strong "Color" keyword match
        for ((page=refined_start; page<=best_start; page++)); do
            pdftotext -f "$page" -l "$page" -layout "${RESOLVE_MANUAL}" "${TEMP_DIR}/page_${page}.txt" 2>/dev/null || continue
            if rg -i "Color Page|Color Grading|^Color$" "${TEMP_DIR}/page_${page}.txt" &>/dev/null; then
                color_start_page=$page
                log_message "INFO" "detect" "Found Color section start: page ${color_start_page}"
                break
            fi
        done
        
        if [[ -z "$color_start_page" ]]; then
            color_start_page=$best_start
            log_message "WARN" "detect" "Could not find precise start, using window start: ${color_start_page}"
        fi
        
        # Find end: where keyword density drops significantly
        local previous_density=$best_density
        for ((page=best_end; page<=refined_end; page++)); do
            pdftotext -f "$page" -l "$((page + 5))" -layout "${RESOLVE_MANUAL}" "${TEMP_DIR}/endcheck_${page}.txt" 2>/dev/null || continue
            
            local hits=0
            while IFS= read -r keyword; do
                local count
                count=$(rg -i -c "$keyword" "${TEMP_DIR}/endcheck_${page}.txt" 2>/dev/null || echo "0")
                hits=$((hits + count))
            done < "${keywords_file}"
            
            local density=$((hits / 5))
            
            if [[ $density -lt $((previous_density / 2)) ]]; then
                color_end_page=$page
                log_message "INFO" "detect" "Found Color section end: page ${color_end_page} (density dropped to ${density})"
                break
            fi
        done
        
        if [[ -z "$color_end_page" ]]; then
            color_end_page=$refined_end
            log_message "WARN" "detect" "Could not find precise end, using refined window end: ${color_end_page}"
        fi
        
        # Write detection report
        local report_file="${TEMP_DIR}/detection-report.md"
        cat > "${report_file}" <<EOF
# Color Section Detection Report

## Manual Information
- File: ${RESOLVE_MANUAL}
- Total pages: ${total_pages}

## Detection Results
- **Start page:** ${color_start_page}
- **End page:** ${color_end_page}
- **Page count:** $((color_end_page - color_start_page + 1))
- **Best keyword density:** ${best_density} hits/page
- **Detection threshold:** ${MIN_KEYWORD_DENSITY} hits/page

## Keywords Used
- Config file: ${CONFIG_FILE}
- Keyword count: ${keyword_count}

## Notes
$(if [[ $best_density -lt $MIN_KEYWORD_DENSITY ]]; then
    echo "- ⚠️ Keyword density below threshold; results may need manual review"
fi)
EOF
        
        log_message "INFO" "detect" "Detection complete: pages ${color_start_page}-${color_end_page}"
        log_message "INFO" "detect" "Detection report: ${report_file}"
        
        # Export for use in next stages
        echo "${color_start_page}" > "${TEMP_DIR}/start_page"
        echo "${color_end_page}" > "${TEMP_DIR}/end_page"
    }

    slice_manual() {
        log_message "INFO" "slice" "Slicing Color section from manual..."
        
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
        log_message "INFO" "extract" "Extracting text from Color section PDF..."
        
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
        
        echo "## Document Information" >> "${DIGEST_MD}"
        echo "" >> "${DIGEST_MD}"
        echo "- **Source:** DaVinci Resolve Manual (Color section)" >> "${DIGEST_MD}"
        echo "- **Extracted pages:** ${start_page}-${end_page} (PDF numbering)" >> "${DIGEST_MD}"
        echo "- **Generated:** $(date '+%Y-%m-%d %H:%M:%S')" >> "${DIGEST_MD}"
        echo "- **Total pages in section:** $((end_page - start_page + 1))" >> "${DIGEST_MD}"
        echo "" >> "${DIGEST_MD}"
        echo "---" >> "${DIGEST_MD}"
        echo "" >> "${DIGEST_MD}"
        
        # Add sections with placeholders
        while IFS= read -r section; do
            [[ -z "$section" ]] && continue
            echo "## ${section}" >> "${DIGEST_MD}"
            echo "" >> "${DIGEST_MD}"
            echo "*TODO: Summarize key concepts and workflows from this section.*" >> "${DIGEST_MD}"
            echo "" >> "${DIGEST_MD}"
            echo "**Page references:** (To be filled during manual review)" >> "${DIGEST_MD}"
            echo "" >> "${DIGEST_MD}"
            echo "---" >> "${DIGEST_MD}"
            echo "" >> "${DIGEST_MD}"
        done <<< "$sections"
        
        # Add mermaid diagram placeholders
        echo "## Diagrams" >> "${DIGEST_MD}"
        echo "" >> "${DIGEST_MD}"
        
        echo "### Node Graph Architecture" >> "${DIGEST_MD}"
        echo "" >> "${DIGEST_MD}"
        echo "<!-- TODO: Generate mermaid flowchart showing:" >> "${DIGEST_MD}"
        echo "     - Serial vs parallel node connections" >> "${DIGEST_MD}"
        echo "     - Input/output signal flow" >> "${DIGEST_MD}"
        echo "     - Node types and their relationships" >> "${DIGEST_MD}"
        echo "     See pages TBD -->" >> "${DIGEST_MD}"
        echo "" >> "${DIGEST_MD}"
        
        echo "### Color Pipeline" >> "${DIGEST_MD}"
        echo "" >> "${DIGEST_MD}"
        echo "<!-- TODO: Generate mermaid diagram showing:" >> "${DIGEST_MD}"
        echo "     - Input → Color Space Transform → Grading → Output Transform" >> "${DIGEST_MD}"
        echo "     - Where LUTs fit in the pipeline" >> "${DIGEST_MD}"
        echo "     See pages TBD -->" >> "${DIGEST_MD}"
        echo "" >> "${DIGEST_MD}"
        
        echo "### Scopes Decision Helper" >> "${DIGEST_MD}"
        echo "" >> "${DIGEST_MD}"
        echo "<!-- TODO: Generate decision tree/flowchart:" >> "${DIGEST_MD}"
        echo "     - Which scope for which task (Waveform vs Parade vs Vectorscope)" >> "${DIGEST_MD}"
        echo "     - When to use Histogram vs Waveform" >> "${DIGEST_MD}"
        echo "     See pages TBD -->" >> "${DIGEST_MD}"
        echo "" >> "${DIGEST_MD}"
        
        echo "### LUT Placement Options" >> "${DIGEST_MD}"
        echo "" >> "${DIGEST_MD}"
        echo "<!-- TODO: Generate diagram showing:" >> "${DIGEST_MD}"
        echo "     - Timeline vs Clip vs Node LUT placement" >> "${DIGEST_MD}"
        echo "     - Order of operations" >> "${DIGEST_MD}"
        echo "     See pages TBD -->" >> "${DIGEST_MD}"
        echo "" >> "${DIGEST_MD}"
        
        echo "---" >> "${DIGEST_MD}"
        echo "" >> "${DIGEST_MD}"
        
        # Add glossary
        echo "## Glossary" >> "${DIGEST_MD}"
        echo "" >> "${DIGEST_MD}"
        
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
            echo "### ${term}" >> "${DIGEST_MD}"
            echo "" >> "${DIGEST_MD}"
            echo "*Definition and usage notes to be filled. Page references: TBD*" >> "${DIGEST_MD}"
            echo "" >> "${DIGEST_MD}"
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
    
    # Stage 2: Detect
    detect_color_section
    
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
