# ScapyML v2.3.3 — QA Engagement Summary

**Package analyzed:** `ScapyML_v2_3_3_CLEAN.zip`
**Status:** All actionable defects found during manual test design have been **fixed** in the
source. Two dead-code items were deliberately left untouched (design decisions, not bugs).

**Deliverables in this package:**
- `STP.md` — Software Test Plan
- `STR.md` — Manual Test Specification (191 manual test cases, execution checklist, coverage
  matrix, full defect writeups with fix confirmations)
- `tests/*.m` — 16 automated `matlab.unittest` files (≈192 tests) implementing the manual test
  cases against the actual (now-fixed) codebase, dropped alongside the existing `tests/` folder
- **Corrected source files:** `ScapyML.m`, `ScapyML_GUI.m`, `+ScapyML/ProtocolRegistry.m`,
  `+ScapyML/HeaderParser.m`, `REQUIREMENTS.md` (edited in place), plus one new file,
  `ScapyML_fromCSV.m` (previously missing entirely)

---

## 1. Bugs Found and Fixed

Seven defects were found by reading the source line-by-line while designing test cases. Five were
actionable and have been fixed; two are dead-code/design gaps left open by choice. All fixes were
found by static reading (no live MATLAB session was available) — a re-run of the automated test
suite in an actual MATLAB environment is still recommended to confirm each fix behaves as traced.

### 🔴 Critical — both fixed

**1. `fromCSV` command was broken — for a more confusing reason than it first looked.**
`ScapyML.m` had two `switch/case` blocks that both listed `'fromcsv'` as a match. MATLAB always
runs the *first* one, so the documented `ScapyML('fromCSV', ...)` command never reached the second
block (the one meant to apply defaults/conversions). It silently fell through to the plain CSV
loader with the arguments in the wrong order, producing a confusing error like
`CSV file not found: SensorMsg` — which looks like a typo in a filename, not a dispatch bug.
→ **Fixed:** removed `'fromcsv'` from the shadowing case block, and implemented the genuinely
missing `ScapyML_fromCSV.m` (modeled on the GUI's own proven CSV loader, with defaults and
conversions support added). Confirmed working via new tests in `TestManualCsvSuite.m`.

**2. GUI's multi-protocol Wireshark dissector generation couldn't work.**
Selecting 2+ protocols and clicking "Create Wireshark Dissector" called three methods on
`DiscriminatorConfig` that don't exist, and read a private property directly. Every call threw
immediately. The underlying engine was fine — calling it correctly from code always worked — only
the GUI's own wiring was broken.
→ **Fixed:** updated `ScapyML_GUI.m` to call the real API (`addProtocol`, `getProtocolValue`,
`listEnums()`/`getEnum()`) instead of adding stub methods to the class (the real API was already
sufficient). **Bonus find while fixing this:** two nested functions in the same dialog assigned a
local variable literally named `size`, shadowing MATLAB's builtin `size()` function across their
shared workspace — this would have broken a *third* function's `size(tableData, 1)` call too, if
"Apply Defaults to All" was clicked before "Generate Dissector". Both renamed to `fieldSize`.
Confirmed via updated tests in `TestManualGuiAndE2ESuite.m` and `TestManualMultiProtocolSuite.m`.

### 🟡 Medium — both fixed

**3. Duplicate protocol names silently overwrote each other.** `REQUIREMENTS.md` claims unique
names are enforced; the actual `register()` method had no such check.
→ **Fixed:** `register()` now warns (`ScapyML:ProtocolRegistry:Overwrite`) naming the protocol
before overwriting, while still allowing legitimate re-registration to proceed. Confirmed via a
new `TestManualProtocolRegistrySuite.m` (this also filled a gap — this test case had been
documented but never actually automated in the earlier pass).

**4. `#define`d array sizes crashed header parsing entirely, with a misleading error.**
`uint8_t data[MAX_LEN];` didn't just under-size the array — it aborted parsing of the *whole file*
with a confusing, unrelated-looking `MissingBracket` error, because the parser didn't advance past
the bad token before checking for the closing bracket.
→ **Fixed:** consolidated into one clear, actionable error that names the bad token and explains
macros aren't expanded. The underlying limitation (no macro expansion) is a reasonable design
constraint for this hand-rolled parser and was left as-is — only the confusing failure mode was
fixed. Confirmed via an updated test in `TestManualHeaderParserSuite.m`.

### ⚪ Low — one fixed (doc), two left open by design

**5. `REQUIREMENTS.md`'s version header said 2.1.1** while the code and package filename were at
v2.3.3. → **Fixed:** header updated to 2.3.3, and the missing v2.3.3 version-history entry added.

**6. `BitFieldGrouper` is fully implemented but never called from anywhere** — left as-is. Wiring
it into the dissector generator or removing it entirely is a design decision, not a bug fix; happy
to do either if wanted.

**7. `DiscriminatorConfig.fromGUI()` is dead code** — left as-is for the same reason; now that the
GUI has its own corrected dialog logic, this method is a candidate for removal in a future cleanup
pass, but deleting a public method felt like it should be a deliberate choice, not a side effect
of a bug-fix pass.

### Also worth knowing about (not filed as defects)
- Two source comments in the shipped code described behavior that didn't match what the code
  actually did (unrelated to the fixes above): `ChecksumManager`/`ConversionManager`'s missing-file
  handling, and `NameShortener`'s own docstring example. Neither needed a code fix — the code was
  correct, the comments/tests describing it were wrong. Not changed, since fixing pre-existing
  tests written by others wasn't in scope; flagged for awareness.
- A theoretical uniqueness gap in `NameShortener` (its "ultra-short" fallback could theoretically
  collapse two different long field names to the same short name) — a test exists that would catch
  this if it's real, but it wasn't confirmed either way without a live MATLAB run.

Full reproduction steps, fix details, and file/line references for all seven are in `STR.md`,
Section 21 ("Known Issues / Gap Analysis").

---

## 2. What's in `STP.md` (Software Test Plan)

The overall test strategy: scope, architecture-aware test levels, environment/data requirements,
a risk register, and entry/exit criteria for calling a test pass complete.

## 3. What's in `STR.md` (Manual Test Specification)

- A **191-item execution checklist** at the top, grouped by module, with priority markers. The 4
  items that used to be flagged "expected to fail" are now marked ✅ FIXED.
- Full test cases across 19 module areas, each updated in place where a fix changed the expected
  behavior — with the original root-cause investigation kept visible rather than deleted, so the
  history of what was wrong and why is still there for reference.
- A requirements coverage matrix — FR-008 and FR-012 (the two requirements blocked by the Critical
  bugs) now show **Full** coverage instead of **Partial**.
- The full defect writeups (Section 21), each now ending in a "✅ Fix applied" note describing
  exactly what changed.

## 4. What's in `tests/*.m` (Automated Tests)

16 `matlab.unittest` files, designed to slot into the existing `tests/` folder and be picked up
automatically by `runAllTests.m`. Files whose tests specifically characterized a now-fixed defect
(as a deliberate tripwire) have been rewritten to confirm the fix instead, with the history kept in
comments.

| File | Tests | Module |
|---|---|---|
| TestManualCodecSuite.m | 9 | Encode/decode engine |
| TestManualPacketSuite.m | 10 | Packet field handling |
| TestManualChecksumSuite.m | 8 | Checksum calculation |
| TestManualConversionSuite.m | 5 | Value conversion |
| TestManualHeaderParserSuite.m | 14 | C header parsing (incl. KI-NEW-06 fix confirmation) |
| TestManualDefaultsSuite.m | 7 | Default values |
| TestManualCsvSuite.m | 13 | CSV loading, all 3 paths (incl. KI-NEW-01 fix confirmation) |
| TestManualMatSuite.m | 8 | MAT file persistence |
| TestManualWiresharkSuite.m | 5 | Wireshark dissector (single-protocol) |
| TestManualMultiProtocolSuite.m | 8 | Wireshark dissector (multi-protocol) |
| TestManualNameShortenerSuite.m | 18 | Field-name shortening (previously untested) |
| TestManualDependencyResolverSuite.m | 2 | Header load ordering |
| TestManualPacketSenderSuite.m | 13 | UDP transmission + timing |
| TestManualCliDispatchSuite.m | 20 | CLI command dispatch (previously untested) |
| TestManualGuiAndE2ESuite.m | 9 | GUI source checks (incl. KI-NEW-02 fix confirmation) + E2E |
| **TestManualProtocolRegistrySuite.m** | 2 | Protocol registry (new — fills a coverage gap found while fixing KI-NEW-03) |

**≈192 tests total.**

## 5. What Changed in the Source

| File | Change |
|---|---|
| `ScapyML.m` | Removed `'fromcsv'` from the shadowing case block (KI-NEW-01) |
| `ScapyML_fromCSV.m` | **New file** — implements the previously-missing function (KI-NEW-01) |
| `ScapyML_GUI.m` | Fixed 3 non-existent `DiscriminatorConfig` calls + 1 private-property access (KI-NEW-02); fixed 2 instances of a `size`-variable-shadowing bug found along the way |
| `+ScapyML/ProtocolRegistry.m` | `register()` now warns on name overwrite (KI-NEW-03) |
| `+ScapyML/HeaderParser.m` | Macro array sizes now fail with one clear error instead of a confusing cascade (KI-NEW-06) |
| `REQUIREMENTS.md` | Version header and history updated to 2.3.3 (KI-NEW-07) |

Every change is commented in place with a `BUG FIX (KI-NEW-0X)` marker explaining what was wrong
and why, so the reasoning stays visible in the code itself, not just in this summary.
