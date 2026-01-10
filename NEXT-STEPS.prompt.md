# Implementation Prompt: Documentation Digest Toolchain (Windows, Bash)

Use this prompt verbatim to guide an implementation session in a clean context. Goal: produce a Bash-based, Windows-friendly tool in `bin/` that processes **any large PDF documentation** using user-provided metadata to slice PDFs into sections, then uses AI to summarize and index the content for LLM consumption.

## Scope and Constraints
- **Generic system:** Works with any PDF (technical manuals, textbooks, specifications, reference docs)
- **First example:** DaVinci Resolve manual color grading section (test case, not exclusive focus)
- Environment: Windows, Git Bash shell. Prefer Scoop-installed CLI tools; no WSL required.
- Repo norms: follow `AGENTS.md` (version-specific, user observations are ground truth), respect `KNOWN_LIES.md` and use `TEMPLATE-FAILURE.md` for logging incorrect or missing guidance.
- **Strategy shift:** User provides metadata file specifying section boundaries; automatic section detection is deferred indefinitely (proven unreliable).
- Primary output: AI-generated summaries and indexes optimized for LLM consultants.
## Required Tools (install via Scoop)
- poppler (`pdftotext`, `pdfinfo`)
- qpdf (preferred for slicing); mutool (mupdf-tools) is an acceptable fallback
- coreutils (for standard UNIX utils, typically present in Git Bash)
- Python 3.13 or greater (for metadata parsing and AI orchestration)
- jq (for JSON manipulation)

Capture tool versions in the run log (e.g., `pdftotext -v`, `qpdf --version`, `python --version`).

**Tool Installation Pattern:**
- `bin/doc-tools-install.sh` supports `--check` mode (returns 0 if all tools present, non-zero otherwise)
- Main script (`bin/doc-digest.sh`) runs install script with `--check` at startup
- On check failure: print clear advisory message, exit non-zero, instruct user to run install script manually
- No just-in-time installation; humans control when dependencies are installed

## Metadata File Schema
User provides a metadata file describing how to slice the documentation. 

**Format:** TOML (`.toml`) or JSON (`.json`)

**Location:** `projects__/<project-name>/doc-metadata.toml` (or `.json`)

**Schema:**
```toml
[document]
source_pdf = "docs/DaVinci_Resolve_Manual.pdf"  # Absolute or workspace-relative path
title = "DaVinci Resolve Manual"
version = "19.1"  # Optional: product version, if known
date = "2024-12"  # Optional: manual date, if known

[[sections]]
name = "color-grading"
title = "Color Grading"
description = "Color page workflow, nodes, curves, scopes, LUTs, and color management"
start_page = 1500  # PDF page number (1-indexed)
end_page = 1850    # PDF page number (inclusive)
priority = "high"  # Optional: "high" | "medium" | "low" - guides AI processing order

[[sections]]
name = "fusion"
title = "Fusion VFX"
description = "Fusion page compositing and visual effects"
start_page = 2000
end_page = 2300
priority = "medium"

# Add more sections as needed
```

**Validation rules:**
- `source_pdf` must exist and be readable
- `start_page` and `end_page` must be valid PDF page numbers (within document bounds)
- `end_page` must be ≥ `start_page`
- `name` must be filesystem-safe (used in output filenames)
- Section page ranges may overlap (tool does not enforce exclusivity)

## Configuration
- **Metadata file:** Specified via `--metadata` flag (required)
- **Section:** Specified via `--section` flag (required)
- **AI provider:** Configurable (OpenAI, Anthropic, local models). Default: use available provider in environment.
- **Environment variables for AI config:**
  - `AI_PROVIDER` - AI service to use (openai|anthropic|local)
  - `AI_MODEL` - specific model name (e.g., gpt-4, claude-3-5-sonnet)
  - `AI_MAX_TOKENS` - max tokens for AI responses
  - `OUTPUT_DIR` - base directory for outputs (default: `docs/`)
  - `LOG_DIR` - directory for run logs (default: `logs/`)

## Pipeline Stages (automate end-to-end)

### 1) **Validate inputs**
   - Load and parse metadata file (TOML or JSON)
   - Validate schema: required fields present, types correct
   - Confirm source PDF exists and is readable
   - Get PDF info: page count, creation/mod dates, file size
   - Validate all section page ranges against PDF page count
   - Record manual metadata (version, date from PDF properties or metadata file)

### 2) **Slice the manual**
   - For each section in metadata:
     - Use qpdf: `qpdf --pages source.pdf START-END -- output.pdf`
     - Output naming: `docs/<source-name>.<section-name>.pdf`
       - Example: `docs/DaVinci_Resolve_Manual.color-grading.pdf`
   - If qpdf unavailable: fail with clear error (should have been caught by install check)
   - Record slice operations and output paths in run log

### 3) **Extract text**
   - For each sliced PDF:
     - `pdftotext -layout <sliced-pdf> <text-output>`
     - Output naming: `docs/<source-name>.<section-name>.txt`
       - Example: `docs/DaVinci_Resolve_Manual.color-grading.txt`
   - Verify text extraction produced non-empty output
   - Record character/line counts for each extracted section

### 4) **AI-powered summarization and indexing**
   This is the core value-add. For each section, use AI to:

   **A. Generate structured summary**
   - Identify key concepts, workflows, and features
   - Extract glossary terms with definitions
   - Note version-specific features or caveats
   - Highlight common pitfalls or troubleshooting steps
   - Create hierarchical outline of topics covered
   - Output format: Markdown with semantic structure

   **B. Create LLM-optimized index**
   - Generate searchable concept map
   - Extract technical terms and their contexts
   - Build cross-references between related concepts
   - Identify user intent patterns ("how to...", "what is...", "troubleshooting...")
   - Tag content by topic clusters
   - Output format: JSON or YAML for programmatic access

   **C. Generate Mermaid diagrams** (where applicable)
   - Identify visual concepts (workflows, hierarchies, state machines)
   - Generate mermaid diagram definitions
   - Embed diagrams in summary markdown
   - Prefer: flowcharts for workflows, graphs for hierarchies, sequence diagrams for operations

   **AI Prompt Strategy:**
   - Use structured prompts with clear roles and output format requirements
   - Provide document version/date context to AI
   - Request AI to note confidence level for version-specific claims
   - Ask AI to flag ambiguous or unclear source material
   - Use multi-stage processing: 1) extract structure, 2) summarize content, 3) generate diagrams

   **Output files per section:**
   - `docs/<source-name>.digest.<section-name>.md` - Human-readable summary with diagrams
   - `docs/<source-name>.index.<section-name>.json` - Machine-readable index for LLM retrieval

### 5) **Generate consolidated artifacts**
   After processing all sections:

   **A. Master index**
   - Combine all section indexes into single searchable structure
   - Output: `docs/<source-name>.master-index.json`

   **B. Cross-section references**
   - Identify concepts mentioned across multiple sections
   - Build navigation graph
   - Output: `docs/<source-name>.cross-references.json`

   **C. Quick reference guide**
   - Distill summaries into compact cheat sheet
   - Focus on high-frequency lookup patterns
   - Output: `docs/<source-name>.quick-reference.md`

### 6) **Logging and reproducibility**
   - **Format:** Unix-style text logs: `YYYY-MM-DD HH:MM:SS [category] [severity] message`
   - **Location:** `logs/doc-digest-run-YYYYMMDD-HHMMSS.log` (create `logs/` directory if missing)
   - **Content:** 
     - Metadata file used (checksum or hash for versioning)
     - Source PDF metadata (version/date, page count, file size)
     - Tool versions
     - AI provider/model used
     - Section processing order and timing
     - Character/token counts for AI requests
     - Output files generated with sizes
     - Any errors, warnings, or AI-flagged ambiguities

## Acceptance Criteria
- Runs under Git Bash on Windows with Scoop-installed deps; fails fast with clear errors if deps/manual/metadata missing.
- Processes all sections defined in metadata file in one run.
- Generates per-section summaries, indexes, and diagrams.
- Produces consolidated master index and cross-references.
- Summaries are structured, concise, and LLM-friendly.
- Diagrams are valid Mermaid syntax.
- All outputs are deterministic given same inputs (except AI non-determinism, which should be minimal with temperature=0).
- Run log captures full provenance for reproducibility.

## File/Path Conventions
- `bin/doc-digest.sh` (main entrypoint)
- `bin/doc-tools-install.sh` (tool installation script with `--check` mode)
- `bin/doc-ai-processor.py` (Python helper for AI orchestration)
- `projects__/<project-name>/doc-metadata.toml` (user-provided metadata)
- `docs/<source-name>.<section-name>.pdf` (sliced PDF sections)
- `docs/<source-name>.<section-name>.txt` (extracted text)
- `docs/<source-name>.digest.<section-name>.md` (AI-generated summary with diagrams)
- `docs/<source-name>.index.<section-name>.json` (AI-generated index)
- `docs/<source-name>.master-index.json` (consolidated index)
- `docs/<source-name>.cross-references.json` (cross-section links)
- `docs/<source-name>.quick-reference.md` (distilled cheat sheet)
- `logs/doc-digest-run-YYYYMMDD-HHMMSS.log` (Unix-style text log)

## Example: DaVinci Resolve Color Grading
Given this metadata file at `projects__/legend_of_halle_/doc-metadata.toml`:
```toml
[document]
source_pdf = "docs/DaVinci_Resolve_Manual.pdf"
title = "DaVinci Resolve Manual"
version = "19.1"

[[sections]]
name = "color-grading"
title = "Color Grading"
description = "Color page workflow and tools"
start_page = 1500
end_page = 1850
priority = "high"
```

Running `bin/doc-digest.sh --metadata projects__/legend_of_halle_/doc-metadata.toml` produces:
- `docs/DaVinci_Resolve_Manual.color-grading.pdf`
- `docs/DaVinci_Resolve_Manual.color-grading.txt`
- `docs/DaVinci_Resolve_Manual.digest.color-grading.md` (AI summary with Mermaid diagrams)
- `docs/DaVinci_Resolve_Manual.index.color-grading.json` (AI-generated index)
- `docs/DaVinci_Resolve_Manual.master-index.json` (since only one section)
- `docs/DaVinci_Resolve_Manual.quick-reference.md`
- `logs/doc-digest-run-YYYYMMDD-HHMMSS.log`

## Testing Checklist (for the implementer)
- Create minimal metadata file with one section
- Run script; verify all artifacts generated
- Check that sliced PDF contains expected content
- Verify text extraction is readable
- Review AI-generated summary for accuracy and structure
- Validate Mermaid diagrams render correctly
- Confirm index JSON is well-formed and contains expected entries
- Check run log captures all operations and metadata
- Test error handling: invalid metadata, missing PDF, out-of-range pages
- Test with multiple sections: verify consolidated outputs

## Notes for Future Extensions
- **Image extraction and analysis:** AI-powered diagram extraction from PDF images (OCR + vision models)
- **Automatic boundary detection:** Restore keyword-based section detection as optional mode when metadata incomplete
- **Multi-document support:** Process multiple PDFs in parallel with shared index
- **Interactive query mode:** CLI tool that uses generated indexes to answer user questions
- **Incremental updates:** Detect changed sections and reprocess only deltas
- **Quality metrics:** AI self-assessment of summary quality and coverage
- **Export formats:** HTML, EPUB, or other formats for digest output
