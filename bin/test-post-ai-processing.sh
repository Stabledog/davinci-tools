#!/bin/bash
# test-post-ai-processing.sh - Integration test for post-AI processing
# Tests the jq parsing and artifact generation without re-running expensive AI calls
#
# Usage: test-post-ai-processing.sh <project-dir>
#   Example: ./bin/test-post-ai-processing.sh projects__/legend_of_halle_

set -euo pipefail

scriptName="${scriptName:-"$(command readlink -f -- "$0")"}"
scriptDir="$(command dirname -- "${scriptName}")"
WORKSPACE_ROOT="$(cd "$scriptDir/.." && pwd)"

die() {
    echo "ERROR: $*" >&2
    exit 1
}

# Parse arguments
if [[ $# -lt 1 ]]; then
    die "Usage: $0 <project-dir>"
fi

PROJECT_DIR="$1"
if [[ ! -d "$PROJECT_DIR" ]]; then
    die "Project directory not found: $PROJECT_DIR"
fi

# Find generated files
echo "=== Integration Test: Post-AI Processing ==="
echo "Project dir: $PROJECT_DIR"
echo

# Look for generated digest and index files
DIGEST_FILES=($(find "$PROJECT_DIR" -name "*.digest.*.md" 2>/dev/null || true))
INDEX_FILES=($(find "$PROJECT_DIR" -name "*.index.*.json" 2>/dev/null || true))

if [[ ${#DIGEST_FILES[@]} -eq 0 ]]; then
    die "No digest files found in $PROJECT_DIR"
fi

if [[ ${#INDEX_FILES[@]} -eq 0 ]]; then
    die "No index files found in $PROJECT_DIR"
fi

echo "Found files:"
echo "  Digests: ${#DIGEST_FILES[@]}"
for f in "${DIGEST_FILES[@]}"; do
    echo "    - $(basename "$f")"
done
echo "  Indexes: ${#INDEX_FILES[@]}"
for f in "${INDEX_FILES[@]}"; do
    echo "    - $(basename "$f")"
done
echo

# Extract source name from first digest file
FIRST_DIGEST="$(basename "${DIGEST_FILES[0]}")"
SOURCE_NAME="${FIRST_DIGEST%.digest.*}"

echo "Source name: $SOURCE_NAME"
echo

# Test 1: Simulate jq parsing of Python output
echo "=== Test 1: JSON parsing simulation ==="
TEST_JSON='{"success": true, "summary_file": "'${DIGEST_FILES[0]}'", "index_file": "'${INDEX_FILES[0]}'", "char_count": 955185, "line_count": 15870}'

echo "Test JSON:"
echo "$TEST_JSON"
echo

if echo "$TEST_JSON" | jq . > /dev/null 2>&1; then
    echo "✓ JSON is valid"
else
    echo "✗ JSON is INVALID"
    echo "Trying to parse:"
    echo "$TEST_JSON" | jq . || true
    die "JSON parsing failed"
fi

# Try extracting fields like the shell script does
echo "Extracting fields..."
SUMMARY_FILE=$(echo "$TEST_JSON" | jq -r '.summary_file')
INDEX_FILE=$(echo "$TEST_JSON" | jq -r '.index_file')
CHAR_COUNT=$(echo "$TEST_JSON" | jq -r '.char_count')

echo "  summary_file: $SUMMARY_FILE"
echo "  index_file: $INDEX_FILE"
echo "  char_count: $CHAR_COUNT"
echo

# Test 2: Generate master index
echo "=== Test 2: Generate master index ==="

# Source the functions from doc-digest.sh by setting sourceMe variable
export sourceMe=1
source "$scriptDir/doc-digest.sh"

OUTPUT_DIR="$PROJECT_DIR"
if ! generate_master_index "$SOURCE_NAME" "${INDEX_FILES[@]}"; then
    die "Master index generation failed"
fi
echo "✓ Master index generated"
echo

# Test 3: Generate quick reference
echo "=== Test 3: Generate quick reference ==="
if ! generate_quick_reference "$SOURCE_NAME" "${DIGEST_FILES[@]}"; then
    die "Quick reference generation failed"
fi
echo "✓ Quick reference generated"
echo

echo "=== All tests passed! ==="
echo "Generated files in: $PROJECT_DIR"
ls -lh "$PROJECT_DIR"/*.master-index.json "$PROJECT_DIR"/*.quick-reference.md 2>/dev/null || true
