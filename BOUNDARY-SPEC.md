# BOUNDARY-SPEC.md — Document Boundary Specification

## Purpose
This document defines how users specify topic boundaries within canonical documentation (large PDFs) for digest generation.

**Scope:** Generic documentation processing system. Works with any large PDF (technical manuals, textbooks, specifications). The DaVinci Resolve manual is used as a first example/test case.

**Context:** Automatic boundary detection was removed (too unreliable across document versions). Users now explicitly declare sections via metadata files.

---

## Metadata File Format

### Location Pattern
```
projects__/<project-name>/doc-metadata.toml
```

**Examples:**
- `projects__/legend_of_halle_/doc-metadata.toml`
- `projects__/fusion_basics_/doc-metadata.toml`

**Alternative format:** `.json` instead of `.toml` (both supported)

### Schema (TOML)

```toml
[document]
source_pdf = "docs/DaVinci_Resolve_Manual.pdf"  # Absolute or workspace-relative path
title = "DaVinci Resolve Manual"                # Human-readable title
version = "19.1"                                 # Optional: product version
date = "2024-12"                                 # Optional: manual date
resolve_version = "19.1"                         # Optional: Resolve version (if applicable)

[[sections]]
name = "color-grading"                           # Filesystem-safe slug (output filename component)
title = "Color Grading"                          # Human-readable section title
description = "Color page workflow, nodes, curves, scopes, LUTs, color management"
start_page = 1500                                # PDF page number (1-indexed)
end_page = 1850                                  # PDF page number (inclusive)
priority = "high"                                # Optional: high|medium|low (guides processing order)

[[sections]]
name = "fusion"
title = "Fusion VFX"
description = "Fusion page compositing and visual effects"
start_page = 2000
end_page = 2300
priority = "medium"

# Add more sections as needed...
```

### Schema (JSON)

```json
{
  "document": {
    "source_pdf": "docs/DaVinci_Resolve_Manual.pdf",
    "title": "DaVinci Resolve Manual",
    "version": "19.1",
    "date": "2024-12",
    "resolve_version": "19.1"
  },
  "sections": [
    {
      "name": "color-grading",
      "title": "Color Grading",
      "description": "Color page workflow, nodes, curves, scopes, LUTs, color management",
      "start_page": 1500,
      "end_page": 1850,
      "priority": "high"
    },
    {
      "name": "fusion",
      "title": "Fusion VFX",
      "description": "Fusion page compositing and visual effects",
      "start_page": 2000,
      "end_page": 2300,
      "priority": "medium"
    }
  ]
}
```

---

## Validation Rules

### Required Fields
- `document.source_pdf` - Must exist and be readable
- `document.title` - String, non-empty
- `sections[].name` - String, filesystem-safe (no `/`, `\`, `:`, `*`, `?`, `"`, `<`, `>`, `|`)
- `sections[].title` - String, non-empty
- `sections[].start_page` - Positive integer, within PDF page bounds
- `sections[].end_page` - Positive integer, within PDF page bounds

### Constraints
- `start_page` ≤ `end_page` (each section)
- `end_page` ≤ total PDF page count
- `start_page` ≥ 1
- `name` must be unique within document (no duplicate section names)
- `name` must match pattern: `[a-z0-9_-]+` (lowercase, digits, hyphens, underscores only)

### Optional Fields
- `document.version` - String, free-form version identifier
- `document.date` - String, recommended format: `YYYY-MM` or `YYYY-MM-DD`
- `document.resolve_version` - String, DaVinci Resolve version (if applicable)
- `sections[].description` - String, aids AI context and user documentation
- `sections[].priority` - Enum: `"high"` | `"medium"` | `"low"` (default: medium)

### Policy Decisions
- **Overlapping page ranges:** Allowed (tool does not enforce exclusivity)
- **Gap between sections:** Allowed (sections need not be contiguous)
- **Out-of-order sections:** Allowed (sections need not be sorted by page number)

**Rationale:** Maximum flexibility for user's mental model. Some topics span multiple physical locations, some users want overlapping views.

---

## User Workflow

### Step 1: Locate Section Boundaries
User manually inspects PDF:
- Open PDF in viewer (Acrobat, Sumatra, etc.)
- Navigate to section start (note page number from viewer)
- Navigate to section end (note page number from viewer)
- **Critical:** Use PDF page numbers (typically bottom of page or viewer status bar)
  - NOT document page numbers (which may be roman numerals, restarted numbering, etc.)
  - If viewer shows "Page 1500 (1421)", use **1500** (the PDF page index)

### Step 2: Create Metadata File
- Copy template (from this document or `TEMPLATE-doc-metadata.toml`)
- Fill in `document.source_pdf` (relative to workspace root)
- Add one `[[sections]]` block per topic
- Fill in page boundaries from Step 1
- Save to `projects__/<project-name>/doc-metadata.toml`

### Step 3: Validate Metadata
```bash
# Proposed validation script (to be implemented)
bin/validate-metadata.py projects__/legend_of_halle_/doc-metadata.toml
```

### Step 4: Generate Digest
```bash
# Run digest generation (reads metadata, slices, generates)
bin/doc-digest.sh --metadata projects__/legend_of_halle_/doc-metadata.toml
```

---

## Output File Naming

Given metadata section with `name = "color-grading"` and `source_pdf = "docs/DaVinci_Resolve_Manual.pdf"`:

- **Sliced PDF:** `docs/DaVinci_Resolve_Manual.color-grading.pdf`
- **Extracted text:** `docs/DaVinci_Resolve_Manual.color-grading.txt`
- **Digest markdown:** `docs/DaVinci_Resolve_Manual.digest.color-grading.md`

**Pattern:**
```
<source-basename>.<section-name>.<extension>
```

**Rationale:** Clear provenance chain, easy to glob, sorts logically.

---

## Migration from Current State

### Current (broken) state:
- Old `color-digest.sh` script exists but is broken (boundary detection removed)
- `color-keywords.toml` has stale config (detection sections removed)
- Scripts are misnamed (imply color-grading-only, but system is generic)
- No metadata file support exists

### Migration tasks:

1. **Create template file:** `TEMPLATE-doc-metadata.toml` (✓ complete)
2. **Create spec document:** `BOUNDARY-SPEC.md` (✓ complete)
3. **Rename/refactor scripts:** (to do)
   - `color-digest.sh` → `doc-digest.sh` (generic document processor)
   - `color-tools-install.sh` → `doc-tools-install.sh` (generic tool dependencies)
   - `color-keywords.toml` → **DELETE** (digest config now in metadata files)
4. **Implement metadata loader:** `bin/metadata-loader.py` (parse TOML/JSON, validate schema)
5. **Implement validation script:** `bin/validate-metadata.py` (user-facing pre-flight checks)
6. **Update `doc-digest.sh`:** Accept `--metadata` flag, load boundaries from metadata file
7. **Document example:** Create `projects__/legend_of_halle_/doc-metadata.toml` (✓ complete)

---

## Design Rationale

### Why TOML?
- Human-readable, easy to edit
- Native Python 3.13+ support (`tomllib`)
- Natural array-of-tables syntax for sections
- Comments supported
- JSON as alternative for programmatic generation

### Why explicit page numbers?
- Automatic detection is unreliable (keyword density, TOC parsing, heuristics all fail)
- User observation is ground truth (AGENTS.md principle)
- PDFs vary: structure, fonts, layout, OCR quality
- Page numbers are deterministic, verifiable

### Why allow overlaps?
- Some topics cross-cut (e.g., "ACES workflow" spans color grading + output)
- Users understand their domain better than tools
- Storage is cheap; redundancy in service of clarity is acceptable

### Why metadata file per project?
- Each project has unique documentation needs and boundaries
- One project might extract "color grading" from Resolve manual
- Another project might extract "Python async" from language reference
- Metadata captures project-specific ground truth about canonical sources

---

## Open Questions / Future Enhancements

### Q: Should metadata include AI prompts per section?
Example:
```toml
[[sections]]
name = "color-grading"
ai_prompt = "Focus on practical workflows and common pitfalls"
```
**Status:** Deferred. Start simple, add if needed.

### Q: Support page ranges as arrays?
Example for non-contiguous sections:
```toml
[[sections]]
name = "fusion-advanced"
page_ranges = [[2000, 2100], [2500, 2600]]
```
**Status:** Deferred. Can implement as multiple sections with same name suffix.

### Q: Validate page content (keyword spot-check)?
Post-load validation: grep extracted text for expected terms.
**Status:** Deferred. False confidence risk (keyword presence ≠ correct boundary).

### Q: Support per-section output directories?
**Status:** Not needed. Flat structure in `docs/` is fine for now.

---

## Success Criteria

User can:
1. Open PDF, note page numbers
2. Create metadata file in 5 minutes
3. Run digest generation command
4. Get correct sliced PDF + text + markdown

Tool must:
1. Validate metadata before destructive operations
2. Produce clear error messages for invalid metadata
3. Log all decisions (which boundaries used, from where)
4. Be idempotent (re-run produces same output)

---

## See Also
- [NEXT-STEPS.prompt.md](NEXT-STEPS.prompt.md) - Full implementation roadmap
- [AGENTS.md](AGENTS.md) - Project philosophy and agent behavior
- [bin/CONTEXT.md](bin/CONTEXT.md) - Script quality standards
- [TEMPLATE-FAILURE.md](TEMPLATE-FAILURE.md) - Failure documentation template
