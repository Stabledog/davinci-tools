#!/bin/bash
# Reproduce the jq parse error

cd /c/Projects/davinci-tools

# Mimic exactly what the shell script does
ai_result=$(python bin/doc-ai-processor.py \
    --text-file projects__/legend_of_halle_/page-limit-tests/Davinci_Resolve_Manual.color-grading.txt \
    --section-name color-grading \
    --section-title "Color Grading" \
    --source-name "Davinci_Resolve_Manual" \
    --doc-version "v20" \
    --output-dir projects__/legend_of_halle_/page-limit-tests \
    --provider anthropic \
    --max-tokens 16384)

echo "=== Full ai_result ($(echo "$ai_result" | wc -l) lines) ==="
echo "$ai_result"
echo
echo "=== Last line ==="
echo "$ai_result" | tail -n1
echo
echo "=== Trying jq parse ==="
echo "$ai_result" | tail -n1 | jq .
