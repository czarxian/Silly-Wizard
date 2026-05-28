# BETA_RELEASE_PLAN.md

## Scope
Prepare a stable Windows beta build distributed as a zipped folder (Steam-compatible packaging workflow).

## Distribution Model (Decision)
- Ship as a zipped Windows build folder.
- Assume Steam depot upload consumes the built folder contents.
- Keep runtime writes in user-writable locations (under GameMaker runtime paths), not inside protected install folders.

## Release Goals
- Build runs on non-dev machines without editing paths.
- Tune library loads consistently in packaged build and zip extraction installs.
- Player settings, per-tune overrides, performances, and audit/debug logs persist safely.
- No regressions in single-tune and set playback flows.

## Must-Fix Before Beta

### 1. Eliminate developer-machine absolute paths
Current blockers:
- Hardcoded dev tune root in startup library build.
- Hardcoded dev tune root in manual library regenerate.
- Hardcoded dev path candidate in tune library loader.
- Hardcoded absolute BPM trace log path.

Required outcome:
- All runtime file access uses resolver-based relative defaults.
- Optional absolute paths are configurable, never hardcoded to a specific machine/user.

### 2. Standardize runtime roots by file category
- Read-only shipped content:
  - tunes
  - score images/manifests
  - embellishments
- Mutable user/runtime data:
  - config and per-player settings
  - performances and summaries
  - debug/audit logs

Required outcome:
- One canonical root strategy per category.
- No mixed behavior where one path uses absolute dev root while another uses runtime-relative fallback.

### 3. Validate packaged content assumptions
- Confirm required tune assets are available in packaged output.
- Confirm tune scanning strategy matches packaged folder layout.
- Confirm score sprite loading paths resolve correctly from packaged tune file locations.

Required outcome:
- Fresh machine smoke test succeeds with no manual path edits.

## Execution Plan

### Phase A - Path Hardening (Start Here)
1. Add/confirm centralized path resolver helpers for:
- tune library root
- tune library index file
- debug log paths
2. Replace hardcoded path call sites with resolver usage.
3. Keep current relative fallbacks for packaged runtime behavior.

Exit criteria:
- No code references to C:/Users/xian/... for runtime GML paths.
- Startup and regenerate both rebuild/load tune library successfully.

### Phase B - Packaging Validation
1. Create Windows build output.
2. Zip distribution folder.
3. Test on clean machine/profile:
- launch
- load single tune
- load set
- run playback
- export history
- restart app and verify settings/overrides persistence

Exit criteria:
- Full smoke flow passes without code/config edits.

### Phase C - QA Gate
1. Run pending gameplay validations already tracked in PROJECT_PLAN.md:
- transition tune pickup/segment restore scenarios
- single vs set scoring playthrough sweep
2. Verify no regressions in:
- timeline score visibility toggle
- per-player per-tune zoom restore (single-tune mode)

Exit criteria:
- No release-blocking behavior regressions.

### Phase D - Beta Packaging Checklist
1. Set Windows metadata fields (display/product/company/version).
2. Build release candidate.
3. Produce zip artifact.
4. Write short beta tester notes:
- where runtime data is stored
- how to submit logs/exports
- known limitations

Exit criteria:
- RC zip ready for Steam depot/beta distribution.

## Start-Now Task List
- [x] Replace startup hardcoded tune root with resolver path.
- [x] Replace regenerate hardcoded tune root with resolver path.
- [x] Remove hardcoded absolute tune_library.json candidate path.
- [x] Replace hardcoded bpm_trace.log absolute path with resolver path.
- [ ] Run build + zipped-folder smoke test.

## Risks and Mitigations
- Risk: Path changes break tune loading in one mode (single/set).
  - Mitigation: Keep fallback candidates and test both load paths.
- Risk: Packaged assets differ from dev folder assumptions.
  - Mitigation: Perform clean-machine run from zip before beta release.
- Risk: Debug/audit logs fail in restricted folders.
  - Mitigation: Write logs to runtime-relative user-writable paths.

## Out of Scope for this beta hardening pass
- New calibration feature work.
- Major UI redesign.
- Steam API integration details beyond build-folder compatibility.
