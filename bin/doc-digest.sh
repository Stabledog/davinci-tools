#!/bin/bash
# doc-digest.sh - Main orchestrator for documentation digest pipeline
# AI agents: be sure to check ../AGENTS.md and make changes that conform to ../SHELL_SCRIPT_TEMPLATE.md as a standard.
# Usage:
#   doc-digest.sh --metadata <path-to-metadata.toml> [--section <name>] [--skip-ai]
#
# Processes PDF documentation sections defined in metadata file:
#   1. Validates inputs (metadata, source PDF, page ranges)
#   2. Slices PDF into sections using qpdf
#   3. Extracts text using pdftotext
#   4. Generates AI-powered summaries and indexes
#   5. Creates consolidated artifacts (master index, cross-refs, quick reference)
#   6. Logs all operations for reproducibility

set -ue  # Always default to strict -ue

# PS4 provides good diagnostics when -x is turned on
#shellcheck disable=2154
PS4='$( _0=$?; exec 2>/dev/null; realpath -- "${BASH_SOURCE[0]:-?}:${LINENO} ^$_0 ${FUNCNAME[0]:-?}()=>" ) '
[[ -n "${DEBUGSH:-}" ]] && set -x # Allows the user to enable debugging output via environment
set -euo pipefail  # Be strict about error handling

scriptName="${scriptName:-"$(command readlink -f -- "$0")"}"
scriptDir="$(command dirname -- "${scriptName}")"

# Script directory and workspace root
WORKSPACE_ROOT="$(cd "$scriptDir/.." && pwd)"

# Default configuration
export OUTPUT_DIR="${OUTPUT_DIR:-$WORKSPACE_ROOT/docs}"
export OUTPUT_DIR_OVERRIDE="${OUTPUT_DIR_OVERRIDE:-}"  # Track if user explicitly set OUTPUT_DIR
export LOG_DIR="${LOG_DIR:-$WORKSPACE_ROOT/logs}"
export AI_PROVIDER="${AI_PROVIDER:-anthropic}"
export AI_MODEL="${AI_MODEL:-}"
export AI_MAX_TOKENS="${AI_MAX_TOKENS:-16384}"

# Log file
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
LOG_FILE="$LOG_DIR/doc-digest-run-$TIMESTAMP.log"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'


die() {
    # Logic which aborts should do so by calling 'die "message text"'
    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] [ERROR] $*" | tee -a "$LOG_FILE" >&2
    builtin echo "ERROR($(basename "${scriptName}")): $*" >&2
    builtin exit 1
}

{  # "outer scope braces" -- this block contains all functions except die() and main()

    # Logging functions
    log() {
        local level=$1
        shift
        local msg="$*"
        local timestamp
        timestamp=$(date +"%Y-%m-%d %H:%M:%S")
        echo "[$timestamp] [$level] $msg" >> "$LOG_FILE"
    }

    log_info() {
        log "INFO" "$@"
        echo -e "${GREEN}[INFO]${NC} $*"
    }

    log_warn() {
        log "WARN" "$@"
        echo -e "${YELLOW}[WARN]${NC} $*"
    }

    log_error() {
        log "ERROR" "$@"
        echo -e "${RED}[ERROR]${NC} $*" >&2
    }

    log_section() {
        log "INFO" "========== $* =========="
        echo
        echo -e "${BLUE}========== $* ==========${NC}"
        echo
    }

    check_dependencies() {
    log_section "Checking Dependencies"
    
    if ! "$scriptDir/doc-tools-install.sh" --check; then
        die "Required tools are missing. Run: $scriptDir/doc-tools-install.sh"
    fi
    
    # Log tool versions
    log "INFO" "Tool versions:"
    log "INFO" "  pdftotext: $(pdftotext -v 2>&1 | head -n1)"
    log "INFO" "  qpdf: $(qpdf --version 2>&1)"
    log "INFO" "  python: $(python --version 2>&1)"
    log "INFO" "  jq: $(jq --version 2>&1)"
    
    log_info "✓ All dependencies present"
    }

    check_ai_connection() {
    log_section "Validating AI Connection"
    
    log_info "Testing $AI_PROVIDER API connection..."
    
    # Use Python to test the actual API connection
    local test_result
    if ! test_result=$(python "$scriptDir/doc-ai-processor.py" \
        --test-connection \
        --provider "$AI_PROVIDER" \
        ${AI_MODEL:+--model "$AI_MODEL"} \
        --max-tokens 100 2>&1); then
        log_error "AI connection test failed"
        echo "$test_result" >&2
        die "Cannot proceed without valid AI API access. Please check your API key and credentials."
    fi
    
    log_info "✓ AI connection validated"
    }

    # Parse metadata file (TOML or JSON)
    parse_metadata() {
    local metadata_file=$1
    
    # Note: Do NOT call log functions here as this function's stdout is captured
    # Caller should log before calling this function
    
    if [[ ! -f "$metadata_file" ]]; then
        die "Metadata file not found: $metadata_file"
    fi
    
        # Use external Python script to parse and validate
        local metadata_json
        if ! metadata_json=$(python "$scriptDir/metadata-parser.py" "$metadata_file" 2>&1); then
            die "Failed to parse metadata file: $metadata_json"
        fi
        
        echo "$metadata_json"
    }

    # Validate PDF and get info
    validate_pdf() {
        local pdf_path=$1
        
        # Note: Do NOT call log functions here as this function's stdout is captured
        # Caller should log before calling this function
        
        # Resolve relative path
        if [[ ! "$pdf_path" = /* ]]; then
            pdf_path="$WORKSPACE_ROOT/$pdf_path"
        fi
        
        if [[ ! -f "$pdf_path" ]]; then
            die "Source PDF not found: $pdf_path"
        fi
        
        # Get PDF info
        local pdf_info
        pdf_info=$(pdfinfo "$pdf_path" 2>&1)
        
        local page_count
        page_count=$(echo "$pdf_info" | grep "Pages:" | awk '{print $2}')
        
        # Write info to log file directly to avoid polluting stdout
        {
            echo "[$(date +"%Y-%m-%d %H:%M:%S")] [INFO] PDF Info:"
            echo "[$(date +"%Y-%m-%d %H:%M:%S")] [INFO]   Path: $pdf_path"
            echo "[$(date +"%Y-%m-%d %H:%M:%S")] [INFO]   Pages: $page_count"
            echo "[$(date +"%Y-%m-%d %H:%M:%S")] [INFO]   Size: $(du -h "$pdf_path" | cut -f1)"
        } >> "$LOG_FILE"
        
        echo "$page_count"
    }

    # Validate section page ranges
    validate_sections() {
        local metadata_json=$1
        local page_count=$2
        local section_filter=$3
        
        # Note: Minimize stdout pollution - this function's output is captured
        
        local sections
        sections=$(echo "$metadata_json" | jq -c '.sections[]')
        
        local valid_sections=()
        
        while IFS= read -r section; do
            local name start_page end_page
            name=$(echo "$section" | jq -r '.name')
            start_page=$(echo "$section" | jq -r '.start_page')
            end_page=$(echo "$section" | jq -r '.end_page')
            
            # Apply section filter if specified
            if [[ -n "$section_filter" ]] && [[ "$name" != "$section_filter" ]]; then
                continue
            fi
            
            # Validate page range
            if [[ $start_page -lt 1 ]] || [[ $start_page -gt $page_count ]]; then
                die "Section '$name': start_page $start_page out of range (1-$page_count)"
            fi
            
            if [[ $end_page -lt 1 ]] || [[ $end_page -gt $page_count ]]; then
                die "Section '$name': end_page $end_page out of range (1-$page_count)"
            fi
            
            if [[ $end_page -lt $start_page ]]; then
                die "Section '$name': end_page ($end_page) < start_page ($start_page)"
            fi
            
            # Log to file directly
            echo "[$(date +"%Y-%m-%d %H:%M:%S")] [INFO] ✓ Section '$name': pages $start_page-$end_page" >> "$LOG_FILE"
            valid_sections+=("$section")
        done <<< "$sections"
        
        if [[ ${#valid_sections[@]} -eq 0 ]]; then
            die "No valid sections to process"
        fi
        
        # Return valid sections as JSON array
        printf '%s\n' "${valid_sections[@]}" | jq -s '.'
    }

    # Slice PDF section
    slice_pdf() {
        local source_pdf=$1
        local start_page=$2
        local end_page=$3
        local output_pdf=$4
        
        log_info "Slicing PDF: pages $start_page-$end_page -> $output_pdf"
        
        if ! qpdf --pages "$source_pdf" "$start_page-$end_page" -- --empty "$output_pdf"; then
            die "Failed to slice PDF"
        fi
        
        log "INFO" "  Output: $output_pdf ($(du -h "$output_pdf" | cut -f1))"
    }

    # Extract text from PDF
    extract_text() {
        local pdf_file=$1
        local text_file=$2
        
            log_info "Extracting text: $pdf_file -> $text_file"
        
        if ! pdftotext -layout "$pdf_file" "$text_file"; then
            die "Failed to extract text"
        fi
        
        local char_count line_count
        char_count=$(wc -c < "$text_file")
        line_count=$(wc -l < "$text_file")
        
        if [[ $char_count -eq 0 ]]; then
            log_warn "Extracted text is empty!"
            return 1
        fi
        
        log "INFO" "  Text: $char_count chars, $line_count lines"
    }

    # Process section with AI
    process_with_ai() {
        local text_file=$1
        local section_json=$2
        local source_name=$3
        local doc_version=$4
        
        local name title description
        name=$(echo "$section_json" | jq -r '.name')
        title=$(echo "$section_json" | jq -r '.title')
        description=$(echo "$section_json" | jq -r '.description // ""')
        
        log "INFO" "Processing with AI: $name"
        
        # Call Python AI processor (stderr stays separate for progress messages)
        local ai_result
        if ! ai_result=$(python "$scriptDir/doc-ai-processor.py" \
            --text-file "$text_file" \
            --section-name "$name" \
            --section-title "$title" \
            --section-description "$description" \
            --doc-version "$doc_version" \
            --source-name "$source_name" \
            --output-dir "$OUTPUT_DIR" \
            --provider "$AI_PROVIDER" \
            ${AI_MODEL:+--model "$AI_MODEL"} \
            --max-tokens "$AI_MAX_TOKENS"); then
            die "AI processing failed: check log for details"
        fi
        
        # Debug: save Python output for forensics (per-section cache for --skip-ai)
        local cached_response="$OUTPUT_DIR/${source_name}.ai-response.${name}.json"
        echo "$ai_result" | tail -n1 > "$cached_response"
        log "DEBUG" "Cached AI response to $cached_response"
        
        # Parse AI result
        local summary_file index_file char_count
        summary_file=$(echo "$ai_result" | tail -n1 | jq -r '.summary_file')
        index_file=$(echo "$ai_result" | tail -n1 | jq -r '.index_file')
        char_count=$(echo "$ai_result" | tail -n1 | jq -r '.char_count')
        
        log "INFO" "  Summary: $summary_file"
        log "INFO" "  Index: $index_file"
        log "INFO" "  Processed: $char_count chars"
        
        echo "$ai_result" | tail -n1
    }

    # Generate master index
    generate_master_index() {
        local source_name=$1
        shift
        local index_files=("$@")
        
        log_section "Generating Master Index"
        
        local master_index="$OUTPUT_DIR/${source_name}.master-index.json"
        
        log_info "Combining ${#index_files[@]} section indexes"
    
        # Merge all indexes
        local merge_script
        #shellcheck disable=2116
        merge_script=$(cut -c 13- <<-'PYEOF'
            import sys
            import json
            
            index_files = sys.argv[1:]
            master = {
                "source": "",
                "sections": [],
                "all_concepts": [],
                "all_terms": [],
                "all_topics": []
            }
            
            for idx_file in index_files:
                with open(idx_file, 'r', encoding='utf-8') as f:
                    data = json.load(f)
                
                master["sections"].append({
                    "name": data.get("section", "unknown"),
                    "title": data.get("title", "Unknown"),
                    "index_file": idx_file
                })
                
                if "concepts" in data:
                    master["all_concepts"].extend(data["concepts"])
                if "terms" in data:
                    master["all_terms"].extend(data["terms"])
                if "topics" in data:
                    master["all_topics"].extend(data["topics"])
            
            print(json.dumps(master, indent=2))
			PYEOF
        )
        
        if ! python -c "$merge_script" "${index_files[@]}" > "$master_index"; then
            die "Failed to generate master index"
        fi
        
        log_info "✓ Master index: $master_index"
    }

    # Generate quick reference
    generate_quick_reference() {
        local source_name=$1
        shift
        local summary_files=("$@")
        
        log_section "Generating Quick Reference"
        
        local quick_ref="$OUTPUT_DIR/${source_name}.quick-reference.md"
        
        log_info "Distilling ${#summary_files[@]} summaries"
        
        # Create quick reference header
        cut -c 9- > "$quick_ref" <<-EOF
        # ${source_name} - Quick Reference
        Generated: $(date +"%Y-%m-%d %H:%M:%S")
        
        This is a distilled quick reference guide combining key information from all sections.
        
        ---
        
		
EOF
        
        # Extract key sections from each summary
        for summary in "${summary_files[@]}"; do
            local section_name
            section_name=$(basename "$summary" | sed 's/.*\.digest\.\(.*\)\.md/\1/')
            
            {
                echo "## Section: $section_name"
                echo
            } >> "$quick_ref"
            
            # Extract overview and key concepts (simplified - could use AI for better distillation)
            if grep -q "^## Overview" "$summary"; then
                sed -n '/^## Overview/,/^## /p' "$summary" | head -n -1 >> "$quick_ref"
            fi
            
            if grep -q "^## Key Concepts" "$summary"; then
                sed -n '/^## Key Concepts/,/^## /p' "$summary" | head -n -1 >> "$quick_ref"
            fi
            
            {
                echo
                echo "---"
                echo
            } >> "$quick_ref"
        done
        
        log_info "✓ Quick reference: $quick_ref"
    }

}  # End outer scope braces

# Main pipeline
main() {
    set -ue
    local metadata_file=""
    local section_filter=""
    local skip_ai=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --metadata)
                metadata_file="$2"
                shift 2
                ;;
            --section)
                section_filter="$2"
                shift 2
                ;;
            --skip-ai)
                skip_ai=true
                shift
                ;;
            *)
                log_error "Unknown argument: $1"
                echo "Usage: $0 --metadata <file> [--section <name>] [--skip-ai]"
                exit 1
                ;;
        esac
    done
    
    if [[ -z "$metadata_file" ]]; then
        die "Missing required argument: --metadata. Usage: $0 --metadata <file> [--section <name>]"
    fi
    
    # Resolve metadata directory and set output directory relative to it
    local metadata_dir
    metadata_dir=$(cd "$(dirname "$metadata_file")" && pwd)
    
    # Override OUTPUT_DIR to be in the same directory as metadata file
    # unless explicitly set by user
    if [[ -z "${OUTPUT_DIR_OVERRIDE:-}" ]]; then
        OUTPUT_DIR="$metadata_dir"
    fi
    
    # Setup
    mkdir -p "$OUTPUT_DIR" "$LOG_DIR"
    
    log_section "Documentation Digest Pipeline"
    log "INFO" "Metadata: $metadata_file"
    log "INFO" "Output: $OUTPUT_DIR"
    log "INFO" "Log: $LOG_FILE"
    log "INFO" "AI Provider: $AI_PROVIDER ${AI_MODEL:+($AI_MODEL)}"
    
    # Check dependencies
    check_dependencies
    
    # Check AI connection before doing expensive work (skip if using cached)
    if [[ "$skip_ai" != "true" ]]; then
        check_ai_connection
    else
        log_warn "Skipping AI processing - using cached results"
    fi
    
    # Parse and validate metadata
    log_info "Parsing metadata: $metadata_file"
    local metadata_json
    metadata_json=$(parse_metadata "$metadata_file")
    
    local source_pdf source_name doc_version doc_title
    source_pdf=$(echo "$metadata_json" | jq -r '.document.source_pdf')
    doc_title=$(echo "$metadata_json" | jq -r '.document.title // "Document"')
    doc_version=$(echo "$metadata_json" | jq -r '.document.version // "unknown"')
    
    # Derive source name from PDF filename
    source_name=$(basename "$source_pdf" .pdf)
    
    log "INFO" "Document: $doc_title (v$doc_version)"
    log "INFO" "Source: $source_pdf"
    
    # Resolve source PDF path
    if [[ ! "$source_pdf" = /* ]]; then
        source_pdf="$WORKSPACE_ROOT/$source_pdf"
    fi
    
    # Validate PDF
    log_info "Validating source PDF: $source_pdf"
    local page_count
    page_count=$(validate_pdf "$source_pdf")
    
    # Validate sections
    log_section "Validating Sections"
    local valid_sections
    valid_sections=$(validate_sections "$metadata_json" "$page_count" "$section_filter")
    
    local section_count
    section_count=$(echo "$valid_sections" | jq 'length')
    log_info "Processing $section_count section(s)"
    
    # Process each section
    log_section "Processing Sections"
    
    local summary_files=()
    local index_files=()
    
    local i=0
    while [[ $i -lt $section_count ]]; do
        local section
        section=$(echo "$valid_sections" | jq -c ".[$i]")
        
        local name start_page end_page
        name=$(echo "$section" | jq -r '.name')
        start_page=$(echo "$section" | jq -r '.start_page')
        end_page=$(echo "$section" | jq -r '.end_page')
        
        echo
        log_info "[$((i+1))/$section_count] Section: $name (pages $start_page-$end_page)"
        
        # Output files
        local sliced_pdf="${OUTPUT_DIR}/${source_name}.${name}.pdf"
        local text_file="${OUTPUT_DIR}/${source_name}.${name}.txt"
        
        # Slice PDF
        if ! slice_pdf "$source_pdf" "$start_page" "$end_page" "$sliced_pdf"; then
            die "Failed to process section: $name"
        fi
        
        # Extract text
        if ! extract_text "$sliced_pdf" "$text_file"; then
            die "Failed to process section: $name"
        fi
        
        # Process with AI or use cached results
        local summary_file index_file
        if [[ "$skip_ai" == "true" ]]; then
            # Look for cached AI response JSON (not the final output files)
            local cached_response="$OUTPUT_DIR/${source_name}.ai-response.${name}.json"
            
            if [[ ! -f "$cached_response" ]]; then
                die "Cached AI response not found: $cached_response\n       Run without --skip-ai first to generate it."
            fi
            
            log_info "Using cached AI response: $cached_response"
            
            # Extract file paths from cached response (same as normal flow)
            summary_file=$(jq -r '.summary_file' "$cached_response")
            index_file=$(jq -r '.index_file' "$cached_response")
            
            # Verify the Python script actually created these files
            if [[ ! -f "$summary_file" ]]; then
                log_warn "Summary file missing: $summary_file (Python script may have failed)"
            fi
            if [[ ! -f "$index_file" ]]; then
                log_warn "Index file missing: $index_file (Python script may have failed)"
            fi
            
            log "INFO" "  Summary: $summary_file"
            log "INFO" "  Index: $index_file"
        else
            # Process with AI
            local ai_result
            if ! ai_result=$(process_with_ai "$text_file" "$section" "$source_name" "$doc_version"); then
                die "Failed to process section: $name"
            fi
            
            # Debug: save what we captured for forensics
            echo "$ai_result" > "$OUTPUT_DIR/DEBUG-captured-ai-result.txt"
            log "DEBUG" "Captured AI result saved to DEBUG-captured-ai-result.txt"
            
            # Collect output files (ai_result is the JSON line from process_with_ai)
            summary_file=$(echo "$ai_result" | jq -r '.summary_file')
            index_file=$(echo "$ai_result" | jq -r '.index_file')
        fi
        
        summary_files+=("$summary_file")
        index_files+=("$index_file")
        
        i=$((i+1))
    done
    
    # Generate consolidated artifacts
    if ! generate_master_index "$source_name" "${index_files[@]}"; then
        die "Failed to generate master index"
    fi
    
    if ! generate_quick_reference "$source_name" "${summary_files[@]}"; then
        die "Failed to generate quick reference"
    fi
    
    # Clean up forensics files from previous failures (success = clean slate)
    log_info "Cleaning up old forensics files..."
    local forensics_count
    forensics_count=$(find "$OUTPUT_DIR" -name "FAILED-*.txt" 2>/dev/null | wc -l)
    if [[ $forensics_count -gt 0 ]]; then
        find "$OUTPUT_DIR" -name "FAILED-*.txt" -delete
        log_info "  Removed $forensics_count old failure forensics files"
    else
        log_info "  No old forensics files to clean up"
    fi
    
    # Summary
    log_section "Pipeline Complete"
    log_info "Processed $section_count section(s)"
    log_info "Generated artifacts:"
    log_info "  - ${#summary_files[@]} summaries"
    log_info "  - ${#index_files[@]} indexes"
    log_info "  - 1 master index"
    log_info "  - 1 quick reference"
    log_info "Output directory: $OUTPUT_DIR"
    log_info "Log file: $LOG_FILE"
    
    echo
    echo -e "${GREEN}✓ Documentation digest complete!${NC}"
}

#  The "sourceMe" conditional allows the user to source the script into their current shell
#  to work with the individual helper functions, overwrite global vars, etc.
if [[ -z "${sourceMe:-}" ]]; then
    main "$@"
    builtin exit
fi
command true
