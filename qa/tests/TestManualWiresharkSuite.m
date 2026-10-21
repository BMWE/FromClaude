classdef TestManualWiresharkSuite < matlab.unittest.TestCase
% Automated equivalents of the manual WiresharkDissector (single-protocol)
% test cases in STR.md Section 13 (TC-WSD-*). This file intentionally
% does NOT re-implement cases already covered by TestWiresharkDissector.m
% (all primitive ProtoField types, bit-field masks matching KI-003
% encoding, cross-byte bit-field containers, array group nodes, array
% offset accumulation with alignment, nested struct absolute offsets,
% union same-start-offset, enum value tables, cross-protocol field-name
% collision avoidance, @@/backtick/non-ASCII hygiene, named-tag enum
% end-to-end).

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

    methods (TestMethodSetup)
        function clearRegistry(~)
            ScapyML.ProtocolRegistry.instance().clearAll();
        end
    end

    methods (Test)

        function tcWsdFunc006_littleEndianUsesAddLeBigEndianUsesAdd(testCase)
            % TC-WSD-FUNC-006 — little-endian multi-byte fields use
            % subtree:add_le(...); big-endian (and single-byte) fields
            % use subtree:add(...).
            h = {'typedef struct End { uint8_t one; uint32_t four; } End;'};

            fLE = writeFixtureHeader(testCase.TempFolder, 'end_le.h', h);
            protosLE = ScapyML.HeaderParser.parseFile(fLE, 'little');
            outLE = fullfile(testCase.TempFolder, 'end_le.lua');
            ScapyML.WiresharkDissector.generate(protosLE{1}, outLE);
            txtLE = fileread(outLE);
            testCase.verifyTrue(contains(txtLE, 'add_le'), ...
                'Little-endian multi-byte field should use add_le');

            ScapyML.ProtocolRegistry.instance().clearAll();

            fBE = writeFixtureHeader(testCase.TempFolder, 'end_be.h', h);
            protosBE = ScapyML.HeaderParser.parseFile(fBE, 'big');
            outBE = fullfile(testCase.TempFolder, 'end_be.lua');
            ScapyML.WiresharkDissector.generate(protosBE{1}, outBE);
            txtBE = fileread(outBE);
            testCase.verifyFalse(contains(txtBE, 'add_le'), ...
                'Big-endian fields should never use add_le');
        end

        function tcWsdNeg001_writeFailureInvalidOutputPath(testCase)
            % TC-WSD-NEG-001 — an unwritable output path (nonexistent
            % directory) errors with ScapyML:WiresharkDissector:WriteError
            % rather than failing silently.
            h = {'typedef struct W { uint8_t a; } W;'};
            f = writeFixtureHeader(testCase.TempFolder, 'w.h', h);
            protos = ScapyML.HeaderParser.parseFile(f, 'little');

            badPath = fullfile(testCase.TempFolder, 'no_such_dir_xyz', 'out.lua');
            testCase.verifyError(...
                @() ScapyML.WiresharkDissector.generate(protos{1}, badPath), ...
                'ScapyML:WiresharkDissector:WriteError');
        end

        function tcWsdInt001_cliDissectorCommandAutoPullsEnumsFromRegistry(testCase)
            % TC-WSD-INT-001 — the CLI 'dissector' command automatically
            % pulls enum definitions from the ProtocolRegistry without the
            % caller needing to supply them manually (unlike calling
            % WiresharkDissector.generate directly, which requires an
            % explicit enumDefs argument).
            h = {'typedef enum Mode { MODE_OFF=0, MODE_ON=1 } Mode;', ...
                 'typedef struct Device { Mode m; uint8_t id; } Device;'};
            f = writeFixtureHeader(testCase.TempFolder, 'device.h', h);
            ScapyML.HeaderParser.parseFile(f, 'little');

            out = fullfile(testCase.TempFolder, 'device.lua');
            ScapyML('dissector', 'Device', out, 5000);

            testCase.verifyTrue(isfile(out));
            txt = fileread(out);
            testCase.verifyTrue(contains(txt, 'MODE_OFF'), ...
                'CLI dissector command should auto-include enum value names from the registry');
            testCase.verifyTrue(contains(txt, 'MODE_ON'));
        end

        function tcWsdFunc002_bitFieldMaskCrossCheckAgainstActualEncoding(testCase)
            % TC-WSD-FUNC-002 — the generated Wireshark mask, when manually
            % applied (shift+AND) to the ACTUAL byte produced by Codec
            % encoding, must recover the exact field value ScapyML itself
            % encoded. This is an independent, byte-level cross-check
            % between two separately-implemented code paths (Codec vs.
            % WiresharkDissector), not just an inspection of the generated
            % text in isolation.
            h = {'typedef struct BF2 { uint8_t a:3; uint8_t b:5; } BF2;'};
            f = writeFixtureHeader(testCase.TempFolder, 'bf2.h', h);
            protos = ScapyML.HeaderParser.parseFile(f, 'little');

            pkt = ScapyML.Packet('BF2');
            pkt.set('a', 5);
            pkt.set('b', 19);
            actualByte = pkt.build();
            actualByte = actualByte(1);

            out = fullfile(testCase.TempFolder, 'bf2.lua');
            ScapyML.WiresharkDissector.generate(protos{1}, out);
            txt = fileread(out);

            % From the existing suite's own documented convention
            % (tc02): a:3 at bit0 -> mask 0xE0; b:5 at bit3 -> mask 0x1F.
            testCase.verifyTrue(contains(txt, '0xE0'));
            testCase.verifyTrue(contains(txt, '0x1F'));

            % Manually apply the documented masks to the ACTUAL encoded
            % byte and confirm they recover the values we set.
            maskA = uint8(hex2dec('E0'));
            maskB = uint8(hex2dec('1F'));
            recoveredA = bitshift(bitand(actualByte, maskA), -5);
            recoveredB = bitand(actualByte, maskB);

            testCase.verifyEqual(double(recoveredA), 5, ...
                'Wireshark mask 0xE0 applied to the real encoded byte must recover field a');
            testCase.verifyEqual(double(recoveredB), 19, ...
                'Wireshark mask 0x1F applied to the real encoded byte must recover field b');
        end

        function tcWsdFunc004_arraySubtreeContainsOnePerElementEntry(testCase)
            % TC-WSD-FUNC-004 — an array field is grouped under a labeled
            % subtree with exactly one per-element add() call for each
            % declared array element (not one combined multi-byte add).
            h = {'typedef struct A6 { uint8_t data[6]; } A6;'};
            f = writeFixtureHeader(testCase.TempFolder, 'a6.h', h);
            protos = ScapyML.HeaderParser.parseFile(f, 'little');
            out = fullfile(testCase.TempFolder, 'a6.lua');
            ScapyML.WiresharkDissector.generate(protos{1}, out);

            txt = fileread(out);
            testCase.verifyTrue(contains(txt, 'data[6]'));
            % Six distinct single-byte buffer offsets (0 through 5) should
            % each appear as a 1-byte read inside the array block.
            for offset = 0:5
                token = sprintf('buffer(%d, 1)', offset);
                testCase.verifyTrue(contains(txt, token), ...
                    sprintf('Expected a per-element read at %s for array element %d', token, offset));
            end
        end

    end
end
