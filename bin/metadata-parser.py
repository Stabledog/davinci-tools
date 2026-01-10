#!/usr/bin/env python3
"""
metadata-parser.py - Parse and validate documentation metadata files

Accepts TOML or JSON metadata files and outputs validated JSON to stdout.

Usage:
    metadata-parser.py <metadata-file>

Exit codes:
    0 - Success
    1 - Validation or parsing error
"""

import sys
import json
from pathlib import Path


def main():
    if len(sys.argv) != 2:
        print("Usage: metadata-parser.py <metadata-file>", file=sys.stderr)
        sys.exit(1)
    
    metadata_file = Path(sys.argv[1])
    
    if not metadata_file.exists():
        print(f"ERROR: File not found: {metadata_file}", file=sys.stderr)
        sys.exit(1)
    
    try:
        if metadata_file.suffix == ".toml":
            try:
                import tomli
            except ImportError:
                try:
                    import tomllib as tomli
                except ImportError:
                    print("ERROR: TOML support requires tomli. Run: pip install tomli", file=sys.stderr)
                    sys.exit(1)
            
            with open(metadata_file, "rb") as f:
                data = tomli.load(f)
        
        elif metadata_file.suffix == ".json":
            with open(metadata_file, "r", encoding="utf-8") as f:
                data = json.load(f)
        
        else:
            print(f"ERROR: Unsupported format: {metadata_file.suffix}", file=sys.stderr)
            sys.exit(1)
        
        # Validate required fields
        if "document" not in data:
            print("ERROR: Missing 'document' section in metadata", file=sys.stderr)
            sys.exit(1)
        
        if "source_pdf" not in data["document"]:
            print("ERROR: Missing 'source_pdf' in document section", file=sys.stderr)
            sys.exit(1)
        
        if "sections" not in data or not data["sections"]:
            print("ERROR: No sections defined in metadata", file=sys.stderr)
            sys.exit(1)
        
        # Output as JSON
        print(json.dumps(data, indent=2))
    
    except Exception as e:
        print(f"ERROR: Failed to parse metadata: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
