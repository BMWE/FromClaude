classdef TestManualCsvSuite < matlab.unittest.TestCase
% Automated equivalents of the manual CSV-loading test cases in STR.md
% Section 9 (TC-CSV-*). This file intentionally does NOT re-implement
% cases already covered by TestBulkCsvLoad.m (fromValuesStruct bulk
% constructor behaviour, override-known-fields-only, many-row bulk load,
% single-application conversion guard). Those tests exercise the GUI's
% underlying building blocks; THIS file exercises the actual file-reading
% entry points: ScapyML.CsvLoader.load (Path A) and the CLI dispatcher's
% 'csv'/'fromcsv' commands.
%
% *** KI-NEW-01 STATUS: FIXED ***
%
% STR.md originally documented that ScapyML('fromCSV', ...) failed, and
% root-caused it (after correction) to TWO independent problems, both now
% fixed:
%   1. ScapyML.m had TWO switch/case blocks both listing 'fromcsv' as a
%      matching label. MATLAB always runs the FIRST match, so the
%      dedicated fromCSV/defaults/conversions block (the second one) was
%      dead code -- calling ScapyML('fromCSV', ...) always misfired into
%      the plain 'csv' loader with swapped arguments, producing a
%      confusing "CSV file not found: <protocol name>" error. FIX:
%      'fromcsv' removed from the first case's alias list.
%   2. ScapyML_fromCSV.m -- the function the second block calls -- was
%      genuinely missing from the package entirely. FIX: implemented,
%      modeled on the GUI's own proven vectorized CSV loader with
%      defaults-file support added.
%
% tcCliFromcsvNowLoadsWithDefaultsAndConversions and
% tcCliFromcsvAliasesAlsoWork below confirm both fixes together: the
% documented 'fromCSV' spelling now reaches the real implementation, and
% the previously-broken 'csv2packets'/'autocsv' aliases now work too.

    properties
        TempFolder
    end

    methods (TestClassSetup)
        function classSetup(testCase)
            import matlab.unittest.fixtures.TemporaryFolderFixture
            fixture = testCase.applyFixture(TemporaryFolderFixture);
            testCase.TempFolder = fixture.Folder;

            h = {'typedef struct CsvRow { uint8_t id; uint16_t temperature; uint32_t big; uint64_t huge; } CsvRow;'};
            f = writeFixtureHeader(testCase.TempFolder, 'csvrow.h', h);
            ScapyML.ProtocolRegistry.instance().clearAll();
            ScapyML.HeaderParser.parseFile(f, 'little');
        end
    end

    methods (Test)

        function tcCsvFunc001_wellFormedCsvAllColumnsMatch(testCase)
            % TC-CSV-FUNC-001 — Path A: ScapyML.CsvLoader.load with a
            % well-formed CSV matching protocol field columns.
            csvFile = fullfile(testCase.TempFolder, 'wellformed.csv');
            fid = fopen(csvFile, 'w');
            fprintf(fid, 'id,temperature\n');
            fprintf(fid, '1,100\n');
            fprintf(fid, '2,200\n');
            fprintf(fid, '3,300\n');
            fclose(fid);

            pkts = ScapyML.CsvLoader.load(csvFile, 'CsvRow');
            testCase.verifyEqual(numel(pkts), 3);
            testCase.verifyEqual(pkts{1}.get('id'), 1);
            testCase.verifyEqual(pkts{1}.get('temperature'), 100);
            testCase.verifyEqual(pkts{3}.get('id'), 3);
            testCase.verifyEqual(pkts{3}.get('temperature'), 300);
        end

        function tcCsvFunc002_extraColumnsIgnored(testCase)
            % TC-CSV-FUNC-002 — an extra column not present in the
            % protocol is silently ignored; other columns still load.
            csvFile = fullfile(testCase.TempFolder, 'extracol.csv');
            fid = fopen(csvFile, 'w');
            fprintf(fid, 'id,temperature,notes\n');
            fprintf(fid, '5,50,some free text\n');
            fclose(fid);

            pkts = ScapyML.CsvLoader.load(csvFile, 'CsvRow');
            testCase.verifyEqual(numel(pkts), 1);
            testCase.verifyEqual(pkts{1}.get('id'), 5);
            testCase.verifyEqual(pkts{1}.get('temperature'), 50);
        end

        function tcCsvFunc003_missingColumnKeepsProtocolDefault(testCase)
            % TC-CSV-FUNC-003 — a protocol field entirely absent from the
            % CSV header stays at its protocol default (0).
            csvFile = fullfile(testCase.TempFolder, 'missingcol.csv');
            fid = fopen(csvFile, 'w');
            fprintf(fid, 'id\n');
            fprintf(fid, '9\n');
            fclose(fid);

            pkts = ScapyML.CsvLoader.load(csvFile, 'CsvRow');
            testCase.verifyEqual(pkts{1}.get('id'), 9);
            testCase.verifyEqual(pkts{1}.get('temperature'), 0);
        end

        function tcCsvFunc004_emptyCellKeepsDefaultOtherFieldsStillLoad(testCase)
            % TC-CSV-FUNC-004 — an empty cell in a data row leaves that
            % field at its default while other fields on the same row
            % still load correctly.
            csvFile = fullfile(testCase.TempFolder, 'emptycell.csv');
            fid = fopen(csvFile, 'w');
            fprintf(fid, 'id,temperature\n');
            fprintf(fid, '7,\n');
            fclose(fid);

            pkts = ScapyML.CsvLoader.load(csvFile, 'CsvRow');
            testCase.verifyEqual(pkts{1}.get('id'), 7);
            testCase.verifyEqual(pkts{1}.get('temperature'), 0);
        end

        function tcCsvFunc005_hexNotationVaryingDigitCountsAutoSize(testCase)
            % TC-CSV-FUNC-005 — hex-notation CSV values of varying digit
            % counts auto-size to uint8/16/32/64 and Packet.set() accepts
            % each without an out-of-range warning.
            csvFile = fullfile(testCase.TempFolder, 'hexvals.csv');
            fid = fopen(csvFile, 'w');
            fprintf(fid, 'id,temperature,big,huge\n');
            fprintf(fid, '0xFF,0xFFFF,0xFFFFFFFF,0xFFFFFFFFFFFFFFFF\n');
            fclose(fid);

            testCase.verifyWarningFree(@() ScapyML.CsvLoader.load(csvFile, 'CsvRow'));
            pkts = ScapyML.CsvLoader.load(csvFile, 'CsvRow');
            testCase.verifyEqual(double(pkts{1}.get('id')), 255);
            testCase.verifyEqual(double(pkts{1}.get('temperature')), 65535);
            testCase.verifyEqual(double(pkts{1}.get('big')), 4294967295);
            testCase.verifyEqual(double(pkts{1}.get('huge')), 18446744073709551615);
        end

        function tcCsvFunc006_quotedFieldContainingCommaDoesNotSplitOrCrash(testCase)
            % TC-CSV-FUNC-006 — a quoted CSV field containing a comma is
            % treated as one field (not split at the internal comma), and
            % since it is not purely numeric it is silently skipped rather
            % than crashing the loader.
            csvFile = fullfile(testCase.TempFolder, 'quoted.csv');
            fid = fopen(csvFile, 'w');
            fprintf(fid, 'id,temperature\n');
            fprintf(fid, '"1,2",42\n');
            fclose(fid);

            pkts = [];
            testCase.verifyWarningFree(...
                @() ScapyML.CsvLoader.load(csvFile, 'CsvRow'));
            pkts = ScapyML.CsvLoader.load(csvFile, 'CsvRow'); %#ok<NASGU>
            testCase.verifyEqual(numel(pkts), 1);
            % "1,2" is not purely numeric -> parseNum returns NaN -> id
            % field is skipped and stays at its default (0); temperature
            % (a distinct, purely-numeric column) still loads correctly.
            testCase.verifyEqual(pkts{1}.get('id'), 0);
            testCase.verifyEqual(pkts{1}.get('temperature'), 42);
        end

        function tcCsvNeg001_missingCsvFileErrors(testCase)
            % TC-CSV-NEG-001 — a non-existent CSV path errors clearly.
            testCase.verifyError(...
                @() ScapyML.CsvLoader.load('does_not_exist.csv', 'CsvRow'), ...
                'ScapyML:CsvLoader:FileNotFound');
        end

        function tcCsvNeg002_emptyCsvFileReturnsEmptyCell(testCase)
            % TC-CSV-NEG-002 — a zero-byte CSV file returns {} without
            % error.
            csvFile = fullfile(testCase.TempFolder, 'empty.csv');
            fid = fopen(csvFile, 'w');
            fclose(fid);

            pkts = ScapyML.CsvLoader.load(csvFile, 'CsvRow');
            testCase.verifyEmpty(pkts);
        end

        function tcCsvNeg003_headerOnlyReturnsEmptyCell(testCase)
            % TC-CSV-NEG-003 — a CSV with only a header row (no data rows)
            % returns {}.
            csvFile = fullfile(testCase.TempFolder, 'headeronly.csv');
            fid = fopen(csvFile, 'w');
            fprintf(fid, 'id,temperature\n');
            fclose(fid);

            pkts = ScapyML.CsvLoader.load(csvFile, 'CsvRow');
            testCase.verifyEmpty(pkts);
        end

        function tcCliFunc004_csvCommandWrapperMatchesDirectCsvLoader(testCase)
            % TC-CLI-FUNC-004 — the CLI 'csv' command is a thin wrapper
            % around ScapyML.CsvLoader.load with the SAME (csvFile,
            % protoName) argument order.
            csvFile = fullfile(testCase.TempFolder, 'cli_csv.csv');
            fid = fopen(csvFile, 'w');
            fprintf(fid, 'id,temperature\n');
            fprintf(fid, '11,111\n');
            fclose(fid);

            pkts = ScapyML('csv', csvFile, 'CsvRow');
            testCase.verifyEqual(numel(pkts), 1);
            testCase.verifyEqual(pkts{1}.get('id'), 11);
            testCase.verifyEqual(pkts{1}.get('temperature'), 111);
        end

        function tcCliFromcsvNowLoadsWithDefaultsAndConversions(testCase)
            % TC-CSV-FUNC-007 (KI-NEW-01 FIX CONFIRMATION) — the
            % documented 'fromCSV' command now reaches the real
            % implementation and correctly applies BOTH defaults and
            % conversions: 'temperature' has a conversion defined and is
            % present in the CSV (converted); 'id' has a default and is
            % NOT present in the CSV (default should survive untouched).
            defFile = fullfile(testCase.TempFolder, 'fromcsv_fix_defaults.txt');
            fid = fopen(defFile, 'w');
            fprintf(fid, 'id = 99\n');
            fclose(fid);

            convFile = fullfile(testCase.TempFolder, 'fromcsv_fix_conversions.txt');
            fid = fopen(convFile, 'w');
            fprintf(fid, 'temperature = @(x) round(x * 10)\n');
            fclose(fid);

            csvFile = fullfile(testCase.TempFolder, 'fromcsv_fix_data.csv');
            fid = fopen(csvFile, 'w');
            fprintf(fid, 'temperature\n');
            fprintf(fid, '25.5\n');
            fprintf(fid, '30.0\n');
            fclose(fid);

            pkts = ScapyML('fromCSV', 'CsvRow', csvFile, defFile, convFile);

            testCase.verifyEqual(numel(pkts), 2);
            % 'id' is not a CSV column -> the defaults-file value (99)
            % should survive, confirming defaults ARE applied.
            testCase.verifyEqual(pkts{1}.get('id'), 99);
            testCase.verifyEqual(pkts{2}.get('id'), 99);
            % 'temperature' IS a CSV column with a conversion defined ->
            % the converted (wire) value should be stored, confirming
            % conversions ARE applied.
            testCase.verifyEqual(double(pkts{1}.get('temperature')), 255);
            testCase.verifyEqual(double(pkts{2}.get('temperature')), 300);
        end

        function tcCliFromcsvAliasesAlsoWork(testCase)
            % KI-NEW-01 FIX CONFIRMATION — the 'csv2packets'/'autocsv'
            % aliases, which previously hit the genuinely-missing
            % ScapyML_fromCSV function ("Undefined function" error), now
            % also work correctly since that function has been
            % implemented.
            csvFile = fullfile(testCase.TempFolder, 'fromcsv_alias_data.csv');
            fid = fopen(csvFile, 'w');
            fprintf(fid, 'id,temperature\n');
            fprintf(fid, '5,50\n');
            fclose(fid);

            pkts = ScapyML('csv2packets', 'CsvRow', csvFile);
            testCase.verifyEqual(numel(pkts), 1);
            testCase.verifyEqual(pkts{1}.get('id'), 5);
            testCase.verifyEqual(pkts{1}.get('temperature'), 50);
        end

        function tcCliFromcsvMissingDefaultsFileWarnsAndContinues(testCase)
            % KI-NEW-01 FIX — ScapyML_fromCSV's own defensive handling: a
            % defaults file path that doesn't exist should warn and
            % proceed without defaults, not crash the whole load.
            csvFile = fullfile(testCase.TempFolder, 'fromcsv_nodefaults.csv');
            fid = fopen(csvFile, 'w');
            fprintf(fid, 'id\n');
            fprintf(fid, '7\n');
            fclose(fid);

            testCase.verifyWarning(...
                @() ScapyML('fromCSV', 'CsvRow', csvFile, 'no_such_defaults_xyz.txt'), ...
                'ScapyML:fromCSV:DefaultsFileNotFound');

            warnState = warning('off', 'ScapyML:fromCSV:DefaultsFileNotFound');
            pkts = ScapyML('fromCSV', 'CsvRow', csvFile, 'no_such_defaults_xyz.txt');
            warning(warnState);
            testCase.verifyEqual(pkts{1}.get('id'), 7);
        end

    end
end
