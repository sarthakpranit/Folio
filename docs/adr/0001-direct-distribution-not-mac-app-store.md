# ADR 0001 — Direct distribution (notarized DMG), not the Mac App Store

- **Status:** Accepted (2026-09-09)
- **Wayfinder ticket:** [D1 — Distribution target](https://github.com/sarthakpranit/Folio/issues/21) · map [#19](https://github.com/sarthakpranit/Folio/issues/19)

## Context

Folio's format-conversion and embedded-metadata features are implemented by shelling out to Calibre's command-line tools. `CalibreConversionService` spawns:

- `/Applications/calibre.app/Contents/MacOS/ebook-convert` (conversion)
- `/Applications/calibre.app/Contents/MacOS/ebook-meta` (metadata extraction)
- `/usr/bin/which` (executable discovery)

The Mac App Store sandbox forbids spawning arbitrary external executables and forbids depending on a separately-installed application. MAS distribution and the current conversion architecture are therefore mutually exclusive. Shipping on MAS would require either bundling an in-process conversion engine, or dropping Calibre and supporting far fewer formats — a rewrite of the entire conversion pipeline (see R5, [#34](https://github.com/sarthakpranit/Folio/issues/34)).

The near-term goal is "make it work well," not "sell it." Distribution mechanics (certificates, notarization, update feed) are not on the critical path yet.

## Decision

1. **Folio is distributed directly as a notarized `.dmg`.** The Mac App Store is out of scope for this effort and is not a design constraint.
2. **Calibre remains an external, optional runtime dependency.** Folio does not bundle Calibre binaries. (Bundling would add ~150 MB and, because Calibre is GPL v3, would force Folio's own license — that question is ADR 0002 / [D2](https://github.com/sarthakpranit/Folio/issues/22).)
3. **Conversion is a degradable feature, not a hard requirement.** The app must be fully usable with Calibre absent: library management, search, metadata fetch from the web APIs, WiFi transfer, and Send-to-Kindle-of-native-formats all work without it. Only format conversion (and on-the-fly Kindle conversion) disable when Calibre is not found.
4. **Calibre's absence is surfaced first-class.** Detect on launch; show a clear "Install Calibre to enable conversion" affordance; expose the detected path (and a manual override) in Preferences. This requirement is documented in DOC1 ([#28](https://github.com/sarthakpranit/Folio/issues/28)).
5. **Self-update via Sparkle**, with the appcast hosted on GitHub Releases — as the intended mechanism, not built yet.
6. **Deferred to a later, separate distribution effort:** the Apple Developer Program (paid) membership decision, the Developer ID Application signing identity, notarization credential storage, and the Sparkle appcast URL and signing keys. The map already parks signed-DMG release *automation* and the release acceptance matrix as out of scope (old [#7](https://github.com/sarthakpranit/Folio/issues/7), [#8](https://github.com/sarthakpranit/Folio/issues/8)).

## Consequences

- **R5 (conversion review):** the `Process`/Calibre dependency is *allowed*. R5's findings stand on their own merits (timeouts, races, dead progress code), not on sandbox grounds. The Calibre-detection UX (R3 #57 context, R5 #76) becomes real product work, tracked via DOC1 and a Preferences panel.
- **Sandbox:** Folio can still run under the App Sandbox with `com.apple.security.app-sandbox` + user-selected file access + the `com.apple.security.temporary-exception` (or a helper) needed to launch Calibre — the sandbox entitlement set is a distribution-effort detail, not decided here.
- **Revisiting MAS** would require a new effort whose first ticket is "replace the external Calibre pipeline with an in-process conversion path" — a rewrite, not a packaging change. This ADR does not close that door; it declines to hold it open at architectural cost.
- **D2** (license) is now partly constrained: because Folio does *not* link or bundle Calibre code (only invokes its CLI as a separate process), Folio is **not** forced to GPL v3 by the Calibre dependency. D2 remains a free choice.
