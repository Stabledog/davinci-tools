# Implementation Prompt: Color-Grading Digest Toolchain (Windows, Bash)

Use this prompt verbatim to guide an implementation session in a clean context. Goal: produce a Bash-based, Windows-friendly tool in `bin/` that automatically slices the DaVinci Resolve manual to the Color section, extracts text-only, and generates a digest stub with page refs and mermaid placeholders. No images exported; reference images by page number.

## Scope and Constraints
- Environment: Windows, Git Bash shell. Prefer Scoop-installed CLI tools; no WSL required.
- Repo norms: follow `AGENTS.md` (version-specific, user observations are ground truth), respect `KNOWN_LIES.md` and use `TEMPLATE-FAILURE.md` for logging incorrect or missing guidance. Don’t invent Resolve features; note Resolve version/date from the manual.
- Manual location: `docs/DaVinci_Resolve_Manual.pdf` (symlink to `C:/Program Files/Blackmagic Design/DaVinci Resolve/Documents/DaVinci Resolve.pdf`).
- Outputs are text-only plus page references. Keep visuals as mermaid placeholders and page numbers.

## Required Tools (install via Scoop)
- poppler (`pdftotext`, `pdfinfo`, `pdfimages` if needed later)
- qpdf (preferred for slicing); mutool (mupdf-tools) is an acceptable fallback
- ripgrep (`rg`) for keyword scanning
- coreutils (for standard UNIX utils, typically present in Git Bash)
- Python 3.13 or greater (for TOML config parsing)

Capture tool versions in the run log (e.g., `pdftotext -v`, `qpdf --version`, `rg --version`, `python --version`).

**Tool Installation Pattern:**
- `bin/color-tools-install.sh` supports `--check` mode (returns 0 if all tools present, non-zero otherwise)
- Main script (`color-digest.sh`) runs install script with `--check` at startup
- On check failure: print clear advisory message, exit non-zero, instruct user to run install script manually
- No just-in-time installation; humans control when dependencies are installed

## Configuration
- **Format:** TOML (`bin/color-keywords.toml`)
- **Parser:** Python 3.13+ required; use `bin/config-reader.py` helper for TOML operations
- **Default keyword list:** `Color Page`, `Color`, `Grading`, `Node`, `Nodes`, `LUT`, `Power Window`, `Qualifier`, `Scopes`, `Waveform`, `Parade`, `Vectorscope`, `HDR`, `ACES`, `DaVinci Color Management`, `DCM`
- **Overrideable via environment variables:**
  - Manual path
  - Output paths
  - Keyword config file path
  - Detection thresholds (minimum keyword hit density, sliding window size, etc.)
- **Detection thresholds:** Define all numeric constants in script header section for easy tuning; values are experimental and subject to trial-and-error refinement

## Pipeline Stages (automate end-to-end)
1) **Validate inputs**
   - Confirm `docs/DaVinci_Resolve_Manual.pdf` exists (follow symlink).
   - Record manual file size and `pdfinfo` summary (page count, creation/mod dates).

2) **Outline and keyword detection**
   - Extract outline/bookmarks (prefer `qpdf --show-object=trailer --json` or `mutool show -e outline`).
   - **Bookmark extraction failure = fatal error; fail loudly, no fallback attempts.**
   - Run targeted text extraction on sampled ranges to map printed vs PDF page numbers if possible.
   - Use `pdftotext -f N -l M` + `rg` with keyword list to find candidate start/end for the Color section.
   - Heuristic: choose the first strong hit near a bookmark titled like "Color" (or similar) as start; end at the next top-level bookmark after Color, or where keyword density drops below threshold over a sliding window.
   - **Page numbering:** Use PDF page numbers (zero-indexed or one-indexed as tool reports); note printed page numbers only if trivially derivable from TOC.
   - **Keyword density issues:** TBD; if detection confidence is low, document loudly in logs and proceed (trial and error will guide future refinements).
   - Emit a detection report (markdown) listing: chosen start/end pages (PDF numbering), matched bookmarks, keyword hit counts by page.

3) **Slice the manual**
   - Use qpdf: `qpdf --pages source.pdf START-END -- output.pdf` to create `docs/DaVinci_Resolve_Manual.color-grading.pdf`.
   - If qpdf unavailable: fail with clear error (should have been caught by install check).

4) **Extract text (no images)**
   - `pdftotext -layout docs/DaVinci_Resolve_Manual.color-grading.pdf docs/DaVinci_Resolve_Manual.color-grading.txt`.
   - Keep note: images are referenced by page; no export.

5) **Generate digest stub** → `docs/DaVinci_Resolve_Manual.digest.color-grading.md`
   - Include: intro, Color page layout/workflow, primary/secondary tools, nodes, curves/advanced tools, scopes, LUTs, color management/ACES, HDR notes, practical workflows/troubleshooting, glossary, and mermaid diagram placeholders.
   - For each section: 1–2 sentence placeholder summary + page refs from the sliced PDF (use PDF page numbers; printed page numbers only if easily derivable).
   - Glossary: terms (Node, Primary, Secondary, Qualifier, Power Window, Tracker, LUT, ACES, HDR/PQ/HLG, Color Warper, Gallery, CDL) with page refs.
   - **Mermaid placeholders:** Commented sections marking where semantic diagrams should go (e.g., node graph, color pipeline, scopes decision helper, LUT placement). Format as `<!-- TODO: Generate mermaid diagram ... See pages X-Y -->`. These are for future tooling; automatic diagram generation requires semantic understanding beyond text extraction (2nd-pass tool).

6) **Logging and reproducibility**
   - **Format:** Unix-style text logs: `YYYY-MM-DD HH:MM:SS [category] [severity] message`
   - **Location:** `logs/color-digest-run-TIMESTAMP.log` (create `logs/` directory if missing)
   - **Content:** Manual metadata (version/date, page count), tool versions, keyword config file used, detected page bounds, command arguments executed, outputs produced
   - Note any uncertainties (e.g., ambiguous boundaries, low keyword density, detection confidence issues)

## Acceptance Criteria
- Runs under Git Bash on Windows with Scoop-installed deps; fails fast with clear errors if deps/manual missing.
- Produces all artifacts on one run (slice PDF, text export, digest stub, run log).
- Digest stub contains page references and mermaid placeholders; no images embedded.
- Keyword list is external/configurable; reruns are deterministic given same manual and config.

## File/Path Conventions
- `bin/color-digest.sh` (main entrypoint)
- `bin/color-tools-install.sh` (tool installation script with `--check` mode)
- `bin/config-reader.py` (Python helper for TOML parsing; requires Python 3.13+)
- `bin/color-keywords.toml` (keyword configuration in TOML format)
- `docs/DaVinci_Resolve_Manual.color-grading.pdf` (sliced PDF, Color section only)
- `docs/DaVinci_Resolve_Manual.color-grading.txt` (extracted text from sliced PDF)
- `docs/DaVinci_Resolve_Manual.digest.color-grading.md` (digest stub with placeholders and page refs; note uppercase 'V' in DaVinci)
- `logs/color-digest-run-YYYYMMDD-HHMMSS.log` (Unix-style text log)

## Testing Checklist (for the implementer)
- Run the script once; verify artifacts exist and page ranges are plausible.
- Spot-check that the detected start/end pages include the Color page intro and exclude non-Color chapters.
- Confirm digest stub has headings, placeholders, and page refs filled.
- Verify run log records tool versions and chosen ranges.

## Notes for Future Extensions
- Optional image extraction/OCR can be added later; keep hooks in the script but disabled by default.
- When manual versions change, rerun with the same script and compare run logs to spot boundary shifts.
