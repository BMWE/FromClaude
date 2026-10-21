classdef TestManualCodecSuite < matlab.unittest.TestCase
% Automated equivalents of the manual Codec test cases in STR.md Section 5
% (TC-CODEC-*). This file intentionally does NOT re-implement cases
% already covered by TestCodecEncoding.m / TestCodecDecoding.m (uint8/16/32
% encode, negative int16, float32, double64, single-byte bit-field packing,
% bit-field round-trip, plain array encode, union dirty-write, decode
% round-trip, insufficient-data error, union __raw decode) — see those
% files for that coverage. Each test method below is headed by the STR.md
% Test Case ID it automates.

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

        function tcCodecFunc001_littleEndianFullRoundTrip(testCase)
            % TC-CODEC-FUNC-001 — little-endian multi-byte encode/decode
            % round-trip, verifying exact byte order AND full round-trip.
            f = writeFixtureHeader(testCase.TempFolder, 'c001.h', ...
                {'typedef struct V { uint32_t v; } V;'});
            ScapyML.HeaderParser.parseFile(f, 'little');
            pkt = ScapyML.Packet('V');
            pkt.set('v', hex2dec('11223344'));
            bytes = pkt.build();
            testCase.verifyEqual(bytes, uint8([0x44 0x33 0x22 0x11]));

            decoded = ScapyML.Packet.fromBytes('V', bytes);
            testCase.verifyEqual(decoded.get('v'), hex2dec('11223344'));
        end

        function tcCodecFunc002_bigEndianFullRoundTrip(testCase)
            % TC-CODEC-FUNC-002 — big-endian multi-byte encode/decode
            % round-trip, verifying exact byte order AND full round-trip.
            f = writeFixtureHeader(testCase.TempFolder, 'c002.h', ...
                {'typedef struct V { uint32_t v; } V;'});
            ScapyML.HeaderParser.parseFile(f, 'big');
            pkt = ScapyML.Packet('V');
            pkt.set('v', hex2dec('11223344'));
            bytes = pkt.build();
            testCase.verifyEqual(bytes, uint8([0x11 0x22 0x33 0x44]));

            decoded = ScapyML.Packet.fromBytes('V', bytes);
            testCase.verifyEqual(decoded.get('v'), hex2dec('11223344'));
        end

        function tcCodecFunc007_arrayOf16ElementsFullRoundTrip(testCase)
            % TC-CODEC-FUNC-007 — array of primitives, full encode/decode
            % round-trip for all 16 elements in declared order.
            f = writeFixtureHeader(testCase.TempFolder, 'c007.h', ...
                {'typedef struct A { uint8_t data[16]; } A;'});
            ScapyML.HeaderParser.parseFile(f, 'little');
            pkt = ScapyML.Packet('A');
            pkt.set('data', 1:16);
            bytes = pkt.build();
            testCase.verifyEqual(bytes, uint8(1:16));

            decoded = ScapyML.Packet.fromBytes('A', bytes);
            testCase.verifyEqual(decoded.get('data'), 1:16);
        end

        function tcCodecFunc009_nestedStructInsideUnionDirtyPropagation(testCase)
            % TC-CODEC-FUNC-009 — nested struct inside a union: only the
            % explicitly-set member ('bytes_lo') is written; the sibling
            % member of the same nested struct ('bytes_hi'), never set,
            % must not corrupt the byte it would otherwise occupy.
            f = writeFixtureHeader(testCase.TempFolder, 'c009.h', ...
                {'typedef union W {'
                 '  uint16_t raw;'
                 '  struct { uint8_t lo; uint8_t hi; } bytes;'
                 '} W;'});
            ScapyML.HeaderParser.parseFile(f, 'little');
            pkt = ScapyML.Packet('W');
            pkt.set('bytes_lo', hex2dec('AB'));
            bytes = pkt.build();
            testCase.verifyEqual(bytes(1), uint8(hex2dec('AB')));
            testCase.verifyEqual(numel(bytes), 2);
            % bytes_hi and raw were never set; confirm byte 2 stays at the
            % zero-initialised buffer default rather than being corrupted.
            testCase.verifyEqual(bytes(2), uint8(0));
        end

        function tcCodecErr002_insufficientDataForArrayField(testCase)
            % TC-CODEC-ERR-002 — decoding with insufficient trailing bytes
            % specifically for an array field must error, not silently
            % truncate or pad the array.
            f = writeFixtureHeader(testCase.TempFolder, 'c_err002.h', ...
                {'typedef struct A { uint8_t hdr; uint8_t data[8]; } A;'});
            ScapyML.HeaderParser.parseFile(f, 'little');
            % Only 1 header byte + 3 of the 8 array bytes supplied.
            shortBytes = uint8([1 2 3 4]);
            testCase.verifyError(...
                @() ScapyML.Codec.decode(...
                    ScapyML.ProtocolRegistry.instance().get('A'), shortBytes), ...
                ?MException);
        end

        function tcCodecBound001_zeroBitFieldIsNoOp(testCase)
            % TC-CODEC-BOUND-001 — a 0-bit writeBits/readBits call must be
            % a no-op: the buffer is unchanged and the function returns
            % immediately without indexing into it.
            buf = uint8([0xAA 0xBB 0xCC]);
            result = ScapyML.Codec.writeBits(buf, 0, 0, 999, 'little', false, true);
            testCase.verifyEqual(result, buf, ...
                'writeBits with numBits=0 must not modify the buffer');

            val = ScapyML.Codec.readBits(buf, 0, 0, 'little', false);
            % readBits returns uint64; cast before comparing to a plain
            % double literal since verifyEqual is class-strict by default.
            testCase.verifyEqual(double(val), 0, ...
                'readBits with numBits=0 should return 0 without touching the buffer');
        end

        function tcCodecBound002_oneBitFieldEncodeDecode(testCase)
            % TC-CODEC-BOUND-002 — a 1-bit field must correctly round-trip
            % both possible values (0 and 1).
            f = writeFixtureHeader(testCase.TempFolder, 'c_b002.h', ...
                {'typedef struct P { uint8_t flag:1; } P;'});
            ScapyML.HeaderParser.parseFile(f, 'little');

            pkt0 = ScapyML.Packet('P');
            pkt0.set('flag', 0);
            decoded0 = ScapyML.Packet.fromBytes('P', pkt0.build());
            testCase.verifyEqual(decoded0.get('flag'), 0);

            pkt1 = ScapyML.Packet('P');
            pkt1.set('flag', 1);
            decoded1 = ScapyML.Packet.fromBytes('P', pkt1.build());
            testCase.verifyEqual(decoded1.get('flag'), 1);
        end

        function tcCodecBound003_maxWidthBitFieldMatchesPlainField(testCase)
            % TC-CODEC-BOUND-003 — a bit-field whose width equals its full
            % container size (uint32_t v:32) must encode/decode identically
            % to an equivalent plain (non-bit-field) uint32_t.
            fPlain = writeFixtureHeader(testCase.TempFolder, 'c_b003_plain.h', ...
                {'typedef struct Plain { uint32_t v; } Plain;'});
            ScapyML.HeaderParser.parseFile(fPlain, 'little');
            plainPkt = ScapyML.Packet('Plain');
            plainPkt.set('v', hex2dec('DEADBEEF'));
            plainBytes = plainPkt.build();

            ScapyML.ProtocolRegistry.instance().clearAll();

            fBit = writeFixtureHeader(testCase.TempFolder, 'c_b003_bit.h', ...
                {'typedef struct Bits { uint32_t v:32; } Bits;'});
            ScapyML.HeaderParser.parseFile(fBit, 'little');
            bitPkt = ScapyML.Packet('Bits');
            bitPkt.set('v', hex2dec('DEADBEEF'));
            bitBytes = bitPkt.build();

            testCase.verifyEqual(bitBytes, plainBytes, ...
                'A 32-bit-wide bitfield must encode identically to a plain uint32_t');

            decoded = ScapyML.Packet.fromBytes('Bits', bitBytes);
            testCase.verifyEqual(decoded.get('v'), hex2dec('DEADBEEF'));
        end

    end
end
