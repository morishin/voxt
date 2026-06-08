# Operating Rules

## Documentation
- Stock information to be shared with the team (requirements, design documents, etc.) should be placed in the `docs/` directory and managed with Git.

## Design Plans
- Plan files are saved in the `docs/plans` directory.
- Once a plan is finalized, before starting implementation, always do the following:
  1. Rename the plan file with a sequential prefix and a descriptive name (e.g., `001-database-schema-design.md`)
  2. Add it to the index in the reference materials section below
  3. If the new plan makes any existing content in `docs/` outdated, update those documents
  4. Add a task list section (checkbox format) to the plan file
  5. Commit all of the above changes together
- During implementation, work through the task list in the plan file and check off tasks as they are completed, then commit. This allows you to see remaining work at any time from the plan file.
- If the approach changes during implementation, update the plan file accordingly.

## Git Operations
- Commit each time a single task is completed.
- Since task completion often requires developer verification, ask for confirmation before committing in those cases.
  - However, if the developer has instructed you to proceed autonomously, this does not apply.

## MCP Tools
- **xcode** — Can build the project. After implementing, verify that the build passes.

# Reference Materials

## docs/ (Team Shared Documents)
- `app_overview.md` — Overview of the current app form, menu bar, settings screens, key behaviors, i18n support, and internal defaults
- `release.md` — Distribution setup (Developer ID signing + notarization + GitHub Releases), GitHub Secrets list, release procedure, update check mechanism, and troubleshooting

## docs/plans/ (Design Plans)
- `001-local-voice-input-pipeline.md` — Implementation plan for the local voice input app (multi-language support, chunk splitting for token limit handling, utterance queuing/chunk parallel formatting, insertion order guarantee pipeline)
- `002-rebrand-voxt-about-tab.md` — Plan for vkey → Voxt rebrand, physical rename, About tab addition, update check, and GitHub Releases distribution/CI
