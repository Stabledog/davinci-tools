#!/usr/bin/env python
"""config-reader.py - TOML configuration reader for color-digest toolchain

Reads color-keywords.toml and outputs in formats consumable by bash scripts.
Requires Python 3.13+ for built-in tomllib support.

Usage:
    config-reader.py --format json [--config PATH]
    config-reader.py --format shell-eval [--config PATH]
    config-reader.py --list-keywords [--config PATH]
    config-reader.py --version

Formats:
    json        - Output full config as JSON
    shell-eval  - Output as KEY=VALUE pairs for 'eval' in bash
    list        - Output flattened keyword list, one per line
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


def flatten_keywords(config: dict) -> list[str]:
    """Extract all keywords from all categories into a flat list."""
    keywords = []
    if "keywords" in config:
        for category, terms in config["keywords"].items():
            if isinstance(terms, list):
                keywords.extend(terms)
    return sorted(set(keywords))  # Deduplicate and sort


def format_json(config: dict) -> str:
    """Format config as JSON."""
    return json.dumps(config, indent=2)


def format_shell_eval(config: dict) -> str:
    """Format config for bash 'eval' consumption.
    
    Outputs key configuration values as shell variable assignments:
    - MIN_KEYWORD_DENSITY=5
    - WINDOW_SIZE=10
    - KEYWORDS_COUNT=42
    """
    lines = []
    
    if "detection" in config:
        det = config["detection"]
        if "min_keyword_density" in det:
            lines.append(f"MIN_KEYWORD_DENSITY={det['min_keyword_density']}")
        if "window_size" in det:
            lines.append(f"WINDOW_SIZE={det['window_size']}")
    
    keywords = flatten_keywords(config)
    lines.append(f"KEYWORDS_COUNT={len(keywords)}")
    
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
    parser.add_argument(
        "--list-keywords",
        action="store_true",
        help="Output flattened keyword list, one per line"
    )
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
    if args.list_keywords:
        keywords = flatten_keywords(config)
        for keyword in keywords:
            print(keyword)
    elif args.format == "json":
        print(format_json(config))
    elif args.format == "shell-eval":
        print(format_shell_eval(config))
    else:
        parser.print_help()
        return 1
    
    return 0


if __name__ == "__main__":
    sys.exit(main())
