# cliamp-plugin-ascii-eq — Agent Context

## Status

**Placeholder project.** No code yet. This directory holds the brainstorm
for a future cliamp visualizer plugin that animates a user-supplied ASCII
art file from the EQ feed.

Work is paused while tubeamp (`~/builds/cliamp-plugin-tubeamp/`) is finalized.

## Important Notes

- This is a placeholder, NOT a real repo yet. No `git init` has been run.
- The eventual plugin name is undecided — see BRAINSTORM.md "Open decisions."
- The directory name `cliamp-plugin-ascii-eq` is provisional and will likely
  be renamed when the final plugin name is chosen.

## Background

Read `BRAINSTORM.md` in this directory. It captures:

- The original prompt from Nick
- 8 candidate design approaches with pros/cons
- The recommended v1 (combo of column-drive + glyph illumination)
- Proposed config schema
- Edge cases with provisional answers
- Open decisions Nick still needs to make
- Pre-build checklist

## Related project

`~/builds/cliamp-plugin-tubeamp/` is the sibling project — its
`docs/DESIGN.md` is the template this plugin should follow when it gets
spun up for real. The color ramp and ANSI helpers should be reused
verbatim so the two plugins feel like the same family.

## Upstream

cliamp lives at `~/builds/cliamp/`. Read `docs/plugins.md` there for the
plugin API contract. Detailed orientation already captured in
`~/builds/cliamp-plugin-tubeamp/docs/DESIGN.md`.

## When work resumes

Follow the pre-build checklist at the bottom of BRAINSTORM.md.
