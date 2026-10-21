classdef TestManualUnionSuite < matlab.unittest.TestCase
% Anonymous struct/union blocks of the opposite kind to their parent must
% keep their own layout (previously they were flattened into the parent, so
% a bit-field struct inside a union overlapped itself and a union inside a
% struct became sequential), and the generated Lua must place union members
% at the same byte with consistent bit masks.

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

    methods (Test)

        function tcAnonymousBitStructInsideUnionSharesTheByte(testCase)
            f = fullfile(testCase.TempFolder, 'reg.h');
            fid = fopen(f, 'w');
            fprintf(fid, 'typedef union {\n  uint8_t raw;\n  struct { uint8_t hi:4; uint8_t lo:4; };\n} Reg;\n');
            fclose(fid);
            protos = ScapyML.HeaderParser.parseFile(f, 'big');
            offs = protos{1}.getFieldOffsets();
            byName = containers.Map();
            for i = 1:numel(offs), byName(offs{i}.name) = offs{i}; end
            testCase.verifyEqual(byName('raw').byteOffset, 0);
            testCase.verifyEqual(byName('hi').byteOffset, 0);
            testCase.verifyEqual(byName('hi').bitOffset, 0);
            testCase.verifyEqual(byName('lo').byteOffset, 0);
            testCase.verifyEqual(byName('lo').bitOffset, 4);   % NOT 0: lo follows hi inside the struct
            testCase.verifyEqual(protos{1}.totalBytes(), 1);

            out = fullfile(testCase.TempFolder, 'reg.lua');
            ScapyML.WiresharkDissector.generate(protos{1}, out);
            txt = fileread(out);
            testCase.verifyTrue(contains(txt, 'nil, 0xF0)'), 'hi mask must be 0xF0');
            testCase.verifyTrue(contains(txt, 'nil, 0xF)'),  'lo mask must be 0xF');
            testCase.verifyEqual(numel(strfind(txt, 'buffer(0, 1)')) >= 3, true, ...
                'raw, hi and lo must all be read from byte 0');
            testCase.verifyFalse(contains(txt, 'buffer(1, 1)'), ...
                'nothing may be shifted to byte 1');
        end

        function tcAnonymousUnionInsideStructOverlaps(testCase)
            f = fullfile(testCase.TempFolder, 'st.h');
            fid = fopen(f, 'w');
            fprintf(fid, 'typedef struct {\n  uint8_t a;\n  union { uint8_t x; uint8_t y; };\n  uint8_t b;\n} S;\n');
            fclose(fid);
            protos = ScapyML.HeaderParser.parseFile(f, 'big');
            offs = protos{1}.getFieldOffsets();
            byName = containers.Map();
            for i = 1:numel(offs), byName(offs{i}.name) = offs{i}.byteOffset; end
            testCase.verifyEqual(byName('a'), 0);
            testCase.verifyEqual(byName('x'), 1);
            testCase.verifyEqual(byName('y'), 1);   % same location as x
            testCase.verifyEqual(byName('b'), 2);
            testCase.verifyEqual(protos{1}.totalBytes(), 3);
        end

    end
end
