classdef TestManualPackedSuite < matlab.unittest.TestCase
% ScapyML layout is ALWAYS packed (no alignment padding):
% struct { unsigned char a; unsigned char b; unsigned int c; }
%   c at byte 2, struct size 6

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

        function tcLayoutIsAlwaysPacked(testCase)
            f = testCase.writeHeader('m_default.h', false);
            p = ScapyML.HeaderParser.parseFile(f, 'big');
            testCase.verifyEqual(testCase.offsetOf(p{1}, 'a'), 0);
            testCase.verifyEqual(testCase.offsetOf(p{1}, 'b'), 1);
            testCase.verifyEqual(testCase.offsetOf(p{1}, 'c'), 2);
            testCase.verifyEqual(p{1}.totalBytes(), 6);
        end

        function tcPragmaPackHeaderGivesTheSameLayout(testCase)
            f = testCase.writeHeader('m_pragma.h', true);
            p = ScapyML.HeaderParser.parseFile(f, 'big');
            testCase.verifyEqual(testCase.offsetOf(p{1}, 'c'), 2);
            testCase.verifyEqual(p{1}.totalBytes(), 6);
        end

        function tcLuaReadsIntFromByte2(testCase)
            f = testCase.writeHeader('m_lua.h', false);
            p = ScapyML.HeaderParser.parseFile(f, 'big');
            out = fullfile(testCase.TempFolder, 'm_lua.lua');
            ScapyML.WiresharkDissector.generate(p{1}, out);
            txt = fileread(out);
            testCase.verifyTrue(contains(txt, 'buffer(1, 1)'), 'second uint8 at byte 1');
            testCase.verifyTrue(contains(txt, 'buffer(2, 4)'), 'uint32 at byte 2');
        end

        function tcEncodingHasNoPadding(testCase)
            f = testCase.writeHeader('m_enc.h', false);
            evalc('ScapyML(''load'', f, ''big'');');
            pkt = ScapyML.Packet('M');
            pkt.set('a', 1); pkt.set('b', 2); pkt.set('c', 16909060);  % 0x01020304
            testCase.verifyEqual(pkt.build(), uint8([1 2 1 2 3 4]));
        end

        function tcNestedStructAndDoubleArePacked(testCase)
            f = fullfile(testCase.TempFolder, 'nested.h');
            fid = fopen(f, 'w');
            fprintf(fid, 'typedef struct { uint8_t t; uint16_t v; } Inner;\n');
            fprintf(fid, 'typedef struct { uint8_t a; Inner in; double d; } Outer;\n');
            fclose(fid);
            p = ScapyML.HeaderParser.parseFile(f, 'big');
            outer = p{2};
            testCase.verifyEqual(p{1}.totalBytes(), 3);      % 1 + 2
            testCase.verifyEqual(outer.totalBytes(), 12);    % 1 + 3 + 8
        end

    end
end
