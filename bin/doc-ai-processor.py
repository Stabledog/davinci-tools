#!/usr/bin/env python3
"""
doc-ai-processor.py - AI-powered documentation processing
Generates summaries, indexes, and diagrams from extracted text.
"""

import argparse
import json
import os
import sys
from pathlib import Path
from typing import Dict, List, Any, Optional
import re
from datetime import datetime

# AI provider support
try:
    import anthropic
    ANTHROPIC_AVAILABLE = True
except ImportError:
    ANTHROPIC_AVAILABLE = False

try:
    import openai
    OPENAI_AVAILABLE = True
except ImportError:
    OPENAI_AVAILABLE = False


class AIProcessor:
    """Handles AI-powered document processing."""
    
    def __init__(self, provider: str = "anthropic", model: Optional[str] = None, 
                 max_tokens: int = 4096, temperature: float = 0.0):
        self.provider = provider.lower()
        self.model = model
        self.max_tokens = max_tokens
        self.temperature = temperature
        self.client = None
        
        self._setup_client()
    
    def _setup_client(self):
        """Initialize AI client based on provider."""
        if self.provider == "anthropic":
            if not ANTHROPIC_AVAILABLE:
                raise RuntimeError("anthropic package not installed. Run: pip install anthropic")
            
            api_key = os.getenv("ANTHROPIC_API_KEY")
            if not api_key:
                raise RuntimeError("ANTHROPIC_API_KEY environment variable not set")
            
            self.client = anthropic.Anthropic(api_key=api_key)
            if not self.model:
                self.model = "claude-sonnet-4-5-20250929"
        
        elif self.provider == "openai":
            if not OPENAI_AVAILABLE:
                raise RuntimeError("openai package not installed. Run: pip install openai")
            
            api_key = os.getenv("OPENAI_API_KEY")
            if not api_key:
                raise RuntimeError("OPENAI_API_KEY environment variable not set")
            
            self.client = openai.OpenAI(api_key=api_key)
            if not self.model:
                self.model = "gpt-4-turbo-preview"
        
        else:
            raise ValueError(f"Unsupported AI provider: {self.provider}")
    
    def call_ai(self, prompt: str, system_prompt: Optional[str] = None) -> str:
        """Make AI API call and return response."""
        try:
            if self.provider == "anthropic":
                kwargs = {
                    "model": self.model,
                    "max_tokens": self.max_tokens,
                    "temperature": self.temperature,
                    "messages": [{"role": "user", "content": prompt}]
                }
                if system_prompt:
                    kwargs["system"] = system_prompt
                
                response = self.client.messages.create(**kwargs)
                return response.content[0].text
            
            elif self.provider == "openai":
                messages = []
                if system_prompt:
                    messages.append({"role": "system", "content": system_prompt})
                messages.append({"role": "user", "content": prompt})
                
                response = self.client.chat.completions.create(
                    model=self.model,
                    messages=messages,
                    max_tokens=self.max_tokens,
                    temperature=self.temperature
                )
                return response.choices[0].message.content
        
        except Exception as e:
            raise RuntimeError(f"AI API call failed: {e}")
    
    def generate_summary(self, text: str, section_info: Dict[str, Any]) -> str:
        """Generate structured summary with Mermaid diagrams."""
        system_prompt = """You are a technical documentation expert. Your task is to create a comprehensive, structured summary optimized for LLM consumption.

Focus on:
- Key concepts, workflows, and features
- Glossary terms with precise definitions
- Version-specific behaviors and caveats
- Common pitfalls and troubleshooting
- Hierarchical topic organization
- Mermaid diagrams for visual concepts (workflows, hierarchies, state machines)

Output format: Clean Markdown with semantic structure. Use headers, lists, tables, and code blocks appropriately."""

        section_name = section_info.get("name", "unknown")
        section_title = section_info.get("title", "Documentation Section")
        doc_version = section_info.get("doc_version", "unknown")
        description = section_info.get("description", "")
        
        prompt = f"""# Documentation Summary Task

**Section:** {section_title} ({section_name})
**Document Version:** {doc_version}
**Description:** {description}

Process the following documentation excerpt and create a comprehensive structured summary.

## Requirements

1. **Overview** - Brief introduction to the section's purpose and scope
2. **Key Concepts** - Main ideas, organized hierarchically
3. **Glossary** - Technical terms with definitions
4. **Workflows** - Step-by-step procedures (with Mermaid flowcharts where applicable)
5. **Features & Tools** - Detailed breakdown of capabilities
6. **Version-Specific Notes** - Behaviors tied to specific versions (flag with confidence level)
7. **Common Issues** - Pitfalls, errors, troubleshooting steps
8. **Cross-References** - Related topics mentioned in the text

## Mermaid Diagram Guidelines
- Use flowcharts for workflows
- Use graph diagrams for hierarchies/relationships
- Use sequence diagrams for interactions
- Embed directly in Markdown with ```mermaid code blocks

## Source Text

{text[:50000]}  

{"... [text truncated for length] ..." if len(text) > 50000 else ""}

Generate the structured summary now."""

        response = self.call_ai(prompt, system_prompt)
        
        # Sanity check for truncated/failed responses
        if len(response) < 100:
            section_name = section_info.get("name", "unknown")
            output_dir = Path(os.getenv("OUTPUT_DIR", "."))
            forensics_file = output_dir / f"FAILED-summary-response-{section_name}-{datetime.now().strftime('%Y%m%d-%H%M%S')}.txt"
            try:
                with open(forensics_file, "w", encoding="utf-8") as f:
                    f.write("=== AI Response (Suspiciously Short Summary) ===\n")
                    f.write(f"Section: {section_info.get('title', 'Unknown')}\n")
                    f.write(f"Timestamp: {datetime.now().isoformat()}\n")
                    f.write(f"Response length: {len(response)} chars (expected thousands)\n")
                    f.write("\n=== Full Response ===\n")
                    f.write(response)
                print(f"DEBUG: Suspiciously short summary saved to: {forensics_file}", file=sys.stderr)
            except Exception as write_err:
                print(f"DEBUG: Failed to save forensics file: {write_err}", file=sys.stderr)
        
        return response
    
    def generate_index(self, text: str, section_info: Dict[str, Any]) -> Dict[str, Any]:
        """Generate LLM-optimized index as JSON."""
        system_prompt = """You are creating a searchable index for LLM-based documentation retrieval. 

Output must be valid JSON with:
- concepts: list of key concepts with descriptions
- terms: technical terms with context
- topics: hierarchical topic clusters
- patterns: user intent patterns (how-to, what-is, troubleshooting)
- cross_refs: related concepts mentioned

Be precise and comprehensive."""

        section_name = section_info.get("name", "unknown")
        section_title = section_info.get("title", "Documentation Section")
        
        prompt = f"""# Index Generation Task

**Section:** {section_title} ({section_name})

Create a comprehensive searchable index from the documentation text below.

## Required JSON Structure

{{
  "section": "{section_name}",
  "title": "{section_title}",
  "concepts": [
    {{"name": "concept_name", "description": "brief explanation", "relevance": "high|medium|low"}}
  ],
  "terms": [
    {{"term": "technical_term", "definition": "meaning", "context": "where it's used"}}
  ],
  "topics": [
    {{"category": "main_topic", "subtopics": ["sub1", "sub2"], "keywords": ["kw1", "kw2"]}}
  ],
  "patterns": {{
    "how_to": ["task descriptions"],
    "what_is": ["concept queries"],
    "troubleshooting": ["problem patterns"]
  }},
  "cross_refs": [
    {{"from": "concept_a", "to": "concept_b", "relationship": "uses|requires|relates"}}
  ]
}}

## Source Text

{text[:50000]}

{"... [text truncated for length] ..." if len(text) > 50000 else ""}

Generate the index as valid JSON now. Output ONLY the JSON, no additional text."""

        response = self.call_ai(prompt, system_prompt)
        
        # Extract JSON from response (handle markdown code blocks)
        json_match = re.search(r'```(?:json)?\s*(\{.*?\})\s*```', response, re.DOTALL)
        if json_match:
            response = json_match.group(1)
        
        try:
            return json.loads(response)
        except json.JSONDecodeError as e:
            # Fallback: try to find JSON object in response
            json_start = response.find('{')
            json_end = response.rfind('}') + 1
            if json_start >= 0 and json_end > json_start:
                try:
                    return json.loads(response[json_start:json_end])
                except:
                    pass
            
            # Save full response for forensics
            section_name = section_info.get("name", "unknown")
            output_dir = Path(os.getenv("OUTPUT_DIR", "."))
            forensics_file = output_dir / f"FAILED-index-response-{section_name}-{datetime.now().strftime('%Y%m%d-%H%M%S')}.txt"
            try:
                with open(forensics_file, "w", encoding="utf-8") as f:
                    f.write("=== AI Response (Failed JSON Parse) ===\n")
                    f.write(f"Section: {section_info.get('title', 'Unknown')}\n")
                    f.write(f"Timestamp: {datetime.now().isoformat()}\n")
                    f.write(f"Response length: {len(response)} chars\n")
                    f.write(f"Parse error: {e}\n")
                    f.write("\n=== Full Response ===\n")
                    f.write(response)
                print(f"DEBUG: Full response saved to: {forensics_file}", file=sys.stderr)
            except Exception as write_err:
                print(f"DEBUG: Failed to save forensics file: {write_err}", file=sys.stderr)
            
            # Debug output for troubleshooting
            print(f"DEBUG: Failed to parse JSON from AI response", file=sys.stderr)
            print(f"DEBUG: Response length: {len(response)} chars", file=sys.stderr)
            print(f"DEBUG: First 500 chars: {response[:500]}", file=sys.stderr)
            print(f"DEBUG: Last 500 chars: {response[-500:]}", file=sys.stderr)
            
            raise RuntimeError(f"Failed to parse AI-generated JSON: {e}")


def load_metadata(metadata_path: Path) -> Dict[str, Any]:
    """Load metadata from TOML or JSON file."""
    try:
        if metadata_path.suffix == ".toml":
            try:
                import tomli
            except ImportError:
                try:
                    import tomllib as tomli
                except ImportError:
                    raise RuntimeError("TOML support requires tomli package. Run: pip install tomli")
            
            with open(metadata_path, "rb") as f:
                return tomli.load(f)
        
        elif metadata_path.suffix == ".json":
            with open(metadata_path, "r", encoding="utf-8") as f:
                return json.load(f)
        
        else:
            raise ValueError(f"Unsupported metadata format: {metadata_path.suffix}")
    
    except Exception as e:
        raise RuntimeError(f"Failed to load metadata: {e}")


def process_section(text_file: Path, section_info: Dict[str, Any], 
                    output_dir: Path, ai_processor: AIProcessor) -> Dict[str, Path]:
    """Process a single section: generate summary and index."""
    
    print(f"Processing section: {section_info['name']}", file=sys.stderr)
    
    # Read extracted text with fallback encoding handling
    try:
        with open(text_file, "r", encoding="utf-8") as f:
            text = f.read()
    except UnicodeDecodeError:
        # Fallback to latin-1 which accepts all byte values
        print("  Warning: UTF-8 decode failed, using latin-1 encoding", file=sys.stderr)
        with open(text_file, "r", encoding="latin-1") as f:
            text = f.read()
    
    if not text.strip():
        raise RuntimeError(f"Extracted text is empty: {text_file}")
    
    char_count = len(text)
    line_count = text.count('\n') + 1
    print(f"  Text: {char_count:,} chars, {line_count:,} lines", file=sys.stderr)
    
    # Generate summary
    print("  Generating summary with AI...", file=sys.stderr)
    summary = ai_processor.generate_summary(text, section_info)
    
    # Generate index
    print("  Generating index with AI...", file=sys.stderr)
    index = ai_processor.generate_index(text, section_info)
    
    # Write outputs
    source_name = section_info.get("source_name", "document")
    section_name = section_info["name"]
    
    summary_file = output_dir / f"{source_name}.digest.{section_name}.md"
    index_file = output_dir / f"{source_name}.index.{section_name}.json"
    
    with open(summary_file, "w", encoding="utf-8") as f:
        f.write(summary)
    print(f"  [OK] Summary: {summary_file}", file=sys.stderr)
    
    with open(index_file, "w", encoding="utf-8") as f:
        json.dump(index, f, indent=2)
    print(f"  [OK] Index: {index_file}", file=sys.stderr)
    
    return {
        "summary": summary_file,
        "index": index_file,
        "char_count": char_count,
        "line_count": line_count
    }


def main():
    parser = argparse.ArgumentParser(
        description="AI-powered documentation processing: summaries, indexes, diagrams"
    )
    parser.add_argument("--test-connection", action="store_true",
                        help="Test API connection and exit")
    parser.add_argument("--list-models", action="store_true",
                        help="List available models and exit")
    parser.add_argument("--text-file", type=Path,
                        help="Path to extracted text file")
    parser.add_argument("--section-name",
                        help="Section name from metadata")
    parser.add_argument("--section-title",
                        help="Section title")
    parser.add_argument("--section-description", default="",
                        help="Section description")
    parser.add_argument("--doc-version", default="unknown",
                        help="Document version")
    parser.add_argument("--source-name",
                        help="Source document name (for output filenames)")
    parser.add_argument("--output-dir", type=Path,
                        help="Output directory for generated files")
    parser.add_argument("--provider", default=os.getenv("AI_PROVIDER", "anthropic"),
                        choices=["anthropic", "openai"],
                        help="AI provider (default: anthropic)")
    parser.add_argument("--model", default=os.getenv("AI_MODEL"),
                        help="AI model name (optional, uses provider default)")
    parser.add_argument("--max-tokens", type=int, 
                        default=int(os.getenv("AI_MAX_TOKENS", "16384")),
                        help="Max tokens for AI responses")
    
    args = parser.parse_args()
    
    # Setup AI processor
    try:
        ai_processor = AIProcessor(
            provider=args.provider,
            model=args.model,
            max_tokens=args.max_tokens
        )
    except Exception as e:
        print(f"ERROR: Failed to setup AI processor: {e}", file=sys.stderr)
        sys.exit(1)
    
    # Handle connection test mode
    if args.test_connection:
        try:
            print(f"Testing {args.provider} API connection...")
            response = ai_processor.call_ai("Respond with only: OK")
            if "OK" in response.upper():
                print(f"[OK] Connection successful (model: {ai_processor.model})")
                sys.exit(0)
            else:
                print(f"WARNING: Unexpected response: {response}", file=sys.stderr)
                sys.exit(1)
        except Exception as e:
            error_msg = str(e)
            print(f"ERROR: Connection test failed: {error_msg}", file=sys.stderr)
            
            # Provide helpful hints for common errors
            if "404" in error_msg or "not_found" in error_msg.lower():
                print(f"\nHINT: Model '{ai_processor.model}' not found.", file=sys.stderr)
                print(f"Try running: python {sys.argv[0]} --list-models --provider {args.provider}", file=sys.stderr)
            elif "401" in error_msg or "authentication" in error_msg.lower():
                print(f"\nHINT: API key invalid or not set.", file=sys.stderr)
                if args.provider == "anthropic":
                    print("Set environment variable: ANTHROPIC_API_KEY", file=sys.stderr)
                elif args.provider == "openai":
                    print("Set environment variable: OPENAI_API_KEY", file=sys.stderr)
            
            sys.exit(1)
    
    # Handle list models mode
    if args.list_models:
        try:
            print(f"Querying {args.provider} for available models...")
            
            if args.provider == "anthropic":
                models = ai_processor.client.models.list()
                print("\nAvailable Claude models:")
                for model in models.data:
                    print(f"  - {model.id}")
            
            elif args.provider == "openai":
                models = ai_processor.client.models.list()
                print("\nAvailable GPT models:")
                for model in models.data:
                    if "gpt" in model.id.lower():
                        print(f"  - {model.id}")
            
            sys.exit(0)
        
        except Exception as e:
            print(f"ERROR: Failed to query models: {e}", file=sys.stderr)
            sys.exit(1)
    
    # Validate inputs for normal processing mode
    if not args.text_file:
        print("ERROR: --text-file is required", file=sys.stderr)
        sys.exit(1)
    if not args.section_name:
        print("ERROR: --section-name is required", file=sys.stderr)
        sys.exit(1)
    if not args.section_title:
        print("ERROR: --section-title is required", file=sys.stderr)
        sys.exit(1)
    if not args.source_name:
        print("ERROR: --source-name is required", file=sys.stderr)
        sys.exit(1)
    if not args.output_dir:
        print("ERROR: --output-dir is required", file=sys.stderr)
        sys.exit(1)
    
    # Validate inputs
    if not args.text_file.exists():
        print(f"ERROR: Text file not found: {args.text_file}", file=sys.stderr)
        sys.exit(1)
    
    args.output_dir.mkdir(parents=True, exist_ok=True)
    
    # Setup AI processor
    try:
        ai_processor = AIProcessor(
            provider=args.provider,
            model=args.model,
            max_tokens=args.max_tokens
        )
    except Exception as e:
        print(f"ERROR: Failed to setup AI processor: {e}", file=sys.stderr)
        sys.exit(1)
    
    # Build section info
    section_info = {
        "name": args.section_name,
        "title": args.section_title,
        "description": args.section_description,
        "doc_version": args.doc_version,
        "source_name": args.source_name
    }
    
    # Process section
    try:
        result = process_section(args.text_file, section_info, args.output_dir, ai_processor)
        
        # Output results as JSON for shell script consumption
        # Convert Windows paths to forward slashes for JSON/bash compatibility
        output = {
            "success": True,
            "summary_file": result["summary"].as_posix(),
            "index_file": result["index"].as_posix(),
            "char_count": result["char_count"],
            "line_count": result["line_count"]
        }
        print(json.dumps(output))
    
    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
