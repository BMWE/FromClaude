# How to Use This Package

## Applying the source fixes

The `corrected_source/` folder contains only the files that were changed or added while fixing
the bugs described in `SUMMARY.md` / `STR.md` §21. To apply them to your original
`ScapyML_v2_3_3_CLEAN` package, copy them over the matching paths:

```
corrected_source/ScapyML.m                      -> ScapyML.m                      (modified)
corrected_source/ScapyML_fromCSV.m              -> ScapyML_fromCSV.m              (NEW file)
corrected_source/ScapyML_GUI.m                  -> ScapyML_GUI.m                  (modified)
corrected_source/REQUIREMENTS.md                -> REQUIREMENTS.md                (modified)
corrected_source/+ScapyML/ProtocolRegistry.m    -> +ScapyML/ProtocolRegistry.m    (modified)
corrected_source/+ScapyML/HeaderParser.m        -> +ScapyML/HeaderParser.m        (modified)
```

Every change in the modified files is marked in place with a comment starting `BUG FIX (KI-NEW-0X)`
so you can see exactly what changed and why with a simple search, rather than diffing blind.

No other source files were touched. `+ScapyML/DiscriminatorConfig.m` and
`+ScapyML/BitFieldGrouper.m` in particular were deliberately left unchanged — see KI-NEW-04/05 in
`STR.md` for why (dead code left as a design decision, not a bug fix).

## Adding the test suite

Copy everything in `tests/` into your existing `tests/` folder (no filename collisions with the
existing suite — all 16 files are new). `runAllTests.m` will pick them up automatically via
`TestSuite.fromFolder`, no registration needed.

## Recommended order to verify

1. Apply the source fixes above.
2. Copy the new tests into `tests/`.
3. Run `runAllTests` (or `runtests('tests')`) from MATLAB with `+ScapyML/` and both entry-point
   `.m` files on the path.
4. Everything should pass. If something doesn't, it's either an environment difference (e.g. no
   loopback UDP available — several tests skip gracefully via `assumeFail` in that case) or a
   genuine finding worth reporting back.
5. Read `STR.md` §21 for the full reasoning behind each fix, and `STP.md` for the overall test
   strategy if you want to extend coverage further.
