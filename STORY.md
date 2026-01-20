Got it. Here's the story:

The Story of Masques
You are working on Masques—an identity compiler for AI agents.
The Problem We're Solving
Right now, agent identity is scattered. When you spin up an agent to do work, you configure it through disconnected mechanisms: a system prompt here, an MCP server there, environment variables, knowledge base references, tool permissions. There's no unified "become this identity" operation.
Orchestration frameworks like Ralph, CrewAI, and AutoGen are solving coordination—who talks to whom and when. But they all have the same gap: what is the agent when it enters the collaboration? The answer today is "a system prompt and some tools." That's not identity. That's configuration sprawl.
What Masques Is
A masque is a cognitive identity—a bundle of five components that together define who an agent is for a given task:

Intent — Why assume this identity? What goals, what boundaries?
Context — Who am I helping? What's the domain?
Knowledge — Where do I look things up? (Pointers, not embedded blobs)
Access — What credentials do I need? (Scoped, temporary)
Lens — How should I think? What's my style, my priorities?

A .masque.yaml file is source code for identity. The Zig CLI is a compiler that turns that source into consumable artifacts.
How It Works
bash# Compile a masque definition into an executable artifact
masques compile codesmith.masque.yaml -o codesmith.masque

# Emit configuration for a specific runtime
masques emit codesmith.masque.yaml --format=claude
masques emit codesmith.masque.yaml --format=ralph
The masque definition is portable. The emit targets adapt it to whatever orchestration framework or agent runtime needs to consume it. You're not asking orchestrators to adopt your model—you're handing them output in their native format.
The Feedback Loop
Masques aren't static. After a session, agents can report back:
yamlreflection:
  task_fit: 0.7
  intent_violations_attempted: ["ship without tests"]
  lens_alignment: high
  suggested_modifications:
    - "allow 'prototype *' for exploration phases"
This closes the loop. Masques become iterable. You build empirical data about which cognitive configurations work for which tasks and tools.
Why This Matters
The orchestration layer is commoditizing. Everyone's building "how agents coordinate." Nobody's building "who agents are when they show up." Masques is the identity layer beneath orchestration—portable, version-pinned, framework-agnostic.
When Ralph spins up three agents, each one should be able to don a masque and have that mean the same thing it would mean in CrewAI or AutoGen or Claude Code. That's the goal.
Current State

Design documentation complete
Zig CLI scaffolded (list/show work via DuckDB)
Compiler approach identified but not yet implemented
Bootstrap path: use yq for YAML→JSON, build emit pipeline

Your Job
Build the compiler. Make masques compile and masques emit work. Start with a single emit target (raw structured output to stdout). The interface matters more than the internals right now—get the artifact flowing, iterate from there.

Temporary identities. Coherent work.
