classdef TestManualChecksumSuite < matlab.unittest.TestCase
% Automated equivalents of the manual ChecksumManager test cases in
% STR.md Section 6 (TC-CHK-*). This file intentionally does NOT
% re-implement cases already covered by TestChecksumManager.m (empty
% manager, simple sum checksum, == operator parsing, checksum applied to
% buffer, idempotency across repeated builds, multi-checksum offset
% ordering, undefined-function calculation error).
%
% NOTE ON AN EXISTING TEST DISCREPANCY (found while writing this file):
% TestChecksumManager.m's 'missingFileProducesEmptyManagerNotError' test
% asserts verifyWarningFree() for a missing checksum file. Reading
% +ScapyML/ChecksumManager.m directly shows the constructor DOES call
% warning('ScapyML:ChecksumManager:FileNotFound', ...) when the file does
% not exist (see line ~50). That existing test therefore contradicts the
% actual source and would fail if executed. TC-CHK-ERR-001 below tests the
% real, source-confirmed behaviour (a warning IS raised) rather than
% repeating that assumption. Recommend fixing/removing the pre-existing
% test as part of this defect's resolution.

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

        function tcChkFunc004_listChecksumsAccessor(testCase)
            % TC-CHK-FUNC-004 — listChecksums()/checksumCount()/
            % hasChecksum() accessors with two defined checksums.
            csFile = fullfile(testCase.TempFolder, 'cs_accessors.txt');
            fid = fopen(csFile, 'w');
            fprintf(fid, 'crcA = @(data) mod(sum(uint32(data)), 65536)\n');
            fprintf(fid, 'crcB = @(data) bitxor(data(1), 0)\n');
            fclose(fid);

            cm = ScapyML.ChecksumManager(csFile);
            testCase.verifyEqual(cm.checksumCount(), 2);
            names = cm.listChecksums();
            testCase.verifyTrue(any(strcmp(names, 'crcA')));
            testCase.verifyTrue(any(strcmp(names, 'crcB')));
            testCase.verifyTrue(cm.hasChecksum('crcA'));
            testCase.verifyTrue(cm.hasChecksum('crcB'));
            testCase.verifyFalse(cm.hasChecksum('nope'));
        end

        function tcChkFunc005_xorAndOnesComplementFormulas(testCase)
            % TC-CHK-FUNC-005 — XOR and ones'-complement checksum formulas
            % (from the class's own documented example set), hand-verified
            % against a fixed 4-byte payload.
            csFile = fullfile(testCase.TempFolder, 'cs_formulas.txt');
            fid = fopen(csFile, 'w');
            fprintf(fid, 'xor_checksum = @(data) bitxor(data(1), bitxor(data(2), bitxor(data(3), data(4))))\n');
            fprintf(fid, 'ones_comp = @(data) bitcmp(uint16(mod(sum(uint32(data)), 65536)), ''uint16'')\n');
            fclose(fid);
            cm = ScapyML.ChecksumManager(csFile);

            payload = uint8([0x12 0x34 0x56 0x78]);

            xorExpected = bitxor(bitxor(bitxor(payload(1), payload(2)), payload(3)), payload(4));
            xorActual = cm.calculateChecksum('xor_checksum', payload);
            testCase.verifyEqual(double(xorActual), double(xorExpected));

            sumVal = mod(sum(uint32(payload)), 65536);
            onesCompExpected = bitcmp(uint16(sumVal), 'uint16');
            onesCompActual = cm.calculateChecksum('ones_comp', payload);
            testCase.verifyEqual(double(onesCompActual), double(onesCompExpected));
        end

        function tcChkErr001_missingFileWarnsFileNotFound(testCase)
            % TC-CHK-ERR-001 — a missing checksum file must produce
            % warning ScapyML:ChecksumManager:FileNotFound and yield an
            % empty (but usable) manager. Confirmed against the actual
            % constructor source (see class-level note above); this
            % corrects the assumption in the pre-existing test of the
            % same intent.
            testCase.verifyWarning(...
                @() ScapyML.ChecksumManager('does_not_exist_ki01.txt'), ...
                'ScapyML:ChecksumManager:FileNotFound');

            % Suppress the expected warning to construct a usable instance
            % for the follow-up assertion.
            warnState = warning('off', 'ScapyML:ChecksumManager:FileNotFound');
            cm = ScapyML.ChecksumManager('does_not_exist_ki01.txt');
            warning(warnState);
            testCase.verifyEqual(cm.checksumCount(), 0);
        end

        function tcChkErr002_malformedLineNoEqualsSign(testCase)
            % TC-CHK-ERR-002 — a line with no '=' sign warns ParseError
            % for that line, but other valid lines in the same file still
            % load.
            csFile = fullfile(testCase.TempFolder, 'cs_malformed.txt');
            fid = fopen(csFile, 'w');
            fprintf(fid, 'garbage line no equals\n');
            fprintf(fid, 'goodOne = @(data) sum(data)\n');
            fclose(fid);

            testCase.verifyWarning(...
                @() ScapyML.ChecksumManager(csFile), ...
                'ScapyML:ChecksumManager:ParseError');

            warnState = warning('off', 'ScapyML:ChecksumManager:ParseError');
            cm = ScapyML.ChecksumManager(csFile);
            warning(warnState);
            testCase.verifyTrue(cm.hasChecksum('goodOne'), ...
                'Valid line after a malformed line must still load');
            testCase.verifyEqual(cm.checksumCount(), 1);
        end

        function tcChkErr003_rhsNotFunctionHandle(testCase)
            % TC-CHK-ERR-003 — right-hand side that evaluates to a plain
            % number (not a function handle) warns NotFunction and is
            % skipped.
            csFile = fullfile(testCase.TempFolder, 'cs_notfunc.txt');
            fid = fopen(csFile, 'w');
            fprintf(fid, 'checksum = 42\n');
            fclose(fid);

            testCase.verifyWarning(...
                @() ScapyML.ChecksumManager(csFile), ...
                'ScapyML:ChecksumManager:NotFunction');

            warnState = warning('off', 'ScapyML:ChecksumManager:NotFunction');
            cm = ScapyML.ChecksumManager(csFile);
            warning(warnState);
            testCase.verifyFalse(cm.hasChecksum('checksum'), ...
                'A non-function entry must not be registered');
        end

        function tcChkErr004_checksumFieldNotFoundInProtocol(testCase)
            % TC-CHK-ERR-004 — a checksum config referencing a field name
            % that does not exist in the loaded protocol must warn
            % FieldNotFound during applyChecksums and not crash the build.
            h = {'typedef struct P { uint8_t a; uint8_t b; } P;'};
            f = writeFixtureHeader(testCase.TempFolder, 'p_nofield.h', h);
            ScapyML.HeaderParser.parseFile(f, 'little');

            csFile = fullfile(testCase.TempFolder, 'cs_nofield.txt');
            fid = fopen(csFile, 'w');
            fprintf(fid, 'nonexistent_field = @(data) sum(data)\n');
            fclose(fid);
            cm = ScapyML.ChecksumManager(csFile);

            pkt = ScapyML.Packet('P');
            pkt.set('a', 5);

            testCase.verifyWarning(@() pkt.buildWithChecksums(cm), ...
                'ScapyML:ChecksumManager:FieldNotFound');
        end

        function tcChkErr006_nonScalarResultWarnsAndLeavesFieldUnmodified(testCase)
            % TC-CHK-ERR-006 — a checksum function returning a non-scalar
            % value warns InvalidResult and leaves the target field
            % unmodified (still zero, since it was zeroed before the
            % attempted calculation).
            h = {'typedef struct P { uint8_t a; uint16_t checksum; } P;'};
            f = writeFixtureHeader(testCase.TempFolder, 'p_nonscalar.h', h);
            ScapyML.HeaderParser.parseFile(f, 'little');

            csFile = fullfile(testCase.TempFolder, 'cs_nonscalar.txt');
            fid = fopen(csFile, 'w');
            fprintf(fid, 'checksum = @(data) [1 2 3]\n');
            fclose(fid);
            cm = ScapyML.ChecksumManager(csFile);

            pkt = ScapyML.Packet('P');
            pkt.set('a', 9);

            testCase.verifyWarning(...
                @() pkt.buildWithChecksums(cm), ...
                'ScapyML:ChecksumManager:InvalidResult');

            warnState = warning('off', 'ScapyML:ChecksumManager:InvalidResult');
            bytes = pkt.buildWithChecksums(cm);
            warning(warnState);
            testCase.verifyEqual(bytes(2), uint8(0));
            testCase.verifyEqual(bytes(3), uint8(0));
        end

        function tcChkBound001_fieldSizesAndEndianness(testCase)
            % TC-CHK-BOUND-001 — writeChecksumToBytes correctly places a
            % checksum value for every supported size (1/2/4/8 bytes) in
            % both endiannesses, and warns UnsupportedSize otherwise.
            cm = ScapyML.ChecksumManager();  % empty manager; only using
                                              % the public writeChecksumToBytes helper

            % 1 byte
            buf = uint8([0 0 0 0]);
            out = cm.writeChecksumToBytes(buf, 200, 0, 1, 'little');
            testCase.verifyEqual(out(1), uint8(200));

            % 2 bytes, little-endian
            buf = uint8([0 0 0 0]);
            out = cm.writeChecksumToBytes(buf, hex2dec('ABCD'), 0, 2, 'little');
            testCase.verifyEqual(out(1:2), uint8([hex2dec('CD') hex2dec('AB')]));

            % 2 bytes, big-endian
            out = cm.writeChecksumToBytes(buf, hex2dec('ABCD'), 0, 2, 'big');
            testCase.verifyEqual(out(1:2), uint8([hex2dec('AB') hex2dec('CD')]));

            % 4 bytes, little-endian
            buf = uint8([0 0 0 0]);
            out = cm.writeChecksumToBytes(buf, hex2dec('11223344'), 0, 4, 'little');
            testCase.verifyEqual(out, uint8([hex2dec('44') hex2dec('33') hex2dec('22') hex2dec('11')]));

            % 4 bytes, big-endian
            out = cm.writeChecksumToBytes(buf, hex2dec('11223344'), 0, 4, 'big');
            testCase.verifyEqual(out, uint8([hex2dec('11') hex2dec('22') hex2dec('33') hex2dec('44')]));

            % 8 bytes, little-endian
            buf8 = uint8(zeros(1,8));
            out = cm.writeChecksumToBytes(buf8, 1, 0, 8, 'little');
            testCase.verifyEqual(out, uint8([1 0 0 0 0 0 0 0]));

            % 8 bytes, big-endian
            out = cm.writeChecksumToBytes(buf8, 1, 0, 8, 'big');
            testCase.verifyEqual(out, uint8([0 0 0 0 0 0 0 1]));

            % Unsupported size (3 bytes)
            testCase.verifyWarning(...
                @() cm.writeChecksumToBytes(uint8([0 0 0]), 5, 0, 3, 'little'), ...
                'ScapyML:ChecksumManager:UnsupportedSize');
        end

    end
end
