# Script Rename Plan

## Problem
Current scripts are misnamed, implying the entire system is for color grading when it's actually a generic document processing system.

## Renamings

### Scripts to Rename
| Current Name | New Name | Purpose |
|--------------|----------|---------|
| `color-digest.sh` | `doc-digest.sh` | Generic document section processor |
| `color-tools-install.sh` | `doc-tools-install.sh` | Generic tool dependency installer |

### Files to Delete
| File | Reason |
|------|--------|
| `color-keywords.toml` | Obsolete config (automatic detection removed, digest config now in metadata files) |

### Files to Keep (Already Generic)
- `config-reader.py` - Generic TOML/JSON reader
- `metadata-loader.py` - (to be created) Generic metadata file parser
- `validate-metadata.py` - (to be created) Generic validation script

## Migration Checklist

### Phase 1: Rename Files
```bash
cd bin/

# Rename scripts
git mv color-digest.sh doc-digest.sh
git mv color-tools-install.sh doc-tools-install.sh

# Delete obsolete config
git rm color-keywords.toml
```

### Phase 2: Update Internal References

**In `doc-digest.sh`:**
- Change `INSTALL_SCRIPT` default from `color-tools-install.sh` to `doc-tools-install.sh`
- Change `CONFIG_FILE` references (or remove if obsolete)
- Update all log messages:
  - "color-digest-run" → "doc-digest-run"
  - "color grading" references → generic terminology
- Update output file naming conventions if needed

**In `doc-tools-install.sh`:**
- Update script description comments
- No functional changes needed (already generic tools)

**In other files:**
- `bin/CONTEXT.md` - Update script examples
- `logs/.gitignore` - Update patterns if needed

### Phase 3: Update Documentation
Files to update:
- `IMPLEMENTATION-PLAN.md` - (already updated)
- `BOUNDARY-SPEC.md` - (already updated)
- `QUICKSTART-boundaries.md` - Update command examples
- `NEXT-STEPS.prompt.md` - Update script names

### Phase 4: Test
```bash
# Test tool check
bin/doc-tools-install.sh --check

# Test metadata validation (once implemented)
bin/validate-metadata.py projects__/legend_of_halle_/doc-metadata.toml

# Test digest generation (once metadata support implemented)
bin/doc-digest.sh --metadata projects__/legend_of_halle_/doc-metadata.toml --section color-grading
```

## Notes

### Why Not Keep Symlinks?
- No "backward compatibility" needed (scripts are already broken)
- Clean break is clearer than legacy cruft
- Simpler to understand and maintain

### Color Grading as Example
Color grading remains an important **example use case**, documented in:
- Example metadata: `projects__/legend_of_halle_/doc-metadata.toml`
- Test outputs: `docs/DaVinci_Resolve_Manual.color-grading.*`

### Future Script Additions
All new scripts should use generic naming:
- ✓ `doc-digest.sh`, `doc-tools-install.sh`
- ✗ `resolve-helper.sh`, `color-analyzer.sh`

If domain-specific helpers are needed, namespace them clearly:
- ✓ `resolve/color-helper.sh` (in subdirectory)
- ✓ `davinci/fusion-helper.sh`
