# bin/ — Script Guidelines

## Purpose
This directory contains executable scripts for workspace setup, automation, and tooling.

---

## Critical: Output Discipline in Shell Scripts

### The Stdout Contamination Problem
Shell scripts that capture function output with `result=$(function)` are vulnerable to stdout contamination. When functions write user messages to stdout (instead of stderr or log files), those messages get captured along with data, causing parse failures.

**The Three Output Streams:**
1. **stdout** - Data for capture/piping: `result=$(function)`
2. **stderr** - User messages, progress, errors: `echo "message" >&2`
3. **Log files** - Persistent records: `echo "log" >> "$LOGFILE"`

**Common Mistake:**
```bash
# BAD: tee writes to BOTH log file AND stdout
log() { echo "$*" | tee -a "$LOGFILE"; }

# When function output is captured:
result=$(my_function)  # Captures log output + data = CONTAMINATED!
```

**Correct Pattern:**
```bash
# GOOD: Separate data output from logging
log() { echo "$*" >> "$LOGFILE"; }  # Only to file
msg() { echo "$*" >&2; }             # Only to stderr

my_function() {
    log "Processing..."    # To file only
    msg "Status: working"  # User sees on stderr
    echo "clean_data"      # ONLY this to stdout
}

result=$(my_function)  # result="clean_data" (uncontaminated)
```

**Rules:**
- Functions whose output is captured MUST NOT use `tee` or write messages to stdout
- All user-facing messages go to stderr or log files
- Test captured output: `result=$(func); echo "$result" | jq .` should parse cleanly
- Colored output helpers (`log_info`, `log_warn`) must NOT be used inside captured functions

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
