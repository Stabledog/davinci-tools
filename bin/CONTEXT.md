# bin/ — Script Guidelines

## Purpose
This directory contains executable scripts for workspace setup, automation, and tooling.

---

## Script Quality Requirements

### 1. Template and Pattern
All shell scripts should follow [SHELL_SCRIPT_TEMPLATE.sh](SHELL_SCRIPT_TEMPLATE.sh) structure:
- Use `set -ue` (strict mode: exit on error + unset variable)
- Include PS4 diagnostics and DEBUGSH support
- Use `die()` function for error messages (to stderr)
- Organize functions in "outer scope braces" block
- Support `sourceMe` pattern for interactive use

### 2. Linting and Quality Checks
All scripts **must** pass appropriate linting before commit:

- **Shell scripts** (`.sh`, `.bash`): `shellcheck`
- **Python scripts** (`.py`): `ruff check` and `ruff format`
- Fix all warnings unless explicitly documented as acceptable (use `#shellcheck disable=` comments sparingly)

### 3. Error Handling
Check potential error conditions **before** mutating state:

- Validate inputs and arguments
- Check file/directory existence before modifying
- Test for required permissions
- Verify command availability (`command -v`, `which`)
- Use `die "message"` for error reporting (see template)
- Provide meaningful error messages to stderr

### 4. Prerequisites and Dependencies
When encountering missing prerequisites:

**DO:**
- Detect the missing requirement early
- Print clear error message explaining what's missing
- Exit with non-zero status
- Suggest manual installation steps if helpful

**DO NOT:**
- Attempt just-in-time installation
- Download/install software without explicit user request
- Modify system configuration speculatively
- Assume package managers or tools are available

**Example:**
```bash
if ! command -v resolve &> /dev/null; then
    echo "Error: DaVinci Resolve not found."
    echo "Please install DaVinci Resolve before running this script."
    exit 1
fi
```

### 5. Scope Discipline
Scripts should do **exactly** what their name/purpose suggests:
- `setup-kb.sh` = set up knowledge base structure (reasonable scope)
- `setup-kb.sh` trying to install DaVinci Resolve = scope violation

---

## Script Execution Pattern
1. Parse arguments
2. Validate prerequisites (fail fast)
3. Check error conditions
4. Execute mutations
5. Report results

---

## Testing Before Commit
- Run linter on modified scripts
- Test with missing prerequisites to verify error handling
- Verify script doesn't execute mutations when validation fails
