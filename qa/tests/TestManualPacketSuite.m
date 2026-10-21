classdef TestManualPacketSuite < matlab.unittest.TestCase
% Automated equivalents of the manual Packet test cases in STR.md Section 4
% (TC-PKT-*). This file intentionally does NOT re-implement cases already
% covered by TestPacketCore.m (packet creation, default field values,
% set/get round-trip, unknown-field set/get errors, non-numeric rejection,
% uint8/signed out-of-range clamping, array truncation/padding, fieldNames,
% loadStruct, constructor field-pairs, getFieldOffsets/getProtocolName
% public accessors) or TestBulkCsvLoad.m (fromValuesStruct bulk
% constructor, TC-PKT-FUNC-011). Each test method below is headed by the
% STR.md Test Case ID it automates.

    properties
        TempFolder
        WideProtoFile
    end

    methods (TestClassSetup)
        function classSetup(testCase)
            import matlab.unittest.fixtures.TemporaryFolderFixture
            fixture = testCase.applyFixture(TemporaryFolderFixture);
            testCase.TempFolder = fixture.Folder;

            % Shared fixture covering every integer width, signed and
            % unsigned, used by the boundary-clamping tests below.
            h = {
                'typedef struct WideProto {'
                '  uint8_t  u8;'
                '  int8_t   s8;'
                '  uint16_t u16;'
                '  int16_t  s16;'
                '  uint32_t u32;'
                '  int32_t  s32;'
                '  uint64_t u64;'
                '  int64_t  s64;'
                '} WideProto;'
            };
            testCase.WideProtoFile = writeFixtureHeader(testCase.TempFolder, 'wide.h', h);
        end
    end

    methods (TestMethodSetup)
        function reloadWideProto(testCase)
            ScapyML.ProtocolRegistry.instance().clearAll();
            ScapyML.HeaderParser.parseFile(testCase.WideProtoFile, 'little');
        end
    end

    methods (Test)

        function tcPktFunc001_defaultsAreZeroForEveryFieldType(testCase)
            % TC-PKT-FUNC-001 — every field of a freshly constructed
            % packet equals its declared default (0), across every
            % integer width.
            pkt = ScapyML.Packet('WideProto');
            for fname = {'u8','s8','u16','s16','u32','s32','u64','s64'}
                testCase.verifyEqual(pkt.get(fname{1}), 0, ...
                    sprintf('Field %s should default to 0', fname{1}));
            end
        end

        function tcPktFunc010_fromBytesRoundTripsMultipleFieldTypes(testCase)
            % TC-PKT-FUNC-010 — Packet.fromBytes decode constructor:
            % encoding then decoding a packet with several different
            % field widths/signs must reproduce every field exactly.
            pkt = ScapyML.Packet('WideProto');
            pkt.set('u8', 200);
            pkt.set('s8', -100);
            pkt.set('u16', 60000);
            pkt.set('s16', -30000);
            pkt.set('u32', 4000000000);
            pkt.set('s32', -2000000000);

            bytes = pkt.build();
            pkt2 = ScapyML.Packet.fromBytes('WideProto', bytes);

            testCase.verifyEqual(pkt2.get('u8'), pkt.get('u8'));
            testCase.verifyEqual(pkt2.get('s8'), pkt.get('s8'));
            testCase.verifyEqual(pkt2.get('u16'), pkt.get('u16'));
            testCase.verifyEqual(pkt2.get('s16'), pkt.get('s16'));
            testCase.verifyEqual(pkt2.get('u32'), pkt.get('u32'));
            testCase.verifyEqual(pkt2.get('s32'), pkt.get('s32'));
        end

        function tcPktFunc007_showProducesNonEmptyFormattedOutput(testCase)
            % TC-PKT-FUNC-007 — show() displays every field. We can't
            % assert exact formatting portably, but we verify it runs
            % without error and prints something containing each field
            % name for a representative packet.
            pkt = ScapyML.Packet('WideProto');
            pkt.set('u8', 42);
            pkt.set('s16', -7);
            output = evalc('pkt.show()');
            testCase.verifyNotEmpty(output);
            testCase.verifyTrue(contains(output, 'u8'), ...
                'show() output should mention field name u8');
            testCase.verifyTrue(contains(output, 's16'), ...
                'show() output should mention field name s16');
        end

        function tcPktFunc008_hexdumpProducesWrappedHexOutput(testCase)
            % TC-PKT-FUNC-008 — hexdump() produces uppercase two-digit hex
            % bytes, wrapped at 16 bytes per line, for a packet longer
            % than 16 bytes.
            f = writeFixtureHeader(testCase.TempFolder, 'c_hex.h', ...
                {'typedef struct Big { uint8_t data[20]; } Big;'});
            ScapyML.HeaderParser.parseFile(f, 'little');
            pkt = ScapyML.Packet('Big');
            pkt.set('data', 1:20);

            output = evalc('pkt.hexdump()');
            testCase.verifyNotEmpty(output);
            % First byte (0x01) must appear as an uppercase two-digit hex
            % token somewhere in the output.
            testCase.verifyTrue(contains(output, '01'), ...
                'hexdump() output should contain the first byte as hex');
            % Output should span more than one line for a 20-byte packet
            % wrapped at 16 bytes/line.
            numLines = numel(strsplit(strtrim(output), newline));
            testCase.verifyGreaterThanOrEqual(numLines, 2, ...
                'hexdump() of a 20-byte packet should wrap onto >= 2 lines');
        end

        function tcPktBound003a_uint16BoundaryClamping(testCase)
            % TC-PKT-BOUND-003 — uint16 range: 0/65535 accepted without
            % warning; 65536/-1 clamp with a warning.
            pkt = ScapyML.Packet('WideProto');
            pkt.set('u16', 0);
            testCase.verifyEqual(pkt.get('u16'), 0);
            pkt.set('u16', 65535);
            testCase.verifyEqual(pkt.get('u16'), 65535);

            testCase.verifyWarning(@() pkt.set('u16', 65536), ...
                'ScapyML:Packet:OutOfRange');
            testCase.verifyEqual(pkt.get('u16'), 65535);

            testCase.verifyWarning(@() pkt.set('u16', -1), ...
                'ScapyML:Packet:OutOfRange');
            testCase.verifyEqual(pkt.get('u16'), 0);
        end

        function tcPktBound003b_int16BoundaryClamping(testCase)
            % TC-PKT-BOUND-003 — int16 range: -32768/32767 accepted;
            % 32768/-32769 clamp with a warning.
            pkt = ScapyML.Packet('WideProto');
            pkt.set('s16', -32768);
            testCase.verifyEqual(pkt.get('s16'), -32768);
            pkt.set('s16', 32767);
            testCase.verifyEqual(pkt.get('s16'), 32767);

            testCase.verifyWarning(@() pkt.set('s16', 32768), ...
                'ScapyML:Packet:OutOfRange');
            testCase.verifyEqual(pkt.get('s16'), 32767);

            testCase.verifyWarning(@() pkt.set('s16', -32769), ...
                'ScapyML:Packet:OutOfRange');
            testCase.verifyEqual(pkt.get('s16'), -32768);
        end

        function tcPktBound003c_uint32BoundaryClamping(testCase)
            % TC-PKT-BOUND-003 — uint32 range: 0/4294967295 accepted;
            % 4294967296/-1 clamp with a warning.
            pkt = ScapyML.Packet('WideProto');
            pkt.set('u32', 0);
            testCase.verifyEqual(pkt.get('u32'), 0);
            pkt.set('u32', 4294967295);
            testCase.verifyEqual(pkt.get('u32'), 4294967295);

            testCase.verifyWarning(@() pkt.set('u32', 4294967296), ...
                'ScapyML:Packet:OutOfRange');
            testCase.verifyEqual(pkt.get('u32'), 4294967295);

            testCase.verifyWarning(@() pkt.set('u32', -1), ...
                'ScapyML:Packet:OutOfRange');
            testCase.verifyEqual(pkt.get('u32'), 0);
        end

        function tcPktBound003d_int32BoundaryClamping(testCase)
            % TC-PKT-BOUND-003 — int32 range: -2147483648/2147483647
            % accepted; one-past-boundary on each side clamps with a
            % warning.
            pkt = ScapyML.Packet('WideProto');
            pkt.set('s32', -2147483648);
            testCase.verifyEqual(pkt.get('s32'), -2147483648);
            pkt.set('s32', 2147483647);
            testCase.verifyEqual(pkt.get('s32'), 2147483647);

            testCase.verifyWarning(@() pkt.set('s32', 2147483648), ...
                'ScapyML:Packet:OutOfRange');
            testCase.verifyEqual(pkt.get('s32'), 2147483647);

            testCase.verifyWarning(@() pkt.set('s32', -2147483649), ...
                'ScapyML:Packet:OutOfRange');
            testCase.verifyEqual(pkt.get('s32'), -2147483648);
        end

        % Note: TC-PKT-BOUND-003 also calls for uint64/int64 boundary
        % coverage. Those boundaries (e.g. 18446744073709551615) exceed
        % MATLAB double precision (2^53), so an automated test using plain
        % numeric literals cannot exercise the exact boundary the way the
        % manual test case can with a human double-checking clamped output.
        % This is left to manual execution (see STR.md TC-PKT-BOUND-003)
        % rather than automated with a misleading "exact" numeric literal.

        function tcPktBound006_scalarFieldSetWithMultipleValuesWarns(testCase)
            % TC-PKT-BOUND-006 — setting a plain scalar field with a
            % multi-element array must warn and keep only the first
            % element.
            pkt = ScapyML.Packet('WideProto');
            testCase.verifyWarning(@() pkt.set('u8', [1 2 3]), ...
                'ScapyML:Packet:NotArray');
            testCase.verifyEqual(pkt.get('u8'), 1);
        end

    end
end
