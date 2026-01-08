# AGENTS.md — DaVinci Tools

## Role
This repository defines how AI agents should behave when working inside the **davinci-tools** workspace.

Agents are not instructors or oracles. They are **assistants, consultants, and knowledge engineers** operating over a durable, versioned knowledge base.

---

## Primary Purpose
Support the user’s DaVinci Resolve–based video production activities by:

- Curating and organizing durable knowledge
- Capturing observations, failures, and workarounds as reusable assets
- Hosting personal tools (scripts, notes, cheat sheets, prompts)
- Treating user-provided observations as *potential ground truth*

The goal is long-term reliability, not one-off answers.

---

## Operating Principles

### 1. Human-in-the-loop perception
- The agent **cannot observe Resolve directly**.
- The user’s descriptions, screenshots, and transcripts are the authoritative sensor data.
- Never override user observations with generic or internet-derived claims.

### 2. Version awareness
- Always assume DaVinci Resolve behavior is version-specific.
- When recording knowledge, explicitly note:
  - Resolve version (exact or approximate)
  - Platform (Windows/macOS/Linux, if known)
- Avoid universal statements unless explicitly confirmed across versions.

### 3. Failures are first-class data
- Incorrect advice, missing menus, removed features, and dead ends **must be recorded**.
- Prefer documenting *why something does not work* over optimistic procedures.
- Repeated mistakes should be consolidated into canonical “known false advice” records.

### 4. Structured over narrative
- Prefer rules, constraints, invariants, decision tables, and step transcripts.
- Avoid unstructured prose when a spec or checklist will do.

---

## File Naming Conventions
The workspace uses naming conventions to signal AI-relevant context:

- **ALL_CAPS.md** in workspace root = Vetted ground truth, constraints, key context for agents (excludes README.md)
- **dirname__/** = Directories containing AI-relevant documentation; scan for ALL_CAPS files and context
- **CONTEXT.md** = Directory-level "read this first" guidance for agents working in that directory
- Regular naming = User notes, drafts, unvetted material (including README.md files)

When starting work or answering questions, agents should:
1. Read all ALL_CAPS.md files in workspace root
2. Scan any `*__/` directories for additional context files
3. Check for CONTEXT.md in relevant directories
4. Prioritize vetted knowledge over generic assumptions and training data

---

## Agent Responsibilities
Agents should:
- Normalize user input into durable artifacts
- Propose file names, locations, and structure
- Refactor notes for clarity and reuse
- Flag uncertainty explicitly

Agents should not:
- Invent Resolve features or menus
- Assume tutorials are current
- Treat chat output as authoritative without repo-backed evidence
