classdef TestManualDefaultsSuite < matlab.unittest.TestCase
% Automated equivalents of the manual DefaultsManager test cases in
% STR.md Section 8 (TC-DEF-*). This file intentionally does NOT
% re-implement cases already covered by TestDefaultsManager.m (create()
% generates a file listing all fields, apply() overrides packet fields,
% comments/blank lines ignored, unspecified fields keep their protocol
% default).

    properties
        TempFolder
    end

    methods (TestClassSetup)
        function classSetup(testCase)
            import matlab.unittest.fixtures.TemporaryFolderFixture
            fixture = testCase.applyFixture(TemporaryFolderFixture);
            testCase.TempFolder = fixture.Folder;

            h = {'typedef struct D2 { uint8_t a; uint16_t b; float c; } D2;'};
            f = writeFixtureHeader(testCase.TempFolder, 'd2.h', h);
            ScapyML.ProtocolRegistry.instance().clearAll();
            ScapyML.HeaderParser.parseFile(f, 'little');
        end
    end

    methods (Test)

        function tcDefFunc003_hexNotationValue(testCase)
            % TC-DEF-FUNC-003 — a hex-notation value ("0x2A") in a
            % defaults file parses to its decimal equivalent (42).
            defFile = fullfile(testCase.TempFolder, 'defaults_hex.txt');
            fid = fopen(defFile, 'w');
            fprintf(fid, 'a = 0x2A\n');
            fclose(fid);

            pkt = ScapyML.Packet('D2');
            pkt = ScapyML.DefaultsManager.apply(pkt, defFile);
            testCase.verifyEqual(pkt.get('a'), 42);
        end

        function tcDefFunc005_explicitSetAfterApplyOverrides(testCase)
            % TC-DEF-FUNC-005 — an explicit set() call after apply()
            % always wins over the loaded default.
            defFile = fullfile(testCase.TempFolder, 'defaults_override.txt');
            fid = fopen(defFile, 'w');
            fprintf(fid, 'c = 20.0\n');
            fclose(fid);

            pkt = ScapyML.Packet('D2');
            pkt = ScapyML.DefaultsManager.apply(pkt, defFile);
            testCase.verifyEqual(pkt.get('c'), 20.0);

            pkt.set('c', 99.9);
            testCase.verifyEqual(pkt.get('c'), 99.9, ...
                'Explicit set() after apply() must override the loaded default');
        end

        function tcDefErr001_missingFileErrors(testCase)
            % TC-DEF-ERR-001 — applying a non-existent defaults file
            % errors clearly rather than silently no-op'ing.
            pkt = ScapyML.Packet('D2');
            testCase.verifyError(...
                @() ScapyML.DefaultsManager.apply(pkt, 'no_such_defaults.txt'), ...
                'ScapyML:DefaultsManager:FileNotFound');
        end

        function tcDefErr002a_noEqualsSignWarnsParseError(testCase)
            % TC-DEF-ERR-002 — a line with no '=' sign warns ParseError
            % and is skipped; other valid lines still apply.
            defFile = fullfile(testCase.TempFolder, 'defaults_noeq.txt');
            fid = fopen(defFile, 'w');
            fprintf(fid, 'this line has no equals sign\n');
            fprintf(fid, 'a = 11\n');
            fclose(fid);

            pkt = ScapyML.Packet('D2');
            testCase.verifyWarning(...
                @() ScapyML.DefaultsManager.apply(pkt, defFile), ...
                'ScapyML:DefaultsManager:ParseError');

            warnState = warning('off', 'ScapyML:DefaultsManager:ParseError');
            pkt2 = ScapyML.Packet('D2');
            pkt2 = ScapyML.DefaultsManager.apply(pkt2, defFile);
            warning(warnState);
            testCase.verifyEqual(pkt2.get('a'), 11, ...
                'A valid line following a malformed line must still apply');
        end

        function tcDefErr002b_twoEqualsSignsWarnsParseError(testCase)
            % TC-DEF-ERR-002 — a line with TWO '=' signs also warns
            % ParseError, since DefaultsManager (unlike ChecksumManager/
            % ConversionManager) uses a plain strsplit(line,'=') with no
            % first-'='-only special-casing; numel(parts) ends up 3, not 2.
            defFile = fullfile(testCase.TempFolder, 'defaults_twoeq.txt');
            fid = fopen(defFile, 'w');
            fprintf(fid, 'a = 1 = 2\n');
            fclose(fid);

            pkt = ScapyML.Packet('D2');
            testCase.verifyWarning(...
                @() ScapyML.DefaultsManager.apply(pkt, defFile), ...
                'ScapyML:DefaultsManager:ParseError');
        end

        function tcDefErr003_unparseableValueWarnsParseError(testCase)
            % TC-DEF-ERR-003 — a non-numeric value string warns
            % ParseError ("Cannot parse value") and the field is left
            % untouched.
            defFile = fullfile(testCase.TempFolder, 'defaults_badval.txt');
            fid = fopen(defFile, 'w');
            fprintf(fid, 'a = not_a_number\n');
            fclose(fid);

            pkt = ScapyML.Packet('D2');
            testCase.verifyWarning(...
                @() ScapyML.DefaultsManager.apply(pkt, defFile), ...
                'ScapyML:DefaultsManager:ParseError');

            warnState = warning('off', 'ScapyML:DefaultsManager:ParseError');
            pkt2 = ScapyML.Packet('D2');
            pkt2 = ScapyML.DefaultsManager.apply(pkt2, defFile);
            warning(warnState);
            testCase.verifyEqual(pkt2.get('a'), 0, ...
                'Field should remain at its prior (protocol default) value');
        end

        function tcDefErr004_fieldNotInPacketWarnsSetError(testCase)
            % TC-DEF-ERR-004 — a value line for a field name not present
            % in the packet warns SetError (caught from the underlying
            % pkt.set() UnknownField error) and loading continues for the
            % remaining lines.
            defFile = fullfile(testCase.TempFolder, 'defaults_nofield.txt');
            fid = fopen(defFile, 'w');
            fprintf(fid, 'nonexistent_field = 5\n');
            fprintf(fid, 'a = 77\n');
            fclose(fid);

            pkt = ScapyML.Packet('D2');
            testCase.verifyWarning(...
                @() ScapyML.DefaultsManager.apply(pkt, defFile), ...
                'ScapyML:DefaultsManager:SetError');

            warnState = warning('off', 'ScapyML:DefaultsManager:SetError');
            pkt2 = ScapyML.Packet('D2');
            pkt2 = ScapyML.DefaultsManager.apply(pkt2, defFile);
            warning(warnState);
            testCase.verifyEqual(pkt2.get('a'), 77, ...
                'A valid line after an unknown-field line must still apply');
        end

    end
end
