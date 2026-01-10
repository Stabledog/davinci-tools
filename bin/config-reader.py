#!/usr/bin/env python
"""config-reader.py - TOML configuration reader for color-digest toolchain

Reads color-keywords.toml and outputs in formats consumable by bash scripts.
Requires Python 3.13+ for built-in tomllib support.

Usage:
    config-reader.py --format json [--config PATH]
    config-reader.py --format shell-eval [--config PATH]
    config-reader.py --version

Formats:
    json        - Output full config as JSON
    shell-eval  - Output as KEY=VALUE pairs for 'eval' in bash

Note: --list-keywords option was removed (automatic detection disabled).
"""

import sys
import json
import argparse
from pathlib import Path

# Require Python 3.13+
if sys.version_info < (3, 13):
    print(f"ERROR: Python 3.13 or greater required (found {sys.version_info.major}.{sys.version_info.minor})", file=sys.stderr)
    sys.exit(1)

import tomllib


def load_config(config_path: Path) -> dict:
    """Load and parse TOML config file."""
    if not config_path.exists():
        print(f"ERROR: Config file not found: {config_path}", file=sys.stderr)
        sys.exit(1)
    
    try:
        with open(config_path, "rb") as f:
            return tomllib.load(f)
    except tomllib.TOMLDecodeError as e:
        print(f"ERROR: Invalid TOML syntax in {config_path}: {e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"ERROR: Failed to read config: {e}", file=sys.stderr)
        sys.exit(1)


# ==============================================================================
# AUTOMATIC DETECTION SUPPORT - REMOVED
# ==============================================================================
# The flatten_keywords() function was removed as part of strategy shift.
# It previously extracted all keywords from [keywords] section for density analysis.
# ==============================================================================


def format_json(config: dict) -> str:
    """Format config as JSON."""
    return json.dumps(config, indent=2)


def format_shell_eval(config: dict) -> str:
    """Format config for bash 'eval' consumption.
    
    Outputs key configuration values as shell variable assignments.
    Note: Detection-related variables (MIN_KEYWORD_DENSITY, WINDOW_SIZE, 
    KEYWORDS_COUNT) were removed - automatic detection is disabled.
    """
    lines = []
    
    if "glossary" in config and "terms" in config["glossary"]:
        lines.append(f"GLOSSARY_TERMS_COUNT={len(config['glossary']['terms'])}")
    
    if "digest" in config and "sections" in config["digest"]:
        lines.append(f"DIGEST_SECTIONS_COUNT={len(config['digest']['sections'])}")
    
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(
        description="TOML configuration reader for color-digest toolchain",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__
    )
    parser.add_argument(
        "--config",
        type=Path,
        help="Path to TOML config file (default: bin/color-keywords.toml relative to script)"
    )
    parser.add_argument(
        "--format",
        choices=["json", "shell-eval"],
        help="Output format"
    )
    # NOTE: --list-keywords removed (automatic detection disabled)
    parser.add_argument(
        "--version",
        action="store_true",
        help="Show Python version and exit"
    )
    
    args = parser.parse_args()
    
    if args.version:
        print(f"Python {sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}")
        return 0
    
    # Determine config path
    if args.config:
        config_path = args.config.resolve()
    else:
        # Default: bin/color-keywords.toml relative to this script
        script_dir = Path(__file__).parent
        config_path = script_dir / "color-keywords.toml"
    
    # Load config
    config = load_config(config_path)
    
    # Output in requested format
    if args.format == "json":
        print(format_json(config))
    elif args.format == "shell-eval":
        print(format_shell_eval(config))
    else:
        parser.print_help()
        return 1
    
    return 0


if __name__ == "__main__":
    sys.exit(main())
