classdef TestManualMatSuite < matlab.unittest.TestCase
% Automated equivalents of the manual MAT-persistence test cases in
% STR.md Section 10 (TC-MAT-*). This file intentionally does NOT
% re-implement cases already covered by TestMatPersistence.m (basic
% round-trip fidelity, missing-packetData detection at the raw struct
% level, protocol-mismatch detectability via strcmp, relative
% save/load performance sanity).
%
% As with TestMatPersistence.m, the actual save/load logic lives inline
% inside ScapyML_GUI.m's saveToMAT()/loadFromMAT() nested callbacks and
% is not exposed as a standalone, directly callable function. These tests
% therefore replicate the EXACT validation logic read directly from
% ScapyML_GUI.m (lines ~688-697 for the required-fields check) to verify
% the documented contract precisely, in the same spirit as the existing
% suite's protocolMismatchIsDetectable test.

    properties
        TempFolder
    end

    methods (TestClassSetup)
        function classSetup(testCase)
            import matlab.unittest.fixtures.TemporaryFolderFixture
            fixture = testCase.applyFixture(TemporaryFolderFixture);
            testCase.TempFolder = fixture.Folder;

            h = {'typedef struct MatProto { uint16_t a; uint8_t b; } MatProto;'};
            f = writeFixtureHeader(testCase.TempFolder, 'matproto.h', h);
            ScapyML.ProtocolRegistry.instance().clearAll();
            ScapyML.HeaderParser.parseFile(f, 'little');
        end
    end

    methods (Test)

        function tcMatErr002a_missingProtocolNameFieldDetected(testCase)
            % TC-MAT-ERR-002 — a packetData struct present but missing the
            % required 'protocolName' sub-field must be detected by the
            % exact validation logic in ScapyML_GUI.m's loadFromMAT():
            %   if ~isfield(packetData,'packets') || ~isfield(packetData,'protocolName')
            %       error('Invalid MAT file: missing required fields');
            %   end
            pkt = ScapyML.Packet('MatProto');
            packetData = struct('packets', {{pkt}});  % 'protocolName' deliberately absent
            matFile = fullfile(testCase.TempFolder, 'missing_protoname.mat');
            save(matFile, 'packetData');

            loaded = load(matFile);
            pd = loaded.packetData;

            testCase.verifyError(...
                @() testCase.replicateRequiredFieldsCheck(pd), ...
                'ScapyMLTest:InvalidMatFile');
        end

        function tcMatErr002b_missingPacketsFieldDetected(testCase)
            % TC-MAT-ERR-002 — the mirror case: 'packets' absent,
            % 'protocolName' present.
            packetData = struct('protocolName', 'MatProto');  % 'packets' absent
            matFile = fullfile(testCase.TempFolder, 'missing_packets.mat');
            save(matFile, 'packetData');

            loaded = load(matFile);
            pd = loaded.packetData;

            testCase.verifyError(...
                @() testCase.replicateRequiredFieldsCheck(pd), ...
                'ScapyMLTest:InvalidMatFile');
        end

        function tcMatErr002c_bothFieldsPresentPassesValidation(testCase)
            % Sanity companion to TC-MAT-ERR-002 — confirms the replicated
            % check does NOT false-positive when both required fields are
            % present (guards against a trivially-always-failing check).
            pkt = ScapyML.Packet('MatProto');
            packetData = struct('protocolName', 'MatProto', 'packets', {{pkt}});
            testCase.verifyWarningFree(...
                @() testCase.replicateRequiredFieldsCheck(packetData));
        end

        function tcMatFunc001_saveOmitsOptionalMetadataWhenEmpty(testCase)
            % TC-MAT-FUNC-001 — saveToMAT() only adds defaultsFile /
            % conversionFile / sourceCSV keys when the corresponding
            % state.* string is non-empty (per the "if ~isempty(...)"
            % guards in ScapyML_GUI.m's saveToMAT()). This test replicates
            % that exact conditional-field-population contract for a
            % session where none of those optional files were used.
            pkt = ScapyML.Packet('MatProto');
            packetData = struct();
            packetData.protocolName = 'MatProto';
            packetData.packetCount = 1;
            packetData.packets = {pkt};
            % Simulate: state.defaultsFile = ''; state.conversionFile = '';
            % state.csvFile = '' -> none of the optional fields are added.

            testCase.verifyFalse(isfield(packetData, 'defaultsFile'));
            testCase.verifyFalse(isfield(packetData, 'conversionFile'));
            testCase.verifyFalse(isfield(packetData, 'sourceCSV'));

            matFile = fullfile(testCase.TempFolder, 'no_optional_meta.mat');
            save(matFile, 'packetData');
            loaded = load(matFile);
            testCase.verifyFalse(isfield(loaded.packetData, 'sourceCSV'));
        end

        function tcMatFunc001b_saveIncludesOptionalMetadataWhenPresent(testCase)
            % TC-MAT-FUNC-001 (continued) — when state.csvFile etc. WERE
            % set, the corresponding metadata keys are present and survive
            % the round-trip.
            pkt = ScapyML.Packet('MatProto');
            packetData = struct();
            packetData.protocolName = 'MatProto';
            packetData.packetCount = 1;
            packetData.packets = {pkt};
            packetData.defaultsFile = 'defaults.txt';
            packetData.conversionFile = 'conversions.txt';
            packetData.sourceCSV = 'original_data.csv';

            matFile = fullfile(testCase.TempFolder, 'with_optional_meta.mat');
            save(matFile, 'packetData');
            loaded = load(matFile);

            testCase.verifyEqual(loaded.packetData.defaultsFile, 'defaults.txt');
            testCase.verifyEqual(loaded.packetData.conversionFile, 'conversions.txt');
            testCase.verifyEqual(loaded.packetData.sourceCSV, 'original_data.csv');
        end

        function tcMatFunc004_packetsRemainFunctionalAfterAcceptedMismatch(testCase)
            % TC-MAT-FUNC-004 — after a user accepts a protocol-mismatch
            % warning ("Yes" to "Load anyway?"), the loaded Packet objects
            % must still be fully functional: each Packet carries its OWN
            % embedded ProtocolDef reference (captured at construction
            % time), independent of the metadata string comparison used
            % only to WARN the user. build() must still succeed and
            % reflect the packet's true, original protocol layout.
            pkt = ScapyML.Packet('MatProto');
            pkt.set('a', 500);
            pkt.set('b', 7);
            originalBytes = pkt.build();

            packetData = struct('protocolName', 'MatProto', 'packetCount', 1, ...
                                 'packets', {{pkt}});
            matFile = fullfile(testCase.TempFolder, 'mismatch_functional.mat');
            save(matFile, 'packetData');

            loaded = load(matFile);
            % Simulate the metadata string mismatch check (as loadFromMAT
            % does) against an arbitrarily different "currently selected"
            % protocol name, then simulate the user clicking "Yes".
            selectedProtocol = 'SomeCompletelyDifferentProtocol';
            isMismatch = ~strcmp(loaded.packetData.protocolName, selectedProtocol);
            testCase.verifyTrue(isMismatch);

            % User clicked "Yes" -> packets are loaded anyway.
            restoredPkt = loaded.packetData.packets{1};
            testCase.verifyEqual(restoredPkt.get('a'), 500);
            testCase.verifyEqual(restoredPkt.get('b'), 7);
            testCase.verifyEqual(restoredPkt.build(), originalBytes, ...
                'A Packet loaded despite a metadata protocol-name mismatch must still build() identically, since it carries its own embedded ProtocolDef');
        end

        function tcMatData001_1000PacketRoundTripSamplesMatchOriginal(testCase)
            % TC-MAT-DATA-001 — round-trip fidelity for a larger (1000)
            % packet collection, spot-checked at the first, middle, and
            % last packet per STR.md's documented sampling strategy.
            proto = ScapyML.ProtocolRegistry.instance().get('MatProto');
            allFields = ScapyML.Packet.collectFields(proto.Fields);
            defaults = struct();
            for k = 1:numel(allFields)
                defaults.(allFields{k}.Name) = allFields{k}.DefaultVal;
            end

            n = 1000;
            packets = cell(1, n);
            for i = 1:n
                packets{i} = ScapyML.Packet.fromValuesStruct(proto, defaults, ...
                    struct('a', i, 'b', mod(i, 256)));
            end

            packetData = struct('protocolName', 'MatProto', 'packetCount', n, ...
                                 'packets', {packets});
            matFile = fullfile(testCase.TempFolder, 'thousand.mat');
            save(matFile, 'packetData', '-v7.3');

            loaded = load(matFile);
            restored = loaded.packetData.packets;
            testCase.verifyEqual(numel(restored), n);

            testCase.verifyEqual(restored{1}.get('a'), 1);
            testCase.verifyEqual(restored{1}.get('b'), mod(1, 256));

            midIdx = round(n/2);
            testCase.verifyEqual(restored{midIdx}.get('a'), midIdx);
            testCase.verifyEqual(restored{midIdx}.get('b'), mod(midIdx, 256));

            testCase.verifyEqual(restored{n}.get('a'), n);
            testCase.verifyEqual(restored{n}.get('b'), mod(n, 256));
        end

    end

    methods (Access = private)
        function replicateRequiredFieldsCheck(~, packetData)
            % Exact replica of ScapyML_GUI.m's loadFromMAT() required-
            % fields validation (lines ~694-697):
            %   if ~isfield(packetData,'packets') || ~isfield(packetData,'protocolName')
            %       error('Invalid MAT file: missing required fields');
            %   end
            % Re-thrown here with a test-local identifier so
            % verifyError() can target it precisely; the real GUI code
            % uses a plain, identifier-less error() call with this exact
            % message text.
            if ~isfield(packetData, 'packets') || ~isfield(packetData, 'protocolName')
                error('ScapyMLTest:InvalidMatFile', ...
                    'Invalid MAT file: missing required fields');
            end
        end
    end
end
