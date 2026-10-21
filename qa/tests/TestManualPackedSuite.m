classdef TestManualPackedSuite < matlab.unittest.TestCase
% Packed (no padding) layout vs. C-ABI natural alignment.
% struct { unsigned char a; unsigned char b; unsigned int c; }
%   aligned (default): c at byte 4, size 8
%   packed           : c at byte 2, size 6

    properties
        TempFolder
    end

    methods (TestClassSetup)
        function classSetup(testCase)
            import matlab.unittest.fixtures.TemporaryFolderFixture
            testCase.TempFolder = testCase.applyFixture(TemporaryFolderFixture).Folder;
        end
    end

    methods (TestMethodSetup)
        function clearRegistry(~)
            ScapyML.ProtocolRegistry.instance().clearAll();
        end
    end

    methods (Access = private)
        function f = writeHeader(testCase, name, withPragma)
            f = fullfile(testCase.TempFolder, name);
            fid = fopen(f, 'w');
            if withPragma, fprintf(fid, '#pragma pack(push, 1)\n'); end
            fprintf(fid, 'typedef struct {\n  unsigned char a;\n  unsigned char b;\n  unsigned int c;\n} M;\n');
            if withPragma, fprintf(fid, '#pragma pack(pop)\n'); end
            fclose(fid);
        end

        function off = offsetOf(~, proto, name)
            offs = proto.getFieldOffsets();
            off = -1;
            for i = 1:numel(offs)
                if strcmp(offs{i}.name, name), off = offs{i}.byteOffset; end
            end
        end
    end

    methods (Test)

        function tcDefaultKeepsCAbiPadding(testCase)
            f = testCase.writeHeader('m_default.h', false);
            p = ScapyML.HeaderParser.parseFile(f, 'big');
            testCase.verifyEqual(testCase.offsetOf(p{1}, 'c'), 4);
            testCase.verifyEqual(p{1}.totalBytes(), 8);
        end

        function tcPackedOptionPlacesIntAtByte2(testCase)
            f = testCase.writeHeader('m_opt.h', false);
            p = ScapyML.HeaderParser.parseFile(f, 'big', true);
            testCase.verifyEqual(testCase.offsetOf(p{1}, 'c'), 2);
            testCase.verifyEqual(p{1}.totalBytes(), 6);

            out = fullfile(testCase.TempFolder, 'm_opt.lua');
            ScapyML.WiresharkDissector.generate(p{1}, out);
            testCase.verifyTrue(contains(fileread(out), 'buffer(2, 4)'), ...
                'Lua must read the 32-bit field from byte 2');
        end

        function tcPragmaPack1IsDetectedAutomatically(testCase)
            f = testCase.writeHeader('m_pragma.h', true);
            p = ScapyML.HeaderParser.parseFile(f, 'big');
            testCase.verifyEqual(testCase.offsetOf(p{1}, 'c'), 2);
            testCase.verifyEqual(p{1}.totalBytes(), 6);
        end

        function tcCliPackedFlagAndEncoding(testCase)
            f = testCase.writeHeader('m_cli.h', false);
            evalc('ScapyML(''load'', f, ''big'', ''packed'');');
            pkt = ScapyML.Packet('M');
            pkt.set('a', 1); pkt.set('b', 2); pkt.set('c', 16909060);  % 0x01020304
            bytes = pkt.build();
            testCase.verifyEqual(bytes, uint8([1 2 1 2 3 4]));
        end

    end
end
