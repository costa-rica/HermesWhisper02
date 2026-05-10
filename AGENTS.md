# Repository agent instructions

## Scope

- Applies to the full HermesWhisper02 monorepo.
- More specific instructions in child `AGENTS.md` files override these instructions for files under their directories.
- Use `AGENTS.md` as the active project convention source. `CLAUDE.md` exists only to point agents here.

## Work order

1. Read the relevant plan and requirement files in `docs/` before implementation.
2. Keep API and mobile changes separated unless a protocol change requires both.
3. Update checklist items in the relevant plan only after tests and build checks pass.
4. Commit one phase at a time when the user asks for commits or the phase workflow requires it.

## Documentation style

- For markdown files, prefer bullets and numbered lists.
- Use short paragraphs only when they make the summary easier to read.
- Avoid bold formatting.
- Never start headings, bullets, or numbered list items with bold text.
- Keep README files concise and aligned with `docs/README_FORMAT.md`.

## Git

- Do not amend commits.
- Do not use `--no-verify`.
- Do not revert user changes unless explicitly asked.
- Commit messages should follow `docs/CommitMessagesGuidance.md`.
- Phase commits should reference the plan file and phase, for example `PLAN_API phase 4`.

## Secrets

- Never commit secrets.
- `.env` files stay ignored.
- Commit only example shapes such as `.env.example`.
- Do not print API keys, bearer tokens, email passwords, or 2FA codes in normal logs.

## Protocol

- Treat `docs/20260510_PROTOCOL_V01.md` as the Swift to API source of truth.
- If protocol behavior is ambiguous, update the protocol document as its own commit before implementing the affected behavior.
- Keep `protocol_version` compatible across API and mobile.

## Verification

- Do not skip tests or build/typecheck commands.
- If a command cannot run because of local tooling, record the exact blocker in the final status.
- Before running a raw Python command, follow `docs/TODO_LIST_GUIDANCE.md`: check `which python` and `python --version`.
- Prefer `uv run python` inside `api/` when the local `python` alias is unavailable.
