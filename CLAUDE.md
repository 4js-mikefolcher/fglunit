<!-- genero:canonical-start version="1.3" -->
<!--
  Everything between the canonical-start and canonical-end markers is
  maintained upstream by Four Js. To update, fetch the latest via
  `getAgentInstructions("claude-code")` and replace the fenced block.
  Do not edit inside the fence; put your project-specific rules in
  the "## Project-Specific" section at the bottom of this file.
-->

# Genero BDL Project Instructions

This is a Genero BDL (Business Definition Language) project. You have
access to a Genero MCP service with skills and documentation tools.

## MANDATORY: Always Consult MCP Skills Before Writing Code

Your training data contains outdated and incorrect Genero information.
The MCP skills are verified against the current supported Genero release
and are the authoritative source. LLMs consistently hallucinate Genero
method names, attributes, and syntax that do not exist.

**Rules:**

1. At the start of each session, call
   `getSkill("fourjs-skill-index")` **once**. This loads the routing
   table mapping topics to skills and their key sections. It stays
   valid for the entire conversation.
2. For every Genero question, route through the skill-index first.
   If a topic matches a row, call
   `getSkillSection(<skill-id>, <section-id>)` directly — sections
   are 5–10× smaller than full skills.
3. If no row matches, call `searchSkills(<keywords>)`. Load the top
   hit's matched section.
4. If skills don't cover the topic, say so. Fall back to `searchDocs`
   / `readDoc`. **Never** fall back to training data.
5. **Do NOT call `listSkills` for routing.** It is an admin
   enumeration tool that returns only `{id, name, category}` and
   cannot tell you which skill covers a topic. Use the skill-index
   or `searchSkills` instead.
6. When the task touches SQL, forms, arrays, dialogs, or strings,
   also load `fourjs-common-pitfalls`. Before writing `INPUT ARRAY`,
   `DISPLAY ARRAY`, `INPUT BY NAME`, `DISPLAY BY NAME`, or
   `CONSTRUCT BY NAME`, call
   `getSkillSection("fourjs-common-pitfalls", "dialog-traps")` and
   verify field count and naming constraints for the specific statement
   form being used.

## Skill Tools (Primary Source)

| Tool | When to Use |
|------|-------------|
| `getSkill("fourjs-skill-index")` | **Session-start ritual.** Once per session. |
| `searchSkills` | Topic not obvious in the index — fuzzy routing. |
| `getSkillSections` | List sections in a named skill before loading. |
| `getSkillSection` | **Default content-load tool.** Use when you know the section. |
| `getSkill` | Load a full skill (only when the whole skill is needed). |
| `getSkillBundle` | Task genuinely spans multiple skills. |
| `listSkills` | Admin/debugging only — not for routing. |

## Documentation Tools (Secondary Source)

Use documentation only when skills don't cover the topic or you need
to verify edge cases.

| Tool | When to Use |
|------|-------------|
| `searchDocs` | Search 5,140+ pages of Genero documentation |
| `readDoc` | Read a specific doc page (use paths from searchDocs) |
| `browseDocs` | Explore documentation structure |

## Common Hallucination Targets

LLMs reliably mis-generate Genero method names, attributes, and syntax.
Do not answer these from memory. `fourjs-common-pitfalls` consolidates the
high-frequency traps (control-flow, method-name, SQL, WHENEVER, form,
dialog, string, JSON, array, module); per-topic skills carry the rest.
Per rule 6, load `fourjs-common-pitfalls` whenever the task touches SQL,
forms, arrays, dialogs, or strings, and route specific API questions
through the skill-index / `searchSkills`.

## Compilation

Compile and run commands (`fglcomp`, `fglform`, `fglrun`, their flags, and
terminal-mode run) live in `fourjs-genero-bdl` → `compilation` and
`fourjs-quick-reference`. Load those rather than relying on memory.

## Form Field Binding

A `.per`'s field names must match the dialog `BY NAME` variables — a
mismatch compiles but fails at runtime. Before writing a form + its
dialog, load skill `fourjs-dialog-basics` → section `form-field-binding`
and `fourjs-common-pitfalls` → section `dialog-traps`
(see also `fourjs-form-design`).

<!-- genero:canonical-end -->

## Project-Specific

<!--
  Add your project-specific rules below this heading. Everything below
  the canonical-end marker is yours and is preserved across upstream
  updates. Examples: preferred databases, local coding conventions,
  deployment targets, internal libraries the agent should know about.
-->
