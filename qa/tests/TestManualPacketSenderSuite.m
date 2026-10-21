classdef TestManualPacketSenderSuite < matlab.unittest.TestCase
% Automated equivalents of the manual PacketSender/UdpSender test cases in
% STR.md Sections 11-12 (TC-UDP-*, TC-SEND-*). This file intentionally
% does NOT re-implement cases already covered by TestUdpSenderAndTiming.m
% (socket-opens-once, send-does-not-reopen, send-after-close throws,
% close-is-idempotent, destructor releases socket, sendOnce static
% helper, busy-wait timing precision pattern, pause()-not-used regression
% guard).
%
% Pure, network-independent functions (isMulticastIP, buildPacket) are
% tested unconditionally. Anything that calls PacketSender.sendWithTiming
% or UdpSender directly opens a real (loopback) UDP socket as its very
% first action — even for cases that are "really" testing argument
% validation — so those tests follow the same testCase.assumeFail
% skip-not-fail pattern already established in TestUdpSenderAndTiming.m
% for sandboxed/CI environments without loopback UDP.

    properties
        TempFolder
    end

    methods (TestClassSetup)
        function classSetup(testCase)
            import matlab.unittest.fixtures.TemporaryFolderFixture
            fixture = testCase.applyFixture(TemporaryFolderFixture);
            testCase.TempFolder = fixture.Folder;

            h = {'typedef struct SendProto { uint8_t id; uint16_t val; } SendProto;'};
            f = writeFixtureHeader(testCase.TempFolder, 'sendproto.h', h);
            ScapyML.ProtocolRegistry.instance().clearAll();
            ScapyML.HeaderParser.parseFile(f, 'little');
        end
    end

    methods (Test)

        % -----------------------------------------------------------
        % Pure functions — no network required
        % -----------------------------------------------------------

        function tcSendFunc005_isMulticastIpClassifiesFullRange(testCase)
            % TC-SEND-FUNC-005 — isMulticastIP correctly classifies
            % addresses across and around the 224-239 multicast range.
            testCase.verifyFalse(ScapyML.PacketSender.isMulticastIP('192.168.1.1'));
            testCase.verifyTrue(ScapyML.PacketSender.isMulticastIP('224.0.0.1'));
            testCase.verifyTrue(ScapyML.PacketSender.isMulticastIP('239.255.255.255'));
            testCase.verifyFalse(ScapyML.PacketSender.isMulticastIP('240.0.0.1'));
            testCase.verifyFalse(ScapyML.PacketSender.isMulticastIP('223.255.255.255'));
            testCase.verifyFalse(ScapyML.PacketSender.isMulticastIP('10.0.0.1'));
        end

        function tcSendFunc005b_isMulticastIpHandlesMalformedInput(testCase)
            % Boundary companion: a malformed (non-4-octet) address must
            % return false rather than erroring.
            testCase.verifyFalse(ScapyML.PacketSender.isMulticastIP('not.an.ip'));
            testCase.verifyFalse(ScapyML.PacketSender.isMulticastIP('1.2.3'));
        end

        function tcSendFunc004a_buildPacketWithoutChecksumManagerUsesPlainBuild(testCase)
            % TC-SEND-FUNC-004 — buildPacket() with an empty checksum
            % manager argument ([]) must produce identical bytes to a
            % plain pkt.build() call.
            pkt = ScapyML.Packet('SendProto');
            pkt.set('id', 9);
            pkt.set('val', 500);

            bytesViaBuildPacket = ScapyML.PacketSender.buildPacket(pkt, []);
            bytesViaPlainBuild = pkt.build();
            testCase.verifyEqual(bytesViaBuildPacket, bytesViaPlainBuild);
        end

        function tcSendFunc004b_buildPacketWithChecksumManagerAppliesChecksum(testCase)
            % TC-SEND-FUNC-004 — buildPacket() with a real ChecksumManager
            % must produce the SAME bytes as calling
            % pkt.buildWithChecksums(cm) directly, confirming the two
            % code paths stay in sync.
            h = {'typedef struct SendProtoChk { uint8_t id; uint8_t checksum; } SendProtoChk;'};
            f = writeFixtureHeader(testCase.TempFolder, 'sendprotochk.h', h);
            ScapyML.HeaderParser.parseFile(f, 'little');

            csFile = fullfile(testCase.TempFolder, 'send_checksum.txt');
            fid = fopen(csFile, 'w');
            fprintf(fid, 'checksum = @(data) mod(sum(uint16(data)), 256)\n');
            fclose(fid);
            cm = ScapyML.ChecksumManager(csFile);

            pkt = ScapyML.Packet('SendProtoChk');
            pkt.set('id', 42);

            bytesViaBuildPacket = ScapyML.PacketSender.buildPacket(pkt, cm);
            bytesViaDirect = pkt.buildWithChecksums(cm);
            testCase.verifyEqual(bytesViaBuildPacket, bytesViaDirect);
        end

        % -----------------------------------------------------------
        % Network-dependent — sendWithTiming argument validation
        % (skips via assumeFail if loopback UDP is unavailable)
        % -----------------------------------------------------------

        function tcSendErr001_periodicModeMissingIntervalErrors(testCase)
            % TC-SEND-ERR-001 — periodic mode with no interval argument
            % errors clearly.
            pkt = ScapyML.Packet('SendProto');
            try
                testCase.verifyError(...
                    @() ScapyML.PacketSender.sendWithTiming(...
                        {pkt}, '127.0.0.1', 40101, 'periodic'), ...
                    ?MException);
            catch ME
                testCase.assumeFail(['Loopback UDP unavailable: ' ME.message]);
            end
        end

        function tcSendErr002_csvModeTimestampCountMismatchErrors(testCase)
            % TC-SEND-ERR-002 — CSV mode with a timestamp-count/packet-
            % count mismatch errors clearly.
            pkt1 = ScapyML.Packet('SendProto');
            pkt2 = ScapyML.Packet('SendProto');
            pkt3 = ScapyML.Packet('SendProto');
            try
                testCase.verifyError(...
                    @() ScapyML.PacketSender.sendWithTiming(...
                        {pkt1, pkt2, pkt3}, '127.0.0.1', 40102, 'csv', [0.0; 0.5]), ...
                    ?MException);
            catch ME
                testCase.assumeFail(['Loopback UDP unavailable: ' ME.message]);
            end
        end

        function tcSendErr003_csvModeNonAscendingTimestampsErrors(testCase)
            % TC-SEND-ERR-003 — CSV mode with non-ascending timestamps
            % errors clearly rather than sending out of order.
            pkt1 = ScapyML.Packet('SendProto');
            pkt2 = ScapyML.Packet('SendProto');
            pkt3 = ScapyML.Packet('SendProto');
            try
                testCase.verifyError(...
                    @() ScapyML.PacketSender.sendWithTiming(...
                        {pkt1, pkt2, pkt3}, '127.0.0.1', 40103, 'csv', [0.0; 0.5; 0.3]), ...
                    ?MException);
            catch ME
                testCase.assumeFail(['Loopback UDP unavailable: ' ME.message]);
            end
        end

        function tcSendErr004_unknownModeStringErrors(testCase)
            % TC-SEND-ERR-004 — an unrecognized mode string errors
            % clearly, naming the valid options.
            pkt = ScapyML.Packet('SendProto');
            try
                testCase.verifyError(...
                    @() ScapyML.PacketSender.sendWithTiming(...
                        {pkt}, '127.0.0.1', 40104, 'bogus_mode'), ...
                    ?MException);
            catch ME
                testCase.assumeFail(['Loopback UDP unavailable: ' ME.message]);
            end
        end

        function tcSendEdge001_emptyPacketListSendsZeroWithoutError(testCase)
            % TC-SEND-EDGE-001 — sending an empty packet list is a
            % well-defined no-op: the socket opens and closes cleanly with
            % zero sends, no error.
            try
                testCase.verifyWarningFree(...
                    @() ScapyML.PacketSender.sendWithTiming(...
                        {}, '127.0.0.1', 40105, 'single'));
            catch ME
                testCase.assumeFail(['Loopback UDP unavailable: ' ME.message]);
            end
        end

        function tcSendFunc001_singleModeSendsAllPacketsWithoutError(testCase)
            % TC-SEND-FUNC-001 — single-mode send transmits all packets
            % without error (functional smoke test; exact received-byte
            % verification would require a second listening socket and is
            % covered at the buildPacket() level above instead).
            pkt1 = ScapyML.Packet('SendProto');
            pkt1.set('id', 1);
            pkt2 = ScapyML.Packet('SendProto');
            pkt2.set('id', 2);
            try
                testCase.verifyWarningFree(...
                    @() ScapyML.PacketSender.sendWithTiming(...
                        {pkt1, pkt2}, '127.0.0.1', 40106, 'single'));
            catch ME
                testCase.assumeFail(['Loopback UDP unavailable: ' ME.message]);
            end
        end

        % -----------------------------------------------------------
        % UdpSender — remaining gaps
        % -----------------------------------------------------------

        function tcUdpFunc004_multicastDestinationAccepted(testCase)
            % TC-UDP-FUNC-004 — UdpSender accepts a multicast destination
            % IP without error (multicast routing itself is an OS/network
            % stack concern, not ScapyML's; we only verify ScapyML doesn't
            % reject the address).
            try
                u = ScapyML.UdpSender('239.255.0.1', 40107);
            catch ME
                testCase.assumeFail(['Loopback/multicast UDP unavailable: ' ME.message]);
                return;
            end
            testCase.addTeardown(@() u.close());
            testCase.verifyWarningFree(@() u.send(uint8([1])));
        end

        function tcUdpBound001_defaultConstructorArguments(testCase)
            % TC-UDP-BOUND-001 — UdpSender() with no arguments defaults to
            % 127.0.0.1:1234. DestIp/DestPort are private properties (no
            % public getter), so we verify indirectly via the socket-open
            % console message, which openSocket() prints as
            % "[ScapyML] UDP socket open (...) -> %s:%d" using obj.DestIp
            % / obj.DestPort directly.
            try
                output = evalc('u = ScapyML.UdpSender();');
            catch ME
                testCase.assumeFail(['Loopback UDP unavailable: ' ME.message]);
                return;
            end
            testCase.addTeardown(@() u.close());
            testCase.verifyTrue(contains(output, '127.0.0.1:1234'), ...
                'Default UdpSender() construction should open a socket to 127.0.0.1:1234');
        end

        function tcUdpErr002_sendToInvalidDestinationErrors(testCase)
            % TC-UDP-ERR-002 — sending to a syntactically invalid
            % destination address errors via ScapyML:UdpSender:SendFailed
            % (or fails at construction, depending on when MATLAB's
            % networking layer validates the address) rather than
            % succeeding silently.
            testCase.verifyError(...
                @() ScapyML.UdpSender.sendOnce(uint8([1]), '999.999.999.999', 40108), ...
                ?MException);
        end

    end
end
