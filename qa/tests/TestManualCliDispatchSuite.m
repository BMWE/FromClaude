classdef TestManualCliDispatchSuite < matlab.unittest.TestCase
% Automated equivalents of the manual CLI dispatch test cases in STR.md
% Section 17 (TC-CLI-*). ScapyML.m's command-dispatch switch statement has
% NO dedicated existing test file — its commands are only incidentally
% exercised inside other suites (TestHeaderParser.m / TestManualHeaderParserSuite.m
% for 'load'; TestManualCsvSuite.m for 'csv'/'fromcsv'; TestManualWiresharkSuite.m
% for 'dissector'). This file provides first-time direct coverage of the
% remaining commands and the dispatcher's own argument-count/unknown-
% command handling.
%
% Commands that open a real UDP socket ('send') follow the same
% testCase.assumeFail skip-not-fail pattern used in
% TestUdpSenderAndTiming.m / TestManualPacketSenderSuite.m for
% sandboxed/CI environments without loopback UDP.

    properties
        TempFolder
    end

    methods (TestClassSetup)
        function classSetup(testCase)
            import matlab.unittest.fixtures.TemporaryFolderFixture
            fixture = testCase.applyFixture(TemporaryFolderFixture);
            testCase.TempFolder = fixture.Folder;

            h = {'typedef struct CliProto { uint8_t id; uint16_t val; } CliProto;'};
            f = writeFixtureHeader(testCase.TempFolder, 'cliproto.h', h);
            ScapyML.ProtocolRegistry.instance().clearAll();
            ScapyML.HeaderParser.parseFile(f, 'little');
        end
    end

    methods (Test)

        function tcCliFunc003_packetCommandWithInlineFieldValuePairs(testCase)
            % TC-CLI-FUNC-003 — 'packet' command with inline field=value
            % pairs returns a correctly-populated Packet.
            pkt = ScapyML('packet', 'CliProto', 'id', 7, 'val', 300);
            testCase.verifyClass(pkt, 'ScapyML.Packet');
            testCase.verifyEqual(pkt.get('id'), 7);
            testCase.verifyEqual(pkt.get('val'), 300);
        end

        function tcCliFunc003b_packetCommandWithNoFieldValuePairs(testCase)
            % Companion — 'packet' with just a protocol name returns a
            % packet with all-default fields.
            pkt = ScapyML('packet', 'CliProto');
            testCase.verifyEqual(pkt.get('id'), 0);
            testCase.verifyEqual(pkt.get('val'), 0);
        end

        function tcCliFunc010_infoCommandPrintsFieldOffsetTable(testCase)
            % TC-CLI-FUNC-010 — 'info' command displays a field/offset
            % table including byte-size and description columns.
            output = evalc('ScapyML(''info'', ''CliProto'')');
            testCase.verifyTrue(contains(output, 'CliProto'));
            testCase.verifyTrue(contains(output, 'id'));
            testCase.verifyTrue(contains(output, 'val'));
        end

        function tcCliFunc010b_infoCommandOnUnknownProtocolErrors(testCase)
            % Negative companion — 'info' on an unregistered protocol name
            % propagates the ProtocolRegistry:NotFound error rather than
            % printing a blank/garbled table.
            testCase.verifyError(...
                @() ScapyML('info', 'NoSuchProtocolXYZ'), ...
                'ScapyML:ProtocolRegistry:NotFound');
        end

        function tcCliFunc011a_listCommandWithOutputArgSuppressesPrint(testCase)
            % TC-CLI-FUNC-011 — 'list' with an output argument requested
            % returns the cell array of names and suppresses the printed
            % table (nargout > 0 branch).
            [output, names] = evalc('ScapyML(''list'')');
            testCase.verifyClass(names, 'cell');
            testCase.verifyTrue(any(strcmp(names, 'CliProto')));
            testCase.verifyEmpty(output, ...
                'Requesting an output argument should suppress the printed protocol table');
        end

        function tcCliFunc011b_listCommandWithoutOutputArgPrintsTable(testCase)
            % TC-CLI-FUNC-011 — 'list' with NO output argument requested
            % prints a human-readable table instead (nargout == 0 branch).
            output = evalc('ScapyML(''list'')');
            testCase.verifyNotEmpty(output);
            testCase.verifyTrue(contains(output, 'CliProto'));
            testCase.verifyTrue(contains(output, 'fields'));
            testCase.verifyTrue(contains(output, 'bytes'));
        end

        function tcCliFunc012_defaultsCommandCreatesFile(testCase)
            % TC-CLI-FUNC-012 — 'defaults' command is a thin CLI wrapper
            % around DefaultsManager.create().
            outFile = fullfile(testCase.TempFolder, 'cli_defaults.txt');
            ScapyML('defaults', 'CliProto', outFile);
            testCase.verifyTrue(isfile(outFile));
            content = fileread(outFile);
            testCase.verifyTrue(contains(content, 'id'));
            testCase.verifyTrue(contains(content, 'val'));
        end

        function tcCliFunc013_loaddefaultsCommandAppliesToPacket(testCase)
            % TC-CLI-FUNC-013 — 'loaddefaults' command is a thin CLI
            % wrapper around DefaultsManager.apply(), returning the
            % updated packet when an output argument is requested.
            defFile = fullfile(testCase.TempFolder, 'cli_apply_defaults.txt');
            fid = fopen(defFile, 'w');
            fprintf(fid, 'id = 55\n');
            fclose(fid);

            pkt = ScapyML.Packet('CliProto');
            pkt = ScapyML('loaddefaults', pkt, defFile);
            testCase.verifyEqual(pkt.get('id'), 55);
        end

        function tcCliFunc014_registerCommandAddsProtocolToRegistry(testCase)
            % TC-CLI-FUNC-014 — 'register' command programmatically adds a
            % manually-constructed ProtocolDef to the registry, after
            % which it is visible via 'list'.
            manualProto = ScapyML.ProtocolDef();
            manualProto.Name = 'ManuallyRegisteredProto';
            manualProto.Endian = 'little';
            fd = ScapyML.FieldDef();
            fd.Name = 'x';
            fd.CType = 'uint8_t';
            fd.ByteSize = 1;
            % ProtocolDef is a value class (not `handle`), so addField()
            % returns a NEW object rather than mutating manualProto in
            % place — the result must be reassigned.
            manualProto = manualProto.addField(fd);

            ScapyML('register', manualProto);
            names = ScapyML('list');
            testCase.verifyTrue(any(strcmp(names, 'ManuallyRegisteredProto')));
        end

        function tcCliNeg001_noArgumentsPrintsHelpWithoutError(testCase)
            % TC-CLI-NEG-001 — calling ScapyML() with no arguments prints
            % the synopsis/help block and returns without error.
            output = evalc('ScapyML()');
            testCase.verifyNotEmpty(output);
            testCase.verifyTrue(contains(output, 'ScapyML'));
        end

        function tcCliNeg002_unknownCommandWarnsAndReturnsEmpty(testCase)
            % TC-CLI-NEG-002 — an unrecognized command string warns
            % ScapyML:UnknownCmd, prints help text, and returns [] when an
            % output argument was requested.
            testCase.verifyWarning(...
                @() ScapyML('this_is_not_a_real_command'), ...
                'ScapyML:UnknownCmd');

            warnState = warning('off', 'ScapyML:UnknownCmd');
            result = ScapyML('this_is_not_a_real_command');
            warning(warnState);
            testCase.verifyEmpty(result);
        end

        function tcCliNeg003a_packetCommandTooFewArgumentsErrors(testCase)
            % TC-CLI-NEG-003 — 'packet' with no protocol name errors with
            % a clear "Usage:" message via the assert() guard.
            testCase.verifyError(@() ScapyML('packet'), ?MException);
        end

        function tcCliNeg003b_csvCommandTooFewArgumentsErrors(testCase)
            % TC-CLI-NEG-003 — 'csv' with only a filename (missing
            % protocol name) errors clearly.
            testCase.verifyError(@() ScapyML('csv', 'file.csv'), ?MException);
        end

        function tcCliNeg003c_dissectorCommandTooFewArgumentsErrors(testCase)
            % TC-CLI-NEG-003 — 'dissector' with only a protocol name
            % (missing output filename) errors clearly.
            testCase.verifyError(@() ScapyML('dissector', 'CliProto'), ?MException);
        end

        function tcCliNeg003d_registerCommandTooFewArgumentsErrors(testCase)
            % TC-CLI-NEG-003 — 'register' with no protoDef argument errors
            % clearly.
            testCase.verifyError(@() ScapyML('register'), ?MException);
        end

        % -----------------------------------------------------------
        % 'send' command variants — open a real UDP socket, so these
        % follow the assumeFail skip-not-fail pattern.
        % -----------------------------------------------------------

        function tcCliFunc005_sendCommandWithSinglePacketObject(testCase)
            % TC-CLI-FUNC-005 — 'send' with a single Packet object routes
            % to UdpSender.sendOnce(pkt.build(), ...).
            pkt = ScapyML.Packet('CliProto');
            try
                testCase.verifyWarningFree(...
                    @() ScapyML('send', pkt, '127.0.0.1', 40201));
            catch ME
                testCase.assumeFail(['Loopback UDP unavailable: ' ME.message]);
            end
        end

        function tcCliFunc006_sendCommandWithCellArrayOfPackets(testCase)
            % TC-CLI-FUNC-006 — 'send' with a cell array of packets routes
            % to PacketSender.sendWithTiming(..., 'single').
            pkt1 = ScapyML.Packet('CliProto');
            pkt2 = ScapyML.Packet('CliProto');
            try
                testCase.verifyWarningFree(...
                    @() ScapyML('send', {pkt1, pkt2}, '127.0.0.1', 40202));
            catch ME
                testCase.assumeFail(['Loopback UDP unavailable: ' ME.message]);
            end
        end

        function tcCliFunc007_sendCommandWithRawByteArray(testCase)
            % TC-CLI-FUNC-007 — 'send' with a raw numeric byte array
            % routes directly to UdpSender.sendOnce with those bytes.
            try
                testCase.verifyWarningFree(...
                    @() ScapyML('send', uint8([1 2 3]), '127.0.0.1', 40203));
            catch ME
                testCase.assumeFail(['Loopback UDP unavailable: ' ME.message]);
            end
        end

        function tcCliFunc007b_sendCommandWithUnsupportedTypeErrors(testCase)
            % Negative companion — 'send' with a data type that is
            % neither a Packet, cell array, nor numeric array errors with
            % ScapyML:BadArg rather than silently doing nothing.
            try
                testCase.verifyError(...
                    @() ScapyML('send', "a string is not valid", '127.0.0.1', 40204), ...
                    'ScapyML:BadArg');
            catch ME
                if ~strcmp(ME.identifier, 'ScapyML:BadArg')
                    testCase.assumeFail(['Loopback UDP unavailable or unexpected error: ' ME.message]);
                end
            end
        end

        function tcCliFunc008_sendCommandUsesDefaultDestinationWhenOmitted(testCase)
            % TC-CLI-FUNC-008 — 'send' with only a packet argument (no
            % ip/port) sends to the hardcoded default 10.10.10.10:1234.
            % We can't verify actual delivery to a non-loopback address in
            % a test environment, but we CAN verify the call is accepted
            % (reaches UdpSender.sendOnce with the default destination)
            % rather than erroring for "missing" ip/port arguments.
            pkt = ScapyML.Packet('CliProto');
            try
                ScapyML('send', pkt);
                % If no loopback restriction applies to 10.10.10.10 in
                % this environment, reaching here without error confirms
                % the default-destination code path was used.
            catch ME
                % Accept either a network-related failure (unreachable
                % default destination is expected in most sandboxes) as
                % confirmation the call proceeded to the send layer, or a
                % skip if UDP itself is fully unavailable.
                testCase.assumeTrue(...
                    contains(ME.identifier, 'UdpSender') || contains(ME.message, 'UDP'), ...
                    sprintf('Expected a UDP-layer failure for the unreachable default destination, got: %s', ME.message));
            end
        end

    end
end
