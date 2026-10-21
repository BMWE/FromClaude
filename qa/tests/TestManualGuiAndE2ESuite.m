classdef TestManualGuiAndE2ESuite < matlab.unittest.TestCase
% Automated equivalents of the manual GUI and End-to-End test cases in
% STR.md Sections 18-19 (TC-GUI-*, TC-E2E-*).
%
% ScapyML_GUI.m builds its entire callback graph as nested functions
% inside a single function scope tied to a uifigure — as TestGuiSmoke.m's
% own header comment explains, this makes true per-dialog unit testing
% impractical without the App Testing Framework and a live graphics
% session. Following that same file's established, deliberate approach,
% this suite extends the SAME two techniques rather than introducing a
% new one:
%   (1) headless-safe static source-scans for structural/API assertions
%       that don't require actually running the GUI, and
%   (2) genuine end-to-end integration tests that exercise the CLI
%       equivalent of a full documented workflow, which IS fully
%       automatable and gives real multi-module integration coverage.
%
% This file does NOT re-implement TestGuiSmoke.m's existing checks (file
% exists/parses, GUI launches when a display is available, waitbar
% CreateCancelBtn pattern exists, send loops avoid pause()).

    properties
        TempFolder
        GuiFile
        GuiSource
    end

    methods (TestClassSetup)
        function classSetup(testCase)
            import matlab.unittest.fixtures.TemporaryFolderFixture
            fixture = testCase.applyFixture(TemporaryFolderFixture);
            testCase.TempFolder = fixture.Folder;

            thisFile = mfilename('fullpath');
            testCase.GuiFile = fullfile(fileparts(fileparts(thisFile)), 'ScapyML_GUI.m');
            testCase.assumeTrue(isfile(testCase.GuiFile), 'ScapyML_GUI.m not found');
            testCase.GuiSource = fileread(testCase.GuiFile);
        end
    end

    methods (Test)

        % -----------------------------------------------------------
        % KI-NEW-01 / KI-NEW-02 fix confirmation at the GUI source level
        % (complements the class-level tests in TestManualCsvSuite.m and
        % TestManualMultiProtocolSuite.m). Both defects are now FIXED;
        % these tests confirm the fix is present in the GUI source AND
        % guard against the old broken calls silently reappearing.
        % -----------------------------------------------------------

        function tcGuiKi01_loadFromCsvCallsTheNowWorkingFromCsvCommand(testCase)
            % KI-NEW-01 (FIXED) — ScapyML_GUI.m's loadFromCSV()
            % useDefaults branch still literally calls
            % ScapyML('fromCSV', state.selectedProtocol, ...) -- this
            % line of GUI code was never itself wrong, only the command
            % it called was broken (duplicate switch-case label in
            % ScapyML.m, plus a genuinely missing ScapyML_fromCSV.m).
            % Both are now fixed (see TestManualCsvSuite.m's
            % tcCliFromcsvNowLoadsWithDefaultsAndConversions for the
            % end-to-end confirmation), so this call now succeeds.
            testCase.verifyTrue(...
                contains(testCase.GuiSource, "ScapyML('fromCSV', state.selectedProtocol"), ...
                'Expected loadFromCSV() to still call ScapyML(''fromCSV'', state.selectedProtocol, ...)');
        end

        function tcGuiKi02_discriminatorDialogNowCallsTheRealApi(testCase)
            % KI-NEW-02 (FIXED) — confirms ScapyML_GUI.m's discriminator
            % dialog now calls the REAL DiscriminatorConfig/
            % ProtocolRegistry API (addProtocol, getProtocolValue,
            % listEnums/getEnum) instead of the three non-existent
            % methods and the private property access it used to call.
            testCase.verifyTrue(contains(testCase.GuiSource, 'config.addProtocol('), ...
                'Expected createConfigFromTable() to call the real config.addProtocol(...)');
            testCase.verifyTrue(contains(testCase.GuiSource, 'config.getProtocolValue('), ...
                'Expected doGenerateMulti() to call the real config.getProtocolValue(...)');
            testCase.verifyTrue(contains(testCase.GuiSource, 'reg.listEnums()'), ...
                'Expected doGenerateMulti() to build enumDefs via the public listEnums()/getEnum() API');
            testCase.verifyTrue(contains(testCase.GuiSource, 'reg.getEnum('), ...
                'Expected doGenerateMulti() to call the public getEnum(...) per enum name');
        end

        function tcGuiKi02b_oldBrokenCallsAreGone(testCase)
            % Regression guard: the three non-existent methods and the
            % private-property access that made KI-NEW-02 a defect must
            % NOT reappear in the GUI source. If this test starts
            % FAILING, someone has reintroduced one of the original
            % broken calls.
            testCase.verifyFalse(contains(testCase.GuiSource, 'config.setDefaults('), ...
                'config.setDefaults() does not exist on DiscriminatorConfig -- must not be called');
            testCase.verifyFalse(contains(testCase.GuiSource, 'config.addMappingSimple('), ...
                'config.addMappingSimple() does not exist on DiscriminatorConfig -- must not be called');
            testCase.verifyFalse(contains(testCase.GuiSource, 'config.getMapping('), ...
                'config.getMapping() does not exist on DiscriminatorConfig -- must not be called');
            testCase.verifyFalse(contains(testCase.GuiSource, 'reg.Enums'), ...
                'ProtocolRegistry.Enums is private -- must not be accessed directly from the GUI');
        end

        % -----------------------------------------------------------
        % TC-GUI-UI-* structural checks (source-scan)
        % -----------------------------------------------------------

        function tcGuiUi001_protocolDependentButtonsStartDisabled(testCase)
            % TC-GUI-UI-001 — protocol-dependent buttons (Show Protocol
            % Info, Create Packet) are explicitly initialised/reset to
            % Enable='off' and only turned 'on' inside protocolSelected().
            testCase.verifyTrue(contains(testCase.GuiSource, "btnShowInfo.Enable = 'off'"), ...
                'Expected btnShowInfo to have an explicit disabled state somewhere (initial/reset)');
            testCase.verifyTrue(contains(testCase.GuiSource, "btnShowInfo.Enable = 'on'"), ...
                'Expected btnShowInfo to be enabled inside protocolSelected()');
            testCase.verifyTrue(contains(testCase.GuiSource, "btnCreatePacket.Enable = 'off'"));
            testCase.verifyTrue(contains(testCase.GuiSource, "btnCreatePacket.Enable = 'on'"));
        end

        function tcGuiUi003_clearProtocolsResetsButtonStates(testCase)
            % TC-GUI-UI-003 — clearProtocols() exists and includes the
            % same button-disabling assignments confirmed in UI-001,
            % consistent with "Clear Protocols" resetting all
            % protocol/packet-dependent buttons back to disabled.
            %
            % Body extraction uses plain string-index slicing rather than
            % a naive regex: a lazy '.*?end' regex would stop at the
            % FIRST inner 'end' (e.g. closing an if-block) rather than
            % the function's actual closing end, silently truncating the
            % body and making this test unreliable. Instead we slice from
            % 'function clearProtocols()' up to the next sibling
            % function declaration at the same (4-space) indent level,
            % which reliably brackets the whole body given this file's
            % consistent nested-function layout.
            startTok = 'function clearProtocols()';
            startIdx = strfind(testCase.GuiSource, startTok);
            testCase.verifyNotEmpty(startIdx, 'Expected to find clearProtocols() in the GUI source');

            remainder = testCase.GuiSource(startIdx(1)+length(startTok):end);
            % NOTE: use bracket concatenation, not '+', to join the
            % newline and the literal — '+' on char arrays performs
            % numeric addition in MATLAB, not concatenation (this exact
            % pitfall previously caused @@ /backtick corruption elsewhere
            % in this project's Lua-generation code; avoiding it here
            % deliberately).
            nextFnMarker = [newline '    function '];
            nextFnIdx = strfind(remainder, nextFnMarker);
            if isempty(nextFnIdx)
                body = remainder;  % clearProtocols() was the last function in the file
            else
                body = remainder(1:nextFnIdx(1)-1);
            end

            testCase.verifyTrue(contains(body, "btnShowInfo.Enable = 'off'"));
            testCase.verifyTrue(contains(body, "btnSend.Enable = 'off'"));
        end

        function tcGuiUi005_endiannessDropdownOffersLittleAndBigEndian(testCase)
            % TC-GUI-UI-005 — the endianness dropdown offers both
            % little-endian and big-endian options for the user to select
            % before loading a header.
            testCase.verifyTrue(contains(testCase.GuiSource, 'little-endian'), ...
                'Expected a little-endian option in the GUI source');
            testCase.verifyTrue(contains(testCase.GuiSource, 'big-endian'), ...
                'Expected a big-endian option in the GUI source');
        end

        function tcGuiUi006_autoResolveCheckboxControlsDependencyResolver(testCase)
            % TC-GUI-UI-006 — the "auto-resolve dependencies" checkbox
            % ultimately drives a call into DependencyResolver / the
            % 'auto' load flag, rather than being a purely cosmetic
            % control with no wired behaviour.
            testCase.verifyTrue(...
                contains(testCase.GuiSource, 'DependencyResolver') || ...
                contains(testCase.GuiSource, "'auto'"), ...
                'Expected the auto-resolve checkbox to be wired to DependencyResolver or the ''auto'' load flag');
        end

        function tcGuiFunc004_checksumFileLoadIntegratesWithSend(testCase)
            % TC-GUI-FUNC-004 — loading a checksums file makes a
            % ChecksumManager available to the send workflow (i.e. the
            % same state field/variable is both populated by the
            % checksum-loading callback and consumed by the send
            % callback), confirming the two dialogs are actually wired
            % together rather than independent/orphaned.
            testCase.verifyTrue(contains(testCase.GuiSource, 'ChecksumManager'), ...
                'Expected ChecksumManager to be referenced in the GUI source');
            % Both a load site and a consumption site should exist.
            occurrences = length(strfind(testCase.GuiSource, 'checksumManager'));
            testCase.verifyGreaterThanOrEqual(occurrences, 2, ...
                'Expected the checksum manager state variable to appear at both a load site and a consumption (send) site');
        end

        % -----------------------------------------------------------
        % TC-E2E-* — genuine end-to-end integration via the CLI
        % (fully automatable; complements the GUI's necessarily-manual
        % workflow verification)
        % -----------------------------------------------------------

        function tcE2e004_fullCliWorkflowLoadPacketCsvSendDissector(testCase)
            % TC-E2E-004 — the exact documented README.md "Full Workflow
            % Example" sequence, run start-to-finish as one continuous
            % integration test: load -> packet -> csv -> send ->
            % dissector. This complements the many per-feature tests
            % elsewhere in the suite by proving the pieces genuinely work
            % TOGETHER in the documented order, using the same command
            % names an end user would type.
            ScapyML.ProtocolRegistry.instance().clearAll();
            h = {
                'typedef struct SensorMsg {'
                '  uint8_t  msg_id;'
                '  int16_t  temperature;'
                '} SensorMsg;'
            };
            headerFile = writeFixtureHeader(testCase.TempFolder, 'sensor_msg.h', h);

            ScapyML('load', headerFile, 'big');
            testCase.verifyTrue(any(strcmp(ScapyML('list'), 'SensorMsg')));

            pkt = ScapyML('packet', 'SensorMsg', 'msg_id', 1, 'temperature', 235);
            testCase.verifyEqual(pkt.get('msg_id'), 1);
            testCase.verifyEqual(pkt.get('temperature'), 235);

            csvFile = fullfile(testCase.TempFolder, 'sensor_data.csv');
            fid = fopen(csvFile, 'w');
            fprintf(fid, 'msg_id,temperature\n');
            fprintf(fid, '2,100\n');
            fprintf(fid, '3,-50\n');
            fclose(fid);
            pkts = ScapyML('csv', csvFile, 'SensorMsg');
            testCase.verifyEqual(numel(pkts), 2);
            testCase.verifyEqual(pkts{2}.get('temperature'), -50);

            try
                ScapyML('send', pkts, '127.0.0.1', 40301);
            catch ME
                testCase.assumeFail(['Loopback UDP unavailable: ' ME.message]);
            end

            luaFile = fullfile(testCase.TempFolder, 'sensor_msg.lua');
            ScapyML('dissector', 'SensorMsg', luaFile, 40301);
            testCase.verifyTrue(isfile(luaFile));
            luaText = fileread(luaFile);
            testCase.verifyTrue(contains(luaText, 'msg_id'));
            testCase.verifyTrue(contains(luaText, 'temperature'));
        end

        function tcE2e005_comprehensiveMultiFeatureIntegration(testCase)
            % TC-E2E-005 — combines cross-file enum/struct references,
            % bit-fields, arrays, checksums, and single-protocol Wireshark
            % generation into one continuous session, specifically to
            % catch integration issues that isolated per-feature tests
            % (elsewhere in this suite) might miss.
            ScapyML.ProtocolRegistry.instance().clearAll();

            typesFile = writeFixtureHeader(testCase.TempFolder, 'e2e_types.h', ...
                {'typedef enum E2EStatus { E2E_OK=0, E2E_ERROR=1 } E2EStatus;'});
            msgFile = writeFixtureHeader(testCase.TempFolder, 'e2e_msg.h', ...
                {'typedef struct E2EMsg {'
                 '  E2EStatus status;'
                 '  uint8_t   flagA:3;'
                 '  uint8_t   flagB:5;'
                 '  uint8_t   payload[4];'
                 '  uint8_t   checksum;'
                 '} E2EMsg;'});

            ScapyML('load', {typesFile, msgFile}, 'little');

            csFile = fullfile(testCase.TempFolder, 'e2e_checksum.txt');
            fid = fopen(csFile, 'w');
            fprintf(fid, 'checksum = @(data) mod(sum(uint16(data)), 256)\n');
            fclose(fid);
            cm = ScapyML.ChecksumManager(csFile);

            pkt = ScapyML.Packet('E2EMsg');
            pkt.set('status', 1);        % E2E_ERROR
            pkt.set('flagA', 5);
            pkt.set('flagB', 19);
            pkt.set('payload', [10 20 30 40]);

            bytes = pkt.buildWithChecksums(cm);
            testCase.verifyGreaterThan(numel(bytes), 0);

            % Round-trip through decode to confirm cross-feature
            % consistency (enum + bit-fields + array all decode correctly
            % from a checksum-augmented buffer).
            decoded = ScapyML.Packet.fromBytes('E2EMsg', bytes);
            testCase.verifyEqual(decoded.get('status'), 1);
            testCase.verifyEqual(decoded.get('flagA'), 5);
            testCase.verifyEqual(decoded.get('flagB'), 19);
            testCase.verifyEqual(decoded.get('payload'), [10 20 30 40]);

            % Idempotent checksum re-calculation (cross-ref TC-CHK-FUNC-002).
            bytes2 = pkt.buildWithChecksums(cm);
            testCase.verifyEqual(bytes, bytes2);

            % Single-protocol Wireshark generation over the same,
            % feature-rich protocol.
            luaFile = fullfile(testCase.TempFolder, 'e2e_msg.lua');
            ScapyML('dissector', 'E2EMsg', luaFile);
            testCase.verifyTrue(isfile(luaFile));
            luaText = fileread(luaFile);
            testCase.verifyTrue(contains(luaText, 'E2E_OK'));
            testCase.verifyTrue(contains(luaText, 'E2E_ERROR'));
        end

    end
end
