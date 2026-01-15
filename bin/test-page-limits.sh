#!/bin/bash
# test-page-limits.sh - Find the page limit for successful AI processing
# Iteratively doubles page count from 10 pages until failure
#
# Usage: test-page-limits.sh <metadata-file> <section-name> <start-page> <max-end-page>
#   Example: ./bin/test-page-limits.sh projects__/legend_of_halle_/doc-metadata.toml color-grading 2952 3414

set -euo pipefail

scriptName="${scriptName:-"$(command readlink -f -- "$0")"}"
scriptDir="$(command dirname -- "${scriptName}")"
WORKSPACE_ROOT="$(cd "$scriptDir/.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

die() {
    echo -e "${RED}ERROR: $*${NC}" >&2
    exit 1
}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_section() {
    echo
    echo -e "${BLUE}========== $* ==========${NC}"
    echo
}

# Parse arguments
if [[ $# -lt 4 ]]; then
    die "Usage: $0 <metadata-file> <section-name> <start-page> <max-end-page>"
fi

METADATA_FILE="$1"
SECTION_NAME="$2"
START_PAGE="$3"
MAX_END_PAGE="$4"

if [[ ! -f "$METADATA_FILE" ]]; then
    die "Metadata file not found: $METADATA_FILE"
fi

METADATA_DIR="$(cd "$(dirname "$METADATA_FILE")" && pwd)"
RESULTS_DIR="$METADATA_DIR/page-limit-tests"
mkdir -p "$RESULTS_DIR"

# Create temporary metadata file template
TEMP_METADATA_TEMPLATE="$RESULTS_DIR/test-metadata-template.toml"

# Extract metadata header (everything before first [[sections]])
sed '/^\[\[sections\]\]/,$d' "$METADATA_FILE" > "$TEMP_METADATA_TEMPLATE"

log_section "Page Limit Testing"
log_info "Metadata: $METADATA_FILE"
log_info "Section: $SECTION_NAME"
log_info "Start page: $START_PAGE"
log_info "Max end page: $MAX_END_PAGE"
log_info "Results dir: $RESULTS_DIR"
echo

# Test parameters
PAGE_COUNT=10
LAST_SUCCESS_PAGES=0
TOTAL_PAGES=$((MAX_END_PAGE - START_PAGE + 1))

log_info "Total pages to test: $TOTAL_PAGES"
echo

# Results tracking
RESULTS_FILE="$RESULTS_DIR/test-results.txt"
echo "Page Limit Test Results - $(date)" > "$RESULTS_FILE"
echo "Section: $SECTION_NAME (pages $START_PAGE-$MAX_END_PAGE)" >> "$RESULTS_FILE"
echo "========================================" >> "$RESULTS_FILE"
echo >> "$RESULTS_FILE"

while [[ $PAGE_COUNT -le $TOTAL_PAGES ]]; do
    CURRENT_END_PAGE=$((START_PAGE + PAGE_COUNT - 1))
    
    if [[ $CURRENT_END_PAGE -gt $MAX_END_PAGE ]]; then
        CURRENT_END_PAGE=$MAX_END_PAGE
        PAGE_COUNT=$((MAX_END_PAGE - START_PAGE + 1))
    fi
    
    log_section "Test: $PAGE_COUNT pages ($START_PAGE-$CURRENT_END_PAGE)"
    
    # Create temporary metadata for this test
    TEST_METADATA="$RESULTS_DIR/test-metadata-${PAGE_COUNT}pages.toml"
    cp "$TEMP_METADATA_TEMPLATE" "$TEST_METADATA"
    
    cat >> "$TEST_METADATA" <<EOF

[[sections]]
name = "$SECTION_NAME"
title = "Test Section"
description = "Testing with $PAGE_COUNT pages"
start_page = $START_PAGE
end_page = $CURRENT_END_PAGE
priority = "high"
EOF
    
    # Run pipeline with timestamped log
    TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
    TEST_LOG="$RESULTS_DIR/test-${PAGE_COUNT}pages-${TIMESTAMP}.log"
    
    log_info "Running pipeline..."
    log_info "Log: $TEST_LOG"
    
    if "$scriptDir/doc-digest.sh" --metadata "$TEST_METADATA" > "$TEST_LOG" 2>&1; then
        log_info "${GREEN}✓ SUCCESS${NC} - $PAGE_COUNT pages processed"
        echo "✓ $PAGE_COUNT pages: SUCCESS" >> "$RESULTS_FILE"
        LAST_SUCCESS_PAGES=$PAGE_COUNT
        
        # Check if we've reached the max
        if [[ $CURRENT_END_PAGE -eq $MAX_END_PAGE ]]; then
            log_section "Test Complete"
            log_info "Successfully processed all $TOTAL_PAGES pages!"
            echo >> "$RESULTS_FILE"
            echo "Result: All $TOTAL_PAGES pages processed successfully" >> "$RESULTS_FILE"
            break
        fi
        
        # Double for next iteration
        PAGE_COUNT=$((PAGE_COUNT * 2))
    else
        log_warn "${RED}✗ FAILED${NC} - $PAGE_COUNT pages"
        echo "✗ $PAGE_COUNT pages: FAILED" >> "$RESULTS_FILE"
        
        # Check the log for error type
        if grep -q "token" "$TEST_LOG" || grep -q "length" "$TEST_LOG"; then
            ERROR_TYPE="Token/Length limit"
        elif grep -q "timeout" "$TEST_LOG" || grep -q "Connection error" "$TEST_LOG"; then
            ERROR_TYPE="Timeout/Connection"
        elif grep -q "decode" "$TEST_LOG" || grep -q "encoding" "$TEST_LOG"; then
            ERROR_TYPE="Encoding issue"
        elif grep -q "jq" "$TEST_LOG" || grep -q "JSON" "$TEST_LOG"; then
            ERROR_TYPE="JSON parsing"
        else
            ERROR_TYPE="Unknown"
        fi
        
        echo "  Error type: $ERROR_TYPE" >> "$RESULTS_FILE"
        echo "  See log: $TEST_LOG" >> "$RESULTS_FILE"
        
        log_section "Test Complete"
        log_info "Last successful: $LAST_SUCCESS_PAGES pages"
        log_info "Failed at: $PAGE_COUNT pages"
        log_info "Error type: $ERROR_TYPE"
        echo >> "$RESULTS_FILE"
        echo "Result: Limit found between $LAST_SUCCESS_PAGES and $PAGE_COUNT pages" >> "$RESULTS_FILE"
        echo "Error type: $ERROR_TYPE" >> "$RESULTS_FILE"
        break
    fi
    
    echo
done

# Summary
log_section "Summary"
cat "$RESULTS_FILE"
echo
log_info "Full results: $RESULTS_FILE"
log_info "Test logs: $RESULTS_DIR/test-*.log"

# Clean up temp files
rm -f "$TEMP_METADATA_TEMPLATE"

echo
if [[ $LAST_SUCCESS_PAGES -eq $TOTAL_PAGES ]]; then
    log_info "${GREEN}Success!${NC} All $TOTAL_PAGES pages can be processed"
    exit 0
else
    log_warn "${YELLOW}Limit found:${NC} Maximum $LAST_SUCCESS_PAGES pages can be processed reliably"
    exit 0
fi
