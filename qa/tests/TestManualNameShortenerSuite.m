classdef TestManualNameShortenerSuite < matlab.unittest.TestCase
% Automated equivalents of the manual NameShortener test cases in STR.md
% Section 16 (TC-NAME-*). This module (+ScapyML/NameShortener.m) has NO
% pre-existing automated test file at all, so this suite provides first-time
% component-level coverage of every public static method, in addition to
% the STR.md-mapped functional/boundary/edge cases.
%
% NOTE ON A SOURCE-COMMENT DISCREPANCY (found while writing this file):
% NameShortener.m's own class-level docstring claims abbreviateName
% converts "MyStructure -> MSt". Tracing the actual code (capital-letter
% extraction: M at position 1, S at position 3; caps(1)==1 so the
% "prepend first char" branch does NOT fire since the condition is
% caps(1) > 1) produces 'MS', not 'MSt'. This is a minor inaccuracy in the
% source file's own comment, not a functional defect — tcComponent_
% abbreviateNameCamelCaseExtractsCapitals below asserts the ACTUAL,
% verified behavior ('MS') rather than the docstring's example.

    methods (Test)

        % -----------------------------------------------------------
        % TC-NAME-FUNC-* / TC-NAME-BOUND-* (STR.md-mapped)
        % -----------------------------------------------------------

        function tcNameFunc001_shortNameReturnedUnchanged(testCase)
            % TC-NAME-FUNC-001 — a name already <= 63 characters is
            % returned unchanged (class docstring's own 46-char example).
            name = 'level2_level3_level4_deepest_level5_field1';
            testCase.verifyEqual(length(name), 46);
            result = ScapyML.NameShortener.shorten(name);
            testCase.verifyEqual(result, name);
        end

        function tcNameFunc002_longNamePreservesFinalFieldName(testCase)
            % TC-NAME-FUNC-002 — a name > 63 characters is shortened while
            % preserving the final field-name segment intact (class
            % docstring's own 69-char example).
            name = 'veryLongStructureNameForTesting_level3_level4_deepest_level5_field1';
            testCase.verifyEqual(length(name), 69);
            result = ScapyML.NameShortener.shorten(name);
            testCase.verifyLessThanOrEqual(length(result), 63);
            testCase.verifyTrue(endsWith(result, '_field1'), ...
                'The final field-name segment must survive shortening intact');
        end

        function tcNameFunc003_endToEndDeepNestingProducesUsableFieldName(testCase)
            % TC-NAME-FUNC-003 — a deeply nested header with long member
            % names triggers automatic shortening during parsing, and the
            % resulting field name is directly usable via Packet.set/get.
            longMemberName = 'thisIsAnIntentionallyVeryLongMemberNameToForceShortening';
            h = {
                sprintf('typedef struct DeepA { uint8_t %s; } DeepA;', longMemberName)
                'typedef struct DeepB { DeepA nestedLevelTwoContainer; } DeepB;'
                'typedef struct DeepC { DeepB nestedLevelThreeContainer; } DeepC;'
            };
            import matlab.unittest.fixtures.TemporaryFolderFixture
            fixture = testCase.applyFixture(TemporaryFolderFixture);
            f = writeFixtureHeader(fixture.Folder, 'deep.h', h);

            ScapyML.ProtocolRegistry.instance().clearAll();
            protos = ScapyML.HeaderParser.parseFile(f, 'little');
            proto = protos{end};
            names = proto.fieldNames();

            testCase.verifyEqual(numel(names), 1, ...
                'DeepC should flatten to exactly one field');
            testCase.verifyLessThanOrEqual(length(names{1}), namelengthmax, ...
                sprintf('Field name "%s" exceeds MATLAB''s namelengthmax', names{1}));

            % The (possibly shortened) name must actually work through
            % Packet.set()/get().
            pkt = ScapyML.Packet('DeepC');
            pkt.set(names{1}, 5);
            testCase.verifyEqual(pkt.get(names{1}), 5);
        end

        function tcNameBound001_exactly63CharsUnchanged(testCase)
            % TC-NAME-BOUND-001 — a name of EXACTLY 63 characters (the
            % boundary itself) must be returned unchanged.
            name63 = repmat('a', 1, 63);
            testCase.verifyEqual(length(name63), 63);
            result = ScapyML.NameShortener.shorten(name63);
            testCase.verifyEqual(result, name63);
        end

        function tcNameBound002_exactly64CharsTriggersShortening(testCase)
            % TC-NAME-BOUND-002 — a name of exactly 64 characters (one
            % past the boundary) must engage the shortening logic and
            % produce a result <= 63 characters.
            name64 = repmat('a', 1, 64);
            testCase.verifyEqual(length(name64), 64);
            result = ScapyML.NameShortener.shorten(name64);
            testCase.verifyLessThanOrEqual(length(result), 63);
            testCase.verifyNotEqual(result, name64);
        end

        function tcNameBound003_singleWordFallsToTruncateWithHash(testCase)
            % TC-NAME-BOUND-003 — a single-word name (no underscore
            % separators) exceeding the limit falls through directly to
            % truncateWithHash, producing "<truncated>_<8 hex digits>".
            name70 = repmat('x', 1, 70);  % single word, zero underscores
            result = ScapyML.NameShortener.shorten(name70);
            testCase.verifyLessThanOrEqual(length(result), 63);
            % Format check: exactly one underscore, followed by exactly 8
            % uppercase hex digits at the very end.
            tokens = regexp(result, '^(.*)_([0-9A-F]{8})$', 'tokens', 'once');
            testCase.verifyNotEmpty(tokens, ...
                'Expected "<truncated>_<8 hex digits>" format from truncateWithHash');
        end

        function tcNameEdge001_uniquenessRiskForSameLengthSameFirstCharSegments(testCase)
            % TC-NAME-EDGE-001 — hypothesised collision risk: ultraShort()
            % abbreviates any path segment to just "<firstChar><length>",
            % discarding all other content. Two DIFFERENT segments that
            % share both their first character AND their exact length
            % collapse to an IDENTICAL ultraShort token. If Strategies 1
            % and 2 (abbreviateCommonPrefixes / abbreviateAll) also fail
            % to fit within the available width — forcing a fallback to
            % Strategy 3 (ultraShort) — two otherwise-distinct long field
            % paths that differ ONLY in such a segment could shorten to
            % the SAME final name, which would corrupt Packet field
            % storage (two different source fields silently sharing one
            % MATLAB struct field).
            %
            % This test asserts the real invariant (uniqueness must be
            % preserved) using inputs specifically constructed to be
            % collision-prone under the mechanism above. If this test
            % FAILS, it confirms a genuine uniqueness defect in
            % NameShortener for deeply-nested headers with many
            % similarly-shaped long member names — log it as a new
            % Critical finding (potential silent field-value corruption)
            % rather than dismissing it as a test bug.
            filler = arrayfun(@(i) sprintf('longFillerSegmentNumber%02d', i), ...
                1:15, 'UniformOutput', false);
            % 'UNIQUEA' and 'UNIQUEB' share the same first character 'U'
            % and the same length (7) -> identical under ultraShort().
            name1 = strjoin([filler, {'UNIQUEA', 'field1'}], '_');
            name2 = strjoin([filler, {'UNIQUEB', 'field1'}], '_');
            testCase.verifyGreaterThan(length(name1), 63);
            testCase.verifyGreaterThan(length(name2), 63);

            result1 = ScapyML.NameShortener.shorten(name1);
            result2 = ScapyML.NameShortener.shorten(name2);

            testCase.verifyNotEqual(result1, result2, ...
                ['NameShortener must not silently collapse two distinct long field ' ...
                 'paths (differing only in a same-length, same-first-letter segment) ' ...
                 'to the identical shortened name.']);
        end

        % -----------------------------------------------------------
        % Component-level coverage of individual static methods
        % -----------------------------------------------------------

        function tcComponent_abbreviateNameShortNamePassthrough(testCase)
            % Names of 6 characters or fewer are returned unchanged.
            testCase.verifyEqual(ScapyML.NameShortener.abbreviateName('simple'), 'simple');
            testCase.verifyEqual(ScapyML.NameShortener.abbreviateName('ab'), 'ab');
        end

        function tcComponent_abbreviateNameCamelCaseExtractsCapitals(testCase)
            % Verified (corrected) behavior for camelCase abbreviation —
            % see class-level discrepancy note above.
            result = ScapyML.NameShortener.abbreviateName('MyStructure');
            testCase.verifyEqual(result, 'MS');
        end

        function tcComponent_abbreviateNamePrependsFirstCharWhenNotLeadingCap(testCase)
            % When the first capital is NOT at position 1, the original
            % first character is prepended to the capital-letter
            % abbreviation (caps(1) > 1 branch).
            % "veryLongName": v-e-r-y-L-o-n-g-N-a-m-e; capitals at L(5), N(9).
            result = ScapyML.NameShortener.abbreviateName('veryLongName');
            testCase.verifyEqual(result, 'vLN');
        end

        function tcComponent_abbreviateNameNoCamelCaseUsesFirstMidLast(testCase)
            % A name with no camelCase (fewer than 2 capitals) falls back
            % to first+middle+last character extraction.
            % "lowercase" (9 chars): first='l', mid=ceil(9/2)=5th char='r', last='e'.
            result = ScapyML.NameShortener.abbreviateName('lowercase');
            testCase.verifyEqual(result, 'lre');
        end

        function tcComponent_ultraShortCollapsesToFirstCharPlusLength(testCase)
            abbrev = ScapyML.NameShortener.ultraShort({'hello', 'world12'});
            testCase.verifyEqual(abbrev{1}, 'h5');
            testCase.verifyEqual(abbrev{2}, 'w7');
        end

        function tcComponent_ultraShortHandlesEmptyPartWithPlaceholder(testCase)
            abbrev = ScapyML.NameShortener.ultraShort({''});
            testCase.verifyEqual(abbrev{1}, 'x');
        end

        function tcComponent_abbreviateCommonPrefixesRecognizesLevelStructField(testCase)
            abbrev = ScapyML.NameShortener.abbreviateCommonPrefixes(...
                {'level3', 'struct2', 'field4', 'unrelated'});
            testCase.verifyEqual(abbrev{1}, 'l3');
            testCase.verifyEqual(abbrev{2}, 's2');
            testCase.verifyEqual(abbrev{3}, 'f4');
            testCase.verifyEqual(abbrev{4}, 'unrelated', ...
                'A part not matching level/struct/field prefixes must pass through unchanged');
        end

        function tcComponent_truncateWithHashFormatAndDeterminism(testCase)
            name = repmat('q', 1, 100);
            result1 = ScapyML.NameShortener.truncateWithHash(name, 63);
            result2 = ScapyML.NameShortener.truncateWithHash(name, 63);
            testCase.verifyEqual(result1, result2, ...
                'truncateWithHash must be deterministic for identical input');
            testCase.verifyLessThanOrEqual(length(result1), 63);

            tokens = regexp(result1, '^(.*)_([0-9A-F]{8})$', 'tokens', 'once');
            testCase.verifyNotEmpty(tokens);
        end

        function tcComponent_truncateWithHashDifferentInputsLikelyDifferentHash(testCase)
            r1 = ScapyML.NameShortener.truncateWithHash(repmat('a', 1, 100), 63);
            r2 = ScapyML.NameShortener.truncateWithHash(repmat('b', 1, 100), 63);
            testCase.verifyNotEqual(r1, r2);
        end

        function tcComponent_truncateWithHashInsufficientSpaceFallsBackToPlainTruncation(testCase)
            % maxLen < 10 leaves no room for "_" + 8 hex digits, so the
            % function must fall back to plain truncation with no hash.
            name = repmat('z', 1, 20);
            result = ScapyML.NameShortener.truncateWithHash(name, 8);
            testCase.verifyEqual(result, name(1:8));
            testCase.verifyFalse(contains(result, '_'));
        end

        function tcComponent_simpleHashIsDeterministicAndBounded(testCase)
            h1 = ScapyML.NameShortener.simpleHash('hello world');
            h2 = ScapyML.NameShortener.simpleHash('hello world');
            testCase.verifyEqual(h1, h2, 'simpleHash must be deterministic');
            testCase.verifyLessThan(h1, 2^32 - 1);
            testCase.verifyGreaterThanOrEqual(h1, 0);

            h3 = ScapyML.NameShortener.simpleHash('completely different string');
            testCase.verifyNotEqual(h1, h3);
        end

    end
end
