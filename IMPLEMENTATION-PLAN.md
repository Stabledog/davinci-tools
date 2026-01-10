# IMPLEMENTATION-PLAN.md — Boundary Specification Implementation

## Status: Planning Phase
**Created:** 2026-01-10  
**Purpose:** Roadmap to restore digest toolchain functionality after automatic boundary detection removal

---

## Background

### What Changed
- Removed automatic section boundary detection (keyword density, TOC parsing)
- Existing `color-digest.sh` script is broken (expects boundaries that no longer exist)
- Scripts are misnamed (imply color-grading focus, but system is generic)
- No convenient way to specify boundaries currently

### What We're Building
**A generic documentation digest system** for extracting and processing sections from large PDFs.

- User-friendly metadata file system for declaring section boundaries
- Validation tooling to catch errors before expensive operations  
- Generic scripts that work with any PDF (technical manuals, textbooks, specifications)
- Clear path from "I want to extract pages X-Y" to "I have a digest"

**First use case:** DaVinci Resolve manual color grading section (test case, not the goal)

---

## Deliverables

### 1. Metadata Schema (✓ Complete)
- [BOUNDARY-SPEC.md](BOUNDARY-SPEC.md) - Canonical specification
- [TEMPLATE-doc-metadata.toml](TEMPLATE-doc-metadata.toml) - User starting point
- [projects__/legend_of_halle_/doc-metadata.toml](projects__/legend_of_halle_/doc-metadata.toml) - Working example

### 2. Metadata Loader (To Do)
**File:** `bin/metadata-loader.py`

**Purpose:** Parse and validate metadata files (TOML/JSON)

**Interface:**
```bash
# Output shell-evaluable variables
bin/metadata-loader.py --format shell-eval --metadata path/to/doc-metadata.toml --section color-grading

# Output:
# SOURCE_PDF="docs/DaVinci_Resolve_Manual.pdf"
# SECTION_NAME="color-grading"
# SECTION_TITLE="Color Grading"
# START_PAGE=1500
# END_PAGE=1850
# PRIORITY="high"

# Output JSON (all sections)
bin/metadata-loader.py --format json --metadata path/to/doc-metadata.toml

# Validate only (exit 0 if valid, non-zero with errors to stderr)
bin/metadata-loader.py --validate --metadata path/to/doc-metadata.toml
```

**Requirements:**
- Python 3.13+ (tomllib)
- JSON support (stdlib)
- Validate all schema rules from BOUNDARY-SPEC.md
- Resolve relative paths against workspace root
- Check PDF exists and is readable
- Validate page ranges against PDF (using `pdfinfo`)
- Clear error messages with line numbers (for TOML syntax errors)

### 3. Validation Script (To Do)
**File:** `bin/validate-metadata.py`

**Purpose:** User-facing pre-flight validation

**Interface:**
```bash
bin/validate-metadata.py projects__/legend_of_halle_/doc-metadata.toml
# Output: validation results, exit 0 if valid
```

**Requirements:**
- Wrapper around `metadata-loader.py --validate`
- Human-friendly output format
- Summary: "Valid: 2 sections in doc-metadata.toml"
- Per-section validation checks with ✓/✗ symbols

**Example output:**
```
Validating: projects__/legend_of_halle_/doc-metadata.toml

Document:
  ✓ source_pdf exists: docs/DaVinci_Resolve_Manual.pdf
  ✓ source_pdf readable (3842 pages, 45.2 MB)
  ✓ title: "DaVinci Resolve Manual"

Section: color-grading
  ✓ name is filesystem-safe: "color-grading"
  ✓ page range valid: 1500-1850 (350 pages)
  ✓ within bounds: 1850 <= 3842
  ✓ priority: high

Summary: Valid metadata with 1 section
```

### 4. Updated Scripts (To Do)

#### 4.1. Rename and refactor scripts
- `color-digest.sh` → `doc-digest.sh` (generic document processor)
- `color-tools-install.sh` → `doc-tools-install.sh` (generic tool installer)
- Delete `color-keywords.toml` (digest config now in metadata files)
- Update all internal references and documentation

#### 4.2. Update `doc-digest.sh` to load metadata
**Changes:**
```bash
# Command-line interface
--metadata PATH         Path to metadata file (required)
--section NAME          Section to process (required)
--list-sections         List available sections in metadata file
```

**Implementation:**
- Parse arguments with getopts
- Require both `--metadata` and `--section` (no defaults, no env vars)
- Call `metadata-loader.py --format shell-eval` early in script  
- `eval` the output to set internal variables (START_PAGE, END_PAGE, etc.)
- Proceed with existing slice/extract/digest logic
- Update all log messages and error handling

#### 4.3. Update `config-reader.py` (minimal changes)
- Already cleaned of detection code
- May need slight adjustments if digest config changes

### 5. Documentation Updates (To Do)

#### 5.1. Update `NEXT-STEPS.prompt.md`
- Reference BOUNDARY-SPEC.md for metadata schema
- Update pipeline stage 2 (slice manual) to show metadata usage
- Update examples to use `--metadata` flag

#### 5.2. Create `README.md` in workspace root
- Quick start guide
- "How to extract a section" walkthrough
- Link to BOUNDARY-SPEC.md for details

#### 5.3. Update `bin/CONTEXT.md`
- Note new metadata loader script
- Add validation script to script inventory

---

## Implementation Sequence

### Phase 0: Script Rename (Priority: High)
**Goal:** Fix misleading script names before building on them

**Tasks:**
1. Rename `color-digest.sh` → `doc-digest.sh`
2. Rename `color-tools-install.sh` → `doc-tools-install.sh`  
3. Delete `color-keywords.toml` (obsolete)
4. Update internal references in renamed scripts
5. Update documentation references

**Guide:** See [SCRIPT-RENAME.md](SCRIPT-RENAME.md) for detailed checklist

**Acceptance Criteria:**
- All scripts have generic names
- No references to old script names in code or docs
- Tool check still works: `bin/doc-tools-install.sh --check`

### Phase 1: Validation Foundation (Priority: High)
**Goal:** Users can validate metadata before running expensive operations

**Tasks:**
1. Implement `bin/metadata-loader.py`
   - TOML parsing with tomllib
   - JSON parsing with json module
   - Schema validation (all required fields, types correct)
   - Path resolution and existence checks
   - PDF page count validation via pdfinfo
   - Shell-eval and JSON output formats
2. Implement `bin/validate-metadata.py`
   - User-friendly wrapper
   - Pretty formatting with ✓/✗ symbols
   - Summary statistics
3. Test with `projects__/legend_of_halle_/doc-metadata.toml`
4. Document usage in BOUNDARY-SPEC.md

**Acceptance Criteria:**
- User can run `validate-metadata.py` and get clear pass/fail
- Invalid metadata produces actionable error messages
- Valid metadata shows page counts and confirmation

### Phase 2: Script Integration (Priority: High)
**Goal:** Restore digest generation functionality

**Tasks:**
1. Update `color-digest.sh`:
   - Add `--metadata` and `--section` flags (getopts)
   - Add `--list-sections` flag
   - Call `metadata-loader.py --format shell-eval`
   - Eval output to set START_PAGE, END_PAGE, etc.
   - Update log messages to show metadata source
2. Create symlink: `bin/doc-digest.sh` → `color-digest.sh` (or rename)
3. Test end-to-end with color grading example:
   ```bash
   bin/doc-digest.sh --metadata projects__/legend_of_halle_/doc-metadata.toml --section color-grading
   ```
4. Test --list-sections flag:
   ```bash
   bin/doc-digest.sh --list-sections --metadata projects__/legend_of_halle_/doc-metadata.toml
   ```

**Acceptance Criteria:**
- User can generate digest from metadata file with one command
- Clear error if metadata file or section not specified
- Log file shows metadata source, validated boundaries, and all decisions

### Phase 3: Generalization (Priority: Medium)
**Goal:** Support multiple documents and projects easily

**Tasks:**
1. Test with second project (create new project directory)
2. Document project setup workflow
3. Consider auto-discovery: scan `projects__/*/doc-metadata.toml`
4. Add batch mode: process all sections in metadata file

**Acceptance Criteria:**
- Two working project examples in repo
- Clear workflow documentation
- User can add new project in <10 minutes

### Phase 4: Quality of Life (Priority: Low)
**Goal:** Refinements and polish

**Possible enhancements:**
- `--dry-run` flag (validate, show what would be done, exit)
- Progress indicators for multi-section processing
- Metadata file generation helper (interactive prompts)
- Shell completion for section names
- CI/CD integration (validate all metadata files in repo)

---

## Testing Strategy

### Unit Tests
- `metadata-loader.py`:
  - Valid TOML parsing
  - Valid JSON parsing
  - Schema violation detection
  - Path resolution
  - Error message clarity

### Integration Tests
- End-to-end: metadata file → sliced PDF + text + digest
- Multiple sections in one metadata file
- Error handling: invalid metadata caught before PDF processing
- Missing required flags produce clear usage message

### Manual Tests
- User workflow: PDF inspection → metadata creation → validation → digest
- Error recovery: typo in page number, missing file, etc.
- Cross-platform: Windows (Git Bash), macOS, Linux

---

## Dependencies

### Existing Tools (already in repo)
- Python 3.13+ (tomllib)
- qpdf (PDF slicing)
- pdftotext (text extraction)
- pdfinfo (PDF metadata)

### New Dependencies
- None (use stdlib only for Python scripts)

---

## Risks and Mitigations

### Risk: User confusion about PDF page numbers vs document page numbers
**Mitigation:** 
- Clear documentation with screenshots
- Validation warnings if page numbers seem suspicious
- Examples in template file

### Risk: TOML syntax errors frustrate users
**Mitigation:**
- Template file with working example
- Clear error messages with line numbers
- Validation before any destructive operations

### Risk: Overlapping sections cause confusion
**Mitigation:**
- Document that overlaps are allowed (policy decision)
- Validation warnings (non-fatal) if overlaps detected
- User controls their own mental model

---

## Success Metrics

### Short-term (Phase 1-2 complete)
- User can extract a section in 3 commands:
  1. Copy template
  2. Edit page numbers
  3. Run digest script
- Zero manual failures due to page boundary errors
- All existing digest outputs reproducible with new system

### Long-term (Phase 3-4 complete)
- 5+ projects using metadata files
- No boundary-related issues reported
- Users prefer metadata approach over env vars (observed usage)

---

## Open Questions

1. **Should we support wildcards in section names?**
   - Example: `--section "color-*"` processes all sections starting with "color-"
   - **Decision:** Defer to Phase 4 (nice-to-have, not blocking)

2. **Should metadata files support includes/inheritance?**
   - Example: base metadata with common sections, per-project overrides
   - **Decision:** Defer indefinitely (YAGNI until proven needed)

3. **Should we validate section content (keyword spot-check)?**
   - Example: after slicing, grep for expected terms
   - **Decision:** No (false confidence risk, boundary correctness is user's responsibility)

4. **Should we support non-PDF sources?**
   - Example: web pages, EPUB, plain text
   - **Decision:** Out of scope (PDF focus aligns with current needs)

---

## Next Steps

**Immediate actions:**
1. Review this plan with user (confirm priorities, scope)
2. Implement Phase 1 (validation foundation)
3. Test Phase 1 with existing example metadata
4. Proceed to Phase 2 (script integration)

**Ready to implement:** Awaiting user confirmation to proceed with Phase 1.
