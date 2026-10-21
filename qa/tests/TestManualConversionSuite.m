classdef TestManualConversionSuite < matlab.unittest.TestCase
% Automated equivalents of the manual ConversionManager test cases in
% STR.md Section 7 (TC-CONV-*). This file intentionally does NOT
% re-implement cases already covered by TestConversionManager.m (empty
% manager pass-through, simple formula load/apply, unrelated-field
% pass-through, == operator parsing, single-application guard,
% undefined-function conversion error).
%
% NOTE ON AN EXISTING TEST DISCREPANCY (found while writing this file):
% TestConversionManager.m's 'missingFileProducesEmptyManagerNotError' test
% asserts verifyWarningFree() for a missing conversion file. Reading
% +ScapyML/ConversionManager.m directly shows the constructor DOES call
% warning('ScapyML:ConversionManager:FileNotFound', ...) when the file
% does not exist (see line ~44) — the same discrepancy pattern found in
% TestChecksumManager.m. TC-CONV-ERR-001 below tests the real,
% source-confirmed behaviour instead of repeating that assumption.

    properties
        TempFolder
    end

    methods (TestClassSetup)
        function classSetup(testCase)
            import matlab.unittest.fixtures.TemporaryFolderFixture
            fixture = testCase.applyFixture(TemporaryFolderFixture);
            testCase.TempFolder = fixture.Folder;
        end
    end

    methods (Test)

        function tcConvFunc003_accessors(testCase)
            % TC-CONV-FUNC-003 — hasConversion()/listConversions()/
            % conversionCount() accessors with three defined conversions.
            convFile = fullfile(testCase.TempFolder, 'conv_accessors.txt');
            fid = fopen(convFile, 'w');
            fprintf(fid, 'azimuth = @(x) round(x / 360 * 65536)\n');
            fprintf(fid, 'elevation = @(x) round((x + 90) / 180 * 65536)\n');
            fprintf(fid, 'temperature = @(x) round((x + 40) * 10)\n');
            fclose(fid);

            cm = ScapyML.ConversionManager(convFile);
            testCase.verifyEqual(cm.conversionCount(), 3);
            names = cm.listConversions();
            testCase.verifyTrue(any(strcmp(names, 'azimuth')));
            testCase.verifyTrue(any(strcmp(names, 'elevation')));
            testCase.verifyTrue(any(strcmp(names, 'temperature')));
            testCase.verifyTrue(cm.hasConversion('azimuth'));
            testCase.verifyFalse(cm.hasConversion('pressure'));
        end

        function tcConvFunc004_documentedWorkedExamples(testCase)
            % TC-CONV-FUNC-004 — elevation/temperature/pressure formulas
            % (from the class's own documented example set), hand-verified
            % against the worked examples in STR.md / the class docstring.
            convFile = fullfile(testCase.TempFolder, 'conv_worked.txt');
            fid = fopen(convFile, 'w');
            fprintf(fid, 'elevation = @(x) round((x + 90) / 180 * 65536)\n');
            fprintf(fid, 'temperature = @(x) round((x + 40) * 10)\n');
            fprintf(fid, 'pressure = @(x) round((x - 300) / 800 * 65536)\n');
            fclose(fid);
            cm = ScapyML.ConversionManager(convFile);

            % Temperature: 25.5 C -> round((25.5+40)*10) = 655
            testCase.verifyEqual(cm.convert('temperature', 25.5), 655);

            % Elevation: 0 deg (level) -> round(90/180*65536) = 32768
            testCase.verifyEqual(cm.convert('elevation', 0), 32768);

            % Pressure: 1100 hPa (max of documented range) ->
            % round((1100-300)/800*65536) = 65536
            testCase.verifyEqual(cm.convert('pressure', 1100), 65536);
        end

        function tcConvErr001_missingFileWarnsFileNotFound(testCase)
            % TC-CONV-ERR-001 — a missing conversion file must produce
            % warning ScapyML:ConversionManager:FileNotFound and yield an
            % empty (but usable) manager. Confirmed against the actual
            % constructor source (see class-level note above).
            testCase.verifyWarning(...
                @() ScapyML.ConversionManager('does_not_exist_ki01.txt'), ...
                'ScapyML:ConversionManager:FileNotFound');

            warnState = warning('off', 'ScapyML:ConversionManager:FileNotFound');
            cm = ScapyML.ConversionManager('does_not_exist_ki01.txt');
            warning(warnState);
            testCase.verifyEqual(cm.conversionCount(), 0);
            testCase.verifyEqual(cm.convert('anything', 99), 99, ...
                'An empty manager (from a missing file) must still pass values through unchanged');
        end

        function tcConvErr003a_malformedLineNoEqualsSign(testCase)
            % TC-CONV-ERR-003 — a line with no '=' sign warns ParseError,
            % other valid lines still load.
            convFile = fullfile(testCase.TempFolder, 'conv_malformed.txt');
            fid = fopen(convFile, 'w');
            fprintf(fid, 'not a valid line at all\n');
            fprintf(fid, 'goodOne = @(x) x * 3\n');
            fclose(fid);

            testCase.verifyWarning(...
                @() ScapyML.ConversionManager(convFile), ...
                'ScapyML:ConversionManager:ParseError');

            warnState = warning('off', 'ScapyML:ConversionManager:ParseError');
            cm = ScapyML.ConversionManager(convFile);
            warning(warnState);
            testCase.verifyTrue(cm.hasConversion('goodOne'));
            testCase.verifyEqual(cm.convert('goodOne', 4), 12);
        end

        function tcConvErr003b_rhsNotFunctionHandle(testCase)
            % TC-CONV-ERR-003 — right-hand side that evaluates to a plain
            % number (not a function handle) warns NotFunction and is
            % skipped.
            convFile = fullfile(testCase.TempFolder, 'conv_notfunc.txt');
            fid = fopen(convFile, 'w');
            fprintf(fid, 'scale = 10\n');
            fclose(fid);

            testCase.verifyWarning(...
                @() ScapyML.ConversionManager(convFile), ...
                'ScapyML:ConversionManager:NotFunction');

            warnState = warning('off', 'ScapyML:ConversionManager:NotFunction');
            cm = ScapyML.ConversionManager(convFile);
            warning(warnState);
            testCase.verifyFalse(cm.hasConversion('scale'));
        end

    end
end
