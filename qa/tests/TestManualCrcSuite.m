classdef TestManualCrcSuite < matlab.unittest.TestCase
% Standard check values for ScapyML.Crc (input = ASCII '123456789').

    methods (Test)
        function tcStandardCheckValues(testCase)
            d = uint8('123456789');
            testCase.verifyEqual(ScapyML.Crc.crc8(d), 244);              % 0xF4
            testCase.verifyEqual(ScapyML.Crc.crc16ccitt(d), 41137);      % 0x29B1
            testCase.verifyEqual(ScapyML.Crc.crc16modbus(d), 19255);     % 0x4B37
            testCase.verifyEqual(ScapyML.Crc.crc32(d), 3421780262);      % 0xCBF43926
            testCase.verifyEqual(ScapyML.Crc.fletcher16(d), 7902);       % 0x1EDE
        end

        function tcInternetChecksumRfc1071(testCase)
            d = uint8([0 1 242 3 244 245 246 247]);
            testCase.verifyEqual(ScapyML.Crc.internetChecksum(d), 8717); % 0x220D
        end

        function tcCrcInsideChecksumFile(testCase)
            % End-to-end: CRC-16 stored in the last 2 bytes, covering the rest
            import matlab.unittest.fixtures.TemporaryFolderFixture
            tmp = testCase.applyFixture(TemporaryFolderFixture).Folder;
            ScapyML.ProtocolRegistry.instance().clearAll();
            h = fullfile(tmp, 'p.h');
            fid = fopen(h, 'w');
            fprintf(fid, 'typedef struct P { uint8_t a; uint8_t b; uint16_t crc; } P;\n');
            fclose(fid);
            ScapyML.HeaderParser.parseFile(h, 'big');
            cf = fullfile(tmp, 'cs.txt');
            fid = fopen(cf, 'w');
            fprintf(fid, 'crc = @(data) ScapyML.Crc.crc16ccitt(data(1:end-2))\n');
            fclose(fid);
            cm = ScapyML.ChecksumManager(cf);
            pkt = ScapyML.Packet('P');
            pkt.set('a', 1); pkt.set('b', 2);
            bytes = pkt.buildWithChecksums(cm);
            expected = ScapyML.Crc.crc16ccitt(uint8([1 2]));
            testCase.verifyEqual(double(bytes(3))*256 + double(bytes(4)), expected);
        end
    end
end
