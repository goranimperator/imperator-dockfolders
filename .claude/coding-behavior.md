## AI Coding Rules & Behavior

You must strictly adhere to the following principles for all code generations, modifications, and discussions in this workspace.

### 1. Think Before Coding
*Don't assume. Don't hide confusion. Surface tradeoffs.*

Before implementing any code:
- **State assumptions:** Explicitly list your assumptions. If uncertain about anything, ask before writing code.
- **Handle ambiguity:** If multiple interpretations exist, present them to the user—do not pick one silently.
- **Propose simpler alternatives:** If a simpler approach exists, suggest it. Push back against complexity when warranted.
- **Stop on confusion:** If instructions are unclear, stop immediately. Name exactly what is confusing and ask for clarification.

### 2. Simplicity First
*Minimum code that solves the problem. Nothing speculative.*

- **No scope creep:** Do not add features beyond exactly what was asked.
- **No premature abstraction:** Do not create abstractions, classes, or utilities for single-use code.
- **No unused flexibility:** Do not add "flexibility" or "configurability" that wasn't requested.
- **No over-engineering:** Do not add error handling for impossible scenarios.
- **Ruthless refactoring:** If you write 200 lines and it could be done in 50, rewrite it.
- **The Senior Test:** Always ask yourself: *"Would a senior engineer say this is overcomplicated?"* If yes, simplify it immediately.

### 3. Surgical Changes
*Touch only what you must. Clean up only your own mess.*

When editing existing code:
- **Isolation:** Do not "improve" or touch adjacent code, comments, or formatting.
- **No unprompted refactoring:** Do not refactor things that are not broken.
- **Style matching:** Match the existing codebase style perfectly, even if you would personally design it differently.
- **Dead code:** If you notice unrelated dead code, mention it to the user—do not delete it on your own.

When your changes create orphans:
- **Clean up your mess:** Remove imports, variables, or functions that *your* changes made unused.
- **Leave old mess alone:** Do not remove pre-existing dead code unless explicitly asked.
- **The Line Test:** Every single changed line must trace directly back to the user's explicit request.

### 4. Goal-Driven Execution
*Define success criteria. Loop until verified.*

Always transform vague tasks into verifiable goals:
- *"Add validation"* → Write tests for invalid inputs, then make them pass.
- *"Fix the bug"* → Write a test that reproduces the bug, then make it pass.
- *"Refactor X"* → Ensure all existing tests pass both before and after the refactoring.

For multi-step tasks, you must state a brief execution plan before starting:
1. `[Step 1]` → verify: `[check]`
2. `[Step 2]` → verify: `[check]`
3. `[Step 3]` → verify: `[check]`
