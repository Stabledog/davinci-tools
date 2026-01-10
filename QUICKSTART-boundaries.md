# Quick Start: Document Boundary Specification

## What This Is
A system for telling the digest generator which parts of a large PDF to extract and process.

---

## 5-Minute Workflow

### 1. Find Your Section in the PDF
Open the PDF in any viewer and note the page numbers:

```
Example: DaVinci Resolve Manual, Color Grading section
- Start: Page 1500 (look at viewer's page counter)
- End: Page 1850
```

**Important:** Use the PDF's internal page number (what the viewer shows), not the document's printed page number.

### 2. Create Metadata File
Copy the template:

```bash
cp TEMPLATE-doc-metadata.toml projects__/my-project/doc-metadata.toml
```

Edit the file:

```toml
[document]
source_pdf = "docs/DaVinci_Resolve_Manual.pdf"
title = "DaVinci Resolve Manual"

[[sections]]
name = "color-grading"              # Lowercase, hyphens/underscores only
title = "Color Grading"             # Human-readable
start_page = 1500                   # From your PDF viewer
end_page = 1850                     # From your PDF viewer
```

### 3. Validate (Coming Soon)
```bash
bin/validate-metadata.py projects__/my-project/doc-metadata.toml
```

### 4. Generate Digest (Coming Soon)
```bash
bin/doc-digest.sh --metadata projects__/my-project/doc-metadata.toml --section color-grading
```

---

## Current Status

**Scripts are currently broken** (automatic boundary detection removed, metadata support not yet implemented).

Once implementation is complete (Phase 1-2), you'll use the metadata file approach shown above.

---

## Output Files

Given section name `color-grading` and source `DaVinci_Resolve_Manual.pdf`:

- `docs/DaVinci_Resolve_Manual.color-grading.pdf` - Sliced PDF (pages 1500-1850)
- `docs/DaVinci_Resolve_Manual.color-grading.txt` - Extracted text
- `docs/DaVinci_Resolve_Manual.digest.color-grading.md` - AI-generated digest

---

## Troubleshooting

### "Metadata file required"
- Specify metadata file with `--metadata` flag
- Ensure file exists and is valid TOML/JSON

### Page numbers don't match content
- Check that you're using PDF page numbers, not document page numbers
- Some PDFs have multiple numbering schemes (roman numerals, restarted numbering)
- Use the number shown in your PDF viewer's status bar or page indicator

### Section seems cut off
- Expand your `end_page` by 10-20 pages and re-run
- Manual boundaries are an iterative process

---

## See Also

- [BOUNDARY-SPEC.md](BOUNDARY-SPEC.md) - Complete specification
- [IMPLEMENTATION-PLAN.md](IMPLEMENTATION-PLAN.md) - Development roadmap
- [TEMPLATE-doc-metadata.toml](TEMPLATE-doc-metadata.toml) - Metadata file template
