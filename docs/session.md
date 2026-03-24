# Session State

Use this file as the single running log for progress and decisions. The previous session history has been archived.

## Current Phase
Phase 2: polish and repository truth-pass cleanup

## Current Focus
- Align README, docs, tests, and AGENTS.md with the actual codebase
- Enhanced search syntax and saved searches
- Smart collections
- Real-device testing (WiFi transfer + Send to Kindle)
- CloudKit entitlements and sync validation

## Recent Wins
- Verified the app still builds successfully
- Identified the major doc-to-code mismatches and stale assistant guidance
- Confirmed `.txt` is intentionally unsupported and reflected that in tests/docs

## Session Update
- Completed
  - Audited README, docs, AGENTS.md, tests, and current implementation for drift
  - Confirmed the app build succeeds
  - Identified stale architecture guidance, dead archive links, and test mismatches
- In Progress
  - Truth-pass cleanup of docs, tests, and assistant guidance
- Blockers
  - None beyond normal dirty-worktree caution
- Next Steps
  - Finish doc/test cleanup
  - Re-run targeted verification
- Decisions
  - `.txt` is not a supported Folio import or transfer format
  - Docs should describe shipped behavior, not planned or previously proposed architecture
