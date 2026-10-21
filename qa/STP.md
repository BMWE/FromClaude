# ScapyML — Software Test Plan (STP)

**Project:** ScapyML — MATLAB Network Packet Framework
**Package analyzed:** `ScapyML_v2_3_3_CLEAN.zip` (folder `matlab_scapy_clean/`)
**Version under test:** v2.3.3 (per `ScapyML.m` fix comments and `REQUIREMENTS.md` §10, though the
REQUIREMENTS.md header itself still states "Version: 2.1.1" — see §14 Risks)
**Document type:** Manual Software Test Plan
**Companion document:** `STR.md` (Manual Test Specification / test cases + coverage matrix)

---

## 1. Test Objectives

1. Verify that C header parsing (`HeaderParser`) correctly builds protocol/field/enum models for
   all documented C constructs (primitives, bit-fields, arrays, nested structs/unions, enums,
   cross-file type references).
2. Verify that the encode/decode engine (`Codec`) produces byte-accurate output for every
   supported field type, endianness, alignment, and bit-field packing rule, and that encode and
   decode are mutually consistent (round-trip).
3. Verify that packet-level operations (`Packet`) enforce field validation, range clamping, array
   padding/truncation, and correct build/parse behavior.
4. Verify that the external-configuration subsystems (`ChecksumManager`, `ConversionManager`,
   `DefaultsManager`) load, validate, and apply user-supplied formulas/values correctly, and fail
   safely on malformed input.
5. Verify that bulk CSV loading, MAT-file persistence, UDP transmission (including timing modes),
   and Wireshark Lua dissector generation behave as specified for both the CLI (`ScapyML.m`) and
   GUI (`ScapyML_GUI.m`) entry points.
6. Identify and document any deviation between the `REQUIREMENTS.md` specification and the actual
   behavior of the delivered code, including defects discovered during test-case design (see
   `STR.md` §Known Issues / Gap Analysis).

---

## 2. Scope

Manual testing covers all functionality reachable through:

- The CLI entry point `ScapyML.m` (commands: `load`, `packet`, `csv`, `send`, `dissector`, `info`,
  `list`, `defaults`, `loaddefaults`, `register`, `fromcsv`).
- The GUI entry point `ScapyML_GUI.m` (all 25 buttons/controls across the 5 panel sections: Load
  Headers, Protocol Info, Packet, Data, Actions).
- The public class API under `+ScapyML/`: `HeaderParser`, `ProtocolDef`, `FieldDef`, `EnumDef`,
  `ProtocolRegistry`, `Packet`, `Codec`, `ChecksumManager`, `ConversionManager`,
  `DefaultsManager`, `CsvLoader`, `UdpSender`, `PacketSender`, `WiresharkDissector`,
  `MultiProtocolDissector`, `DiscriminatorConfig`, `DependencyResolver`, `NameShortener`,
  `BitFieldGrouper`.
- External configuration file formats: `.h` protocol headers, checksum `.txt`, conversion `.txt`,
  defaults `.txt`, discriminator-config `.txt`, CSV data files, `.mat` packet collections,
  generated `.lua` Wireshark dissectors.

---

## 3. Out of Scope

- Automated/unit-test execution (`tests/*.m`, `matlab.unittest` suite, `runAllTests.m`) — these
  already exist as an automated regression suite and are a *different* verification activity from
  the manual testing covered by this document. Manual testing in `STR.md` is designed to
  complement them (per `REQUIREMENTS.md` DP-005 — manual byte-level verification), not duplicate
  them line-for-line.
- Load/stress testing beyond the specific NFR-001 performance targets stated in
  `REQUIREMENTS.md` (single packet <10ms, 1000-packet CSV load <15s, 1000-packet MAT load <1s).
- Actual Wireshark installation and live-capture verification of generated `.lua` dissectors —
  testing is limited to inspecting the generated Lua source for correctness (syntax, offsets,
  masks) since Wireshark itself is external tooling not included in this package.
- Testing of MATLAB Instrument Control Toolbox legacy `udp()` or raw Java `DatagramSocket`
  fallback paths inside `UdpSender` beyond confirming the fallback *logic* exists — these paths
  only activate on MATLAB configurations lacking `udpport` (R2020b+), which is environment-
  dependent and cannot be forced deterministically in a single test environment.
- Security penetration testing of the checksum/conversion formula `eval()` mechanism beyond
  confirming that malformed/malicious-looking formulas are handled with a warning rather than a
  silent miscalculation (these files are trusted, user-authored local configuration, not untrusted
  network input — see DP-001).

---

## 4. System Overview

ScapyML is a MATLAB framework (package `+ScapyML`) that lets a user:

1. Define a binary protocol by writing a plain C header (`.h`) with `typedef struct/union/enum`.
2. Parse that header into an in-memory `ProtocolDef` (registered in a singleton
   `ProtocolRegistry`).
3. Create `Packet` instances, set field values (with automatic range checking/clamping), and
   encode them to raw bytes (`Codec`), optionally applying post-encoding checksums
   (`ChecksumManager`).
4. Bulk-create packets from CSV data (`CsvLoader` / GUI bulk loader), optionally applying
   physical-to-wire conversions (`ConversionManager`) and defaults (`DefaultsManager`).
5. Persist packet collections to `.mat` files for fast reuse (GUI only).
6. Transmit packets over UDP (`UdpSender`, `PacketSender`) in single, periodic, or CSV-timestamp-
   replay modes, to unicast or multicast destinations.
7. Auto-generate a Wireshark Lua dissector (`WiresharkDissector`, `MultiProtocolDissector`) so
   captured traffic can be decoded field-by-field in Wireshark.

Both a MATLAB command-line interface (`ScapyML.m`) and a full `uifigure`-based GUI
(`ScapyML_GUI.m`) expose this functionality.

---

## 5. Architecture Relevant to Testing

Per `REQUIREMENTS.md` §2.1, the framework is a 5-layer architecture:

| Layer | Modules | Test Focus |
|---|---|---|
| 1. Presentation | `ScapyML_GUI.m`, `ScapyML.m` | Workflow correctness, error surfacing, button state management |
| 2. Application | Command dispatch inside `ScapyML.m` | Argument parsing, command routing |
| 3. Business Logic | `Packet`, `Codec`, `ChecksumManager`, `ConversionManager`, `DefaultsManager` | Field validation, byte-accurate encode/decode, checksum/conversion correctness |
| 4. Protocol | `HeaderParser`, `ProtocolRegistry`, `ProtocolDef`, `FieldDef`, `EnumDef` | Parsing correctness, layout/alignment, registry integrity |
| 5. Network | `PacketSender`, `UdpSender` | Timing precision, socket lifecycle, unicast/multicast |

Two components sit outside this layering and are tested separately:
- **Wireshark dissector generation** (`WiresharkDissector`, `MultiProtocolDissector`,
  `DiscriminatorConfig`, `BitFieldGrouper`, `NameShortener`) — consumes Layer 4 objects, produces
  external `.lua` artifacts.
- **`DependencyResolver`** — a pre-processing step invoked by Layer 1/2 before `HeaderParser` runs,
  when multiple header files are loaded together with automatic ordering.

A critical, testable architectural invariant (per `ProtocolDef.alignBitPos`'s own code comment,
fixed in v2.3.1 as "KI-001") is that **five separate code paths** — `ProtocolDef.recompute()`,
`Codec.encodeFields`, `Codec.decodeFields`, `ProtocolDef.getFieldOffsets()`, and
`WiresharkDissector.emitFieldList`/`collectFieldsWithMeta` — must all agree on field bit
placement. Divergence between any of these previously caused silent data corruption. Manual
cross-checking of offsets reported by `ScapyML('info', ...)` / `proto.getFieldOffsets()` against
actual encoded byte positions is therefore a first-class test activity (see `STR.md`
TC-CODEC-INT tests).

---

## 6. Modules and Features Under Test

1. **C Header Parsing** — primitives, bit-fields, arrays, nested struct/union, enums, comments,
   cross-file type resolution, dependency-ordered multi-file loading, name shortening for >63-char
   MATLAB identifiers.
2. **Protocol Data Model** — `ProtocolDef` layout computation (C-ABI alignment, union vs struct
   sizing), `FieldDef` type-size mapping, `EnumDef` value tables, `ProtocolRegistry` singleton
   behavior.
3. **Packet Field Manipulation** — `set`/`get`, array truncation/padding, signed/unsigned range
   clamping per type, unknown-field errors, nested/dotted field access limitations.
4. **Packet Encoding/Decoding** — `Codec.encode`/`decode`, bit-field MSB-first packing, float/double
   IEEE-754 handling, union semantics (dirty-field-only writing), round-trip fidelity.
5. **Checksum Calculation** — `ChecksumManager` formula loading, post-encoding calculation,
   zero-before-compute idempotency, multi-checksum offset ordering, malformed-formula handling.
6. **Value Conversion** — `ConversionManager` physical-to-wire formulas, error fallback to raw
   value.
7. **Default Values** — `DefaultsManager` file generation and application, override semantics.
8. **Bulk CSV Loading** — CLI `ScapyML.CsvLoader`, CLI `fromcsv` command (**known broken**, see
   §14), and the GUI's independent vectorized bulk loader (`fromValuesStruct`), including
   waitbar/cancel behavior.
9. **MAT File Persistence** — GUI Save/Load to `.mat`, protocol-mismatch handling, metadata
   round-trip.
10. **UDP Transmission** — `UdpSender` persistent-socket lifecycle, `sendOnce` convenience,
    unicast/multicast detection, `PacketSender` single/periodic/CSV-timed modes, timing precision,
    Ctrl+C/cancel handling.
11. **Wireshark Dissector Generation** — single-protocol (`WiresharkDissector`, working) and
    multi-protocol (`MultiProtocolDissector` + `DiscriminatorConfig`, **known broken via GUI**, see
    §14) Lua generation; enum value tables; bit-field masks; array handling; nested struct/union
    subtrees.
12. **CLI Command Dispatch** — every `ScapyML(...)` command switch case, unknown-command handling,
    help text.
13. **GUI Workflows** — all three documented workflows (Single Packet, Bulk CSV, Reuse Saved
    Packets) plus supporting dialogs (Edit Packet Fields, Send dialog, Wireshark dialog,
    Discriminator config dialog, Clear Protocols).

---

## 7. Testing Strategy

- **Component-level manual validation**: exercise each class's public methods directly from the
  MATLAB command window with hand-crafted header/CSV/config fixtures, verifying return values and
  byte-level output against hand-computed expected values.
- **Integration testing**: verify data flows correctly across layer boundaries — e.g. a value set
  via `Packet.set()` appears at the correct byte offset after `Codec.encode()`, and that same
  offset is what `ChecksumManager` and `WiresharkDissector` independently compute.
- **System / end-to-end testing**: run full CLI and GUI workflows exactly as documented in
  `REQUIREMENTS.md` §6.2 (Workflow 1/2/3), from header load through UDP send / dissector
  generation.
- **Manual byte-level verification** (DP-005): for representative structs, manually hand-encode
  the expected byte sequence (accounting for endianness, alignment padding, and bit-field packing)
  and diff it against `pkt.build()` output and the corresponding hex dump.
- **Negative / fault-injection testing**: missing files, malformed config syntax, protocol-name
  typos, out-of-range values, array size mismatches, duplicate discriminator values, circular
  header dependencies.

---

## 8. Test Levels

| Level | Description | Example |
|---|---|---|
| Component | Single class/function in isolation | `ScapyML.FieldDef.ctypeBytes('uint32_t')` returns 4 |
| Integration | Two or more components together | `Packet.build()` → `ChecksumManager.applyChecksums()` → correct checksum byte written |
| System | Full CLI or GUI feature | Load header → create packet → set fields → send UDP |
| End-to-End | Complete documented workflow | GUI Workflow 2 (Bulk CSV): load header → load conversions → load CSV → save MAT → load checksums → send |
| Acceptance | Cross-check against `REQUIREMENTS.md` FR/NFR list | Each FR-0xx acceptance criterion individually verified |

---

## 9. Functional Testing

Covered exhaustively per module in `STR.md`. Priority given to:
- Every C type in `FieldDef.ctypeBytes` (8/16/32/64-bit signed/unsigned, float, double, char
  variants).
- Every bit-field width from 1 to 32 bits, including cross-byte-boundary bit-fields.
- Every array scenario: exact-size, undersized (padded), oversized (truncated) CSV/set() input.
- Both endiannesses for every multi-byte type.
- Nested struct-in-struct, union-in-struct, struct-in-union, and array-of-struct.

## 10. UI Testing

GUI button enable/disable state machine (buttons disabled until a protocol is loaded/selected/
packet created, per `protocolSelected()`/`createPacket()` logic), dialog modality, waitbar
cancel-button behavior, dropdown population after load/clear, field-editor dialog value parsing
(scalar vs. space/comma-separated array).

## 11. Validation Testing

Field-name existence checks (`Packet.set`/`get` error on unknown field), numeric-value type
checks, array element count validation, checksum-function return-type validation (must be scalar
numeric), discriminator size validation (must be 1/2/4 bytes).

## 12. Negative Testing

Non-existent header/CSV/checksum/conversion/MAT file paths, malformed struct/union syntax,
missing closing brace, multi-dimensional array syntax (explicitly rejected with `error`), invalid
array size token, unresolved type references (now warn instead of silently corrupting, per
v2.3.3 fix), unknown CLI command, `send` with an unsupported data type.

## 13. Boundary Testing

- Integer range boundaries for every signed/unsigned width (e.g. uint8 0/255/256/-1; int8
  -128/127/128/-129).
- Bit-field boundary widths (1 bit, 7 bits crossing into next byte, exactly 8 bits, >8 bits).
- Array size 0/1/max declared size, and CSV/set() value counts above/below declared size.
- MATLAB 63-character field-name limit (`NameShortener` — exactly 63, 64, and very long
  deeply-nested names).
- Empty CSV file, CSV with header row only (no data rows), CSV with only some columns matching
  protocol fields.
- Zero-length / zero-byte fields (unresolved-type fallback).
- Discriminator field sizes exactly 1, 2, 4 bytes (5 is invalid per `DiscriminatorConfig`).

## 14. Edge Case Testing

- Duplicate protocol names registered (registry overwrite behavior — not explicitly validated by
  `ProtocolRegistry.register`, per code inspection; `REQUIREMENTS.md` §8.3 claims "Unique protocol
  names enforced" but no such enforcement exists in `register()` — **discrepancy, see Risks**).
- Re-loading the same header twice.
- Union with all-default (unset) fields — `Codec` union write logic depends on the `dirty` map;
  encoding a `Packet` with no explicit `set()` calls on any union member.
- Truly anonymous inline struct/union (no member name) — fields flattened directly into parent
  with no prefix.
- Circular header dependencies (`DependencyResolver` — must raise `ScapyML:CircularDependency`).
- CSV numeric values in hex notation (`0x...`) of varying digit counts (uint8/16/32/64
  auto-sizing in `CsvLoader.parseNum`).
- Checksum/conversion formulas containing `==`, `<=`, `>=` (must not break the "split on first
  `=`" line parser).
- Sending 0 packets (empty cell array) via `PacketSender.sendWithTiming`.
- CSV-timed send with non-ascending timestamps (`PacketSender` must `error`).

## 15. Error Handling Testing

Every `try/catch` surfaced to the user must produce a clear, actionable message (per NFR-002/
DP-003): file-not-found, parse errors, checksum evaluation errors, UDP send failures (all three
socket backends), MAT-file structural validation errors, protocol-mismatch confirmation dialogs.

## 16. API Testing

Not a networked REST/RPC API; "API" here means the public MATLAB class/method surface. Each
public method listed in `README.md` §"API Reference" is exercised directly from the MATLAB
command window with valid and invalid arguments (see `STR.md` TC-API-* series).

## 17. Database Testing

Not applicable — ScapyML has no database. The closest analogue, the in-memory
`ProtocolRegistry` (`containers.Map`), is tested under Protocol Registry test cases (registration,
lookup, existence checks, `clearAll`/`clearInstance`).

## 18. Integration Testing

See `STR.md` TC-*-INT series. Key integration points:
- `HeaderParser` → `ProtocolRegistry` (registration timing across multi-file loads, v2.3.3 fix).
- `Packet` → `Codec` (build/parse).
- `Packet` → `ChecksumManager` (`buildWithChecksums`).
- `ConversionManager` → GUI CSV loader → `Packet.fromValuesStruct`.
- `PacketSender` → `UdpSender` → `ChecksumManager` (checksum applied per-packet during timed send).
- `ProtocolDef`/`FieldDef` → `WiresharkDissector` (offset/mask agreement, KI-001/KI-003).
- `ScapyML_GUI.m` → `DiscriminatorConfig` → `MultiProtocolDissector` (**broken**, see §14 above and
  `STR.md` Known Issues).

## 19. End-to-End Testing

Three documented GUI workflows (`REQUIREMENTS.md` §6.2) plus the CLI equivalent (`README.md`
"Basic Example" / "Full Workflow Example") are each executed start-to-finish as system tests.

## 20. Authentication Testing

Not applicable — ScapyML has no authentication or user-account concept.

## 21. Authorization Testing

Not applicable — no roles/permissions model exists in this codebase.

## 22. Security Testing

Limited scope (see §3 Out of Scope). Covers: confirming checksum/conversion formula files are
evaluated via MATLAB `eval()` and that malformed/unexpected formula strings produce a caught
warning rather than crashing the whole load; confirming file-path inputs (header, CSV, MAT,
config) are validated with `isfile`/`exist` before use; confirming generated `.lua` files strip
non-ASCII bytes (existing defensive code in `WiresharkDissector`/`MultiProtocolDissector`) so a
maliciously-named protocol/enum cannot inject arbitrary bytes into the Lua script.

## 23. Data Integrity Testing

- Round-trip fidelity: `pkt.build()` then `Packet.fromBytes(protoName, bytes)` must reproduce the
  original field values (within the precision of the declared C type).
- MAT-file round-trip: save N packets, reload, verify field values and count match.
- Checksum idempotency: calling `build()`/`buildWithChecksums()` multiple times on the same packet
  must produce the identical checksum value every time (verifies the "zero the checksum field
  before computing" fix documented in `ChecksumManager.applyChecksums`).
- CSV bulk-load conversion correctness: verify conversion is applied exactly once per value (guard
  against double-scaling, per the code comment in `ScapyML_GUI.m`'s `loadFromCSV`).

## 24. Performance Testing Considerations

Manual stopwatch/`tic`-`toc` checks only (no automated load-testing scripts), per NFR-001 targets:
- Single packet `build()`: should complete well under 10 ms (manually timed with `tic`/`toc` around
  a single call, averaged over several calls).
- 1000-row CSV bulk load via the GUI's vectorized loader: should complete in well under 15 seconds
  (informal wall-clock timing while the waitbar is visible).
- 1000-packet MAT save/load: should complete in well under 1 second (`tic`/`toc` around
  `save`/`load` calls), and should be visibly faster than the equivalent CSV load.

These are sanity-check observations, not formal benchmarks; no automated timing harness is created
per the manual-testing-only scope of this document.

## 25. Compatibility Testing

- Endianness: every relevant test case run in both `'big'` and `'little'` header-load modes.
- MATLAB `udpport` availability: `UdpSender` has a three-tier fallback (`udpport` → legacy `udp()`
  → Java `DatagramSocket`); manual testing confirms the "modern" path works on the test
  environment and that the fallback *code path exists*, without necessarily forcing all three
  branches (see §3 Out of Scope).
- Platform: MATLAB is cross-platform; no OS-specific behavior identified in the reviewed code
  beyond standard file-path handling (`fullfile`, `uigetfile`/`uiputfile` dialogs), so
  compatibility testing is limited to confirming the GUI renders and functions on whatever
  platform the tester's MATLAB session runs on. No dedicated multi-OS/browser/device matrix is
  applicable — this is a desktop MATLAB application, not a web or mobile app.

## 26. Smoke Testing

Minimal pass/fail gate before deeper testing: load one simple header, create one packet, set one
field, `build()` it, confirm non-empty byte array of the expected length, and confirm `ScapyML
GUI` opens without error via `TestGuiSmoke`-equivalent manual check (open GUI, confirm all buttons
render, close without error).

## 27. Sanity Testing

After any config/code change, re-run: load header → create packet → build → checksum → send
(loopback) → generate dissector, confirming no regression in the primary happy path before
investing in the full manual suite.

## 28. Regression Testing

Given the version history in `REQUIREMENTS.md` §10, regression testing should specifically
re-verify the fixes called out there before any release:
- KI-001: alignment-padded `TotalBits` matches actual field placement in `Codec`/
  `getFieldOffsets`/`WiresharkDissector` (5-way agreement).
- KI-002: `ProtocolRegistry.clearInstance()` actually clears the singleton.
- KI-003: bit-field encode→decode round-trip and Wireshark mask agreement (MSB-first packing).
- v2.3.3: cross-file type resolution (struct/enum in file A referenced from file B parsed in a
  separate `parseFile()` call); unresolved-type now warns instead of silently zero-sizing.

## 29. Exploratory Testing

Time-boxed, unscripted exploration of the GUI — particularly the "Edit Packet Fields" scrollable
dialog with a protocol that has a very large number of fields, the multi-protocol Wireshark
dialog (given the known defect, see §14), and CSV files with unusual column ordering/casing/extra
columns — to surface issues not anticipated by the scripted test cases in `STR.md`.

## 30. Recovery and Resilience Testing

- Cancel button behavior mid-CSV-load (large file) and mid-UDP-send (periodic/CSV-timed) via the
  GUI waitbar's cancel button — verify partial results are handled gracefully (packets loaded up
  to cancellation point are kept; sending stops cleanly).
- `Ctrl+C` interrupt during CLI `PacketSender.sendWithTiming` periodic/CSV mode — verify the
  socket is still closed (`catch` block calls `sender.close()`).
- Recovery after a failed UDP send (e.g., invalid IP) — verify the error propagates without
  leaving a socket open (destructor `delete()` on `UdpSender`).

## 31. Test Environment

- MATLAB (any R2020b+ release recommended, for the modern `udpport` UDP backend; the framework
  falls back to older mechanisms on earlier releases per `UdpSender.openSocket`).
- `+ScapyML` class folder on the MATLAB path (or working directory containing it), plus
  `ScapyML.m` and `ScapyML_GUI.m` on the path.
- Local loopback UDP testing (`127.0.0.1`) preferred to avoid external network dependencies;
  Wireshark installed locally is optional/out-of-scope for full live-capture verification (see §3).
- No external services, databases, or credentials are required — the framework is fully
  self-contained and file-based (DP-001).

## 32. Test Data

- A small library of hand-authored `.h` fixtures exercising: all primitive types, bit-fields
  (single-byte and cross-byte), arrays, nested struct, nested union, enums, and multi-file
  cross-references (mirrors the pattern used by `tests/writeFixtureHeader.m` in the existing
  automated suite, but authored independently for manual testing per DP-005).
- CSV files: well-formed matching all columns; missing columns; extra unrecognized columns; empty
  cells; hex-notation values; large (~1000+ row) file for performance sanity checks; a CSV with a
  `timestamp` column for CSV-timed send testing.
- Checksum/conversion/defaults `.txt` files: valid formulas (sum, XOR, ones'/two's complement, as
  shown in `checksums_example.txt`); malformed formulas (missing `@`, syntax errors, non-function
  right-hand side); files referencing non-existent field names.
- Pre-built `.mat` files: one matching the currently selected protocol, one from a different
  protocol (to test the mismatch-confirmation dialog), one deliberately corrupted/missing the
  `packetData` structure.

## 33. Dependencies

- MATLAB base + (optionally) Instrument Control Toolbox for the legacy `udp()` fallback path.
- No third-party MATLAB File Exchange packages are imported anywhere in the reviewed source.
- Manual testers need a text editor (for authoring `.h`/`.txt`/`.csv` fixtures) and, optionally,
  Wireshark (for out-of-scope live dissector verification).

## 34. Risks

| Risk | Impact | Notes |
|---|---|---|
| CLI `fromcsv` command and GUI's "use defaults with CSV" path call the undefined function `ScapyML_fromCSV`, which is **not present** in this package | High — feature completely non-functional wherever exercised | See `STR.md` Known Issues KI-NEW-01 |
| GUI multi-protocol Wireshark dissector generation calls `DiscriminatorConfig` methods (`setDefaults`, `addMappingSimple`, `getMapping`) that do not exist on the actual class | High — feature completely non-functional | See `STR.md` Known Issues KI-NEW-02 |
| `ProtocolRegistry.register()` performs no duplicate-name check, contradicting `REQUIREMENTS.md` §8.3 ("Unique protocol names enforced") | Medium — silent overwrite of an existing protocol definition is possible | See `STR.md` Known Issues KI-NEW-03 |
| `BitFieldGrouper` is fully implemented but never invoked from any other module | Low — dead code; no functional risk, but suggests an incomplete/abandoned feature (grouped bit-field display in dissectors) | See `STR.md` Known Issues KI-NEW-04 |
| `DiscriminatorConfig.fromGUI()` builds a `uifigure` dialog that is never actually invoked by `ScapyML_GUI.m` (which has its own, differently-structured discriminator dialog) | Low — dead/orphaned code path, only reachable via direct programmatic call to `MultiProtocolDissector.generate` with no `discConfig` argument | See `STR.md` Known Issues KI-NEW-05 |
| `REQUIREMENTS.md` header states "Version: 2.1.1" while `ScapyML.m`/`ProtocolDef.m` code comments reference fixes through v2.3.3 | Low — documentation/version-string drift only | Noted for completeness |
| Legacy `udp()` and Java `DatagramSocket` fallback paths in `UdpSender` cannot be forced/verified in a modern MATLAB test environment | Low–Medium — untested code paths | See §3 Out of Scope |

## 35. Assumptions

- The tester has a working MATLAB installation with the `+ScapyML` package and both entry-point
  `.m` files on the path, matching the exact contents of `ScapyML_v2_3_3_CLEAN.zip`.
- "Manual testing" means a human tester invokes MATLAB commands / GUI actions and visually/
  programmatically inspects results (e.g., via `disp`, hex dump, breakpoints) — not that formulas
  or byte layouts are computed by hand from scratch for every single test case; hand computation
  is reserved for the DP-005 byte-level verification cases specifically.
- Loopback (`127.0.0.1`) UDP send/receive is sufficient to verify transmission correctness; testers
  do not need a second physical machine.
- The existing automated `matlab.unittest` suite in `tests/` is assumed to already pass (it is out
  of scope to re-verify it here) — manual testing is additive, per DP-005's own rationale.

## 36. Entry Criteria

- This package (`matlab_scapy_clean/`) is unpacked and placed on the MATLAB path.
- `REQUIREMENTS.md` and `README.md` are available as the specification baseline.
- Test fixtures described in §32 are prepared.
- Tester has verified `ScapyML_GUI` launches without error (smoke test, §26) before proceeding to
  scripted test cases.

## 37. Exit Criteria

- All test cases in `STR.md` have been executed and marked Pass/Fail/Blocked.
- All FR-001 through FR-013 acceptance criteria in `REQUIREMENTS.md` have at least one
  corresponding executed manual test case with a recorded result.
- All defects found (including the two pre-identified breaking defects in §34) are logged with
  reproduction steps.
- No unresolved **Critical** or **High** severity defects remain open in core encode/decode,
  checksum, or CLI dispatch functionality (Wireshark multi-protocol generation and `fromcsv` are
  explicitly carved out as **known-broken, tracked** defects that do not block sign-off provided
  they are documented — see `STR.md` Known Issues).

## 38. Defect Management

Each failed test case in `STR.md` should be logged with: Test Case ID, module/file and line
reference (where identified during code reading), reproduction steps, expected vs. actual result,
and severity (Critical/High/Medium/Low). The two pre-identified defects (missing
`ScapyML_fromCSV.m`; `DiscriminatorConfig` method mismatch in the GUI) are already documented in
`STR.md` with file/line references so they can be filed directly without re-discovery.

## 39. Test Prioritization

1. **Critical** — Codec encode/decode byte accuracy (all types, bit-fields, endianness,
   alignment); Packet field validation; ChecksumManager post-encoding correctness; CLI/GUI happy
   paths for the three documented workflows.
2. **High** — HeaderParser construct coverage; ProtocolRegistry/singleton behavior; CSV bulk
   loading (both working paths); UDP send timing modes; single-protocol Wireshark dissector
   generation.
3. **Medium** — DefaultsManager, ConversionManager, MAT persistence, DependencyResolver,
   NameShortener boundary cases.
4. **Low** — Multi-protocol dissector generation and `fromcsv`/defaults-CSV path (already known
   broken — tests here primarily *confirm and characterize* the failure rather than seek new
   defects), BitFieldGrouper (dead code), GUI cosmetic/layout details.

## 40. Quality Gates

- Gate 1 (Smoke): GUI opens, CLI `ScapyML('list')` runs without error on a clean session.
- Gate 2 (Component): All Critical-priority Codec/Packet/HeaderParser test cases pass.
- Gate 3 (Integration): Checksum, CSV bulk-load (GUI path), and UDP send integration test cases
  pass.
- Gate 4 (System/E2E): All three documented workflows complete end-to-end without unhandled
  errors, and single-protocol Wireshark dissector output is manually verified correct for at
  least one struct with bit-fields, arrays, and an enum.
- Release readiness requires Gates 1–4 passed and all defects logged per §38, with the two known
  breaking defects either fixed or explicitly accepted/documented as known limitations before
  shipping v2.3.3 (or whatever version follows).

---

*This STP is a companion to `STR.md`, which contains the actionable test cases, IDs, and coverage
matrix implementing the strategy defined above.*
