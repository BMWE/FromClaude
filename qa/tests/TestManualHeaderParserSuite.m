classdef TestManualHeaderParserSuite < matlab.unittest.TestCase
% Automated equivalents of the manual HeaderParser test cases in STR.md
% Section 1 (TC-HDR-*). This file intentionally does NOT re-implement
% cases already covered by TestHeaderParser.m (flat primitive struct,
% named/anonymous-tag enums, enum 4-byte field width, single-byte
% bit-fields, fixed arrays, nested named struct member names, union
% parses without error, explicit endianness, struct alignment padding,
% garbage input doesn't crash, and 'auto'-resolved cross-file enum
% reference with reversed load order).
%
% KI-NEW-06 STATUS: FIXED (history retained below for context).
% STR.md originally described a macro-name array size (e.g.
% "uint8_t data[MAX_LEN];") as producing only a warning with arraySize
% silently defaulting to 1. Tracing +ScapyML/HeaderParser.m's parseField
% line-by-line showed this was NOT what actually happened: when the
% array-size token was non-numeric, the code raised the
% ScapyML:Parser:InvalidArray warning but did NOT advance the token
% cursor past the invalid token, so the very next check (for a closing
% ']') always failed too, throwing a confusing, unrelated
% ScapyML:Parser:MissingBracket error. The fix consolidates this into ONE
% clear, actionable ScapyML:Parser:InvalidArray ERROR that names the bad
% token and explains macros aren't expanded — no more silent 1-element
% fallback (which risked worse, undetected downstream corruption) and no
% more confusing cascaded error. tcHdrNeg005 below tests the current,
% fixed behavior.

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

        function tcHdrFunc002_signedAndCharTypesGetCorrectByteSizes(testCase)
            % TC-HDR-FUNC-002 — signed integer types and char variants map
            % to the correct byte sizes.
            h = {
                'typedef struct SignedTypes {'
                '  int8_t  a;'
                '  int16_t b;'
                '  int32_t c;'
                '  int64_t d;'
                '  char    e;'
                '  signed char f;'
                '  unsigned char g;'
                '} SignedTypes;'
            };
            f = writeFixtureHeader(testCase.TempFolder, 'signed_types.h', h);
            protos = ScapyML.HeaderParser.parseFile(f, 'little');
            proto = protos{1};
            offs = proto.getFieldOffsets();

            expected = struct('a',1,'b',2,'c',4,'d',8,'e',1,'f',1,'g',1);
            fns = fieldnames(expected);
            for i = 1:numel(fns)
                info = testCase.findByName(offs, fns{i});
                testCase.verifyNotEmpty(info, sprintf('Field %s not found', fns{i}));
                testCase.verifyEqual(info.sizeBytes, expected.(fns{i}), ...
                    sprintf('Field %s expected %d bytes', fns{i}, expected.(fns{i})));
            end
        end

        function tcHdrFunc004_bitFieldCrossingByteBoundaryRoundTrips(testCase)
            % TC-HDR-FUNC-004 — a bit-field spanning more than one byte
            % (uint16_t b:12 following uint8_t a:4) parses without error
            % and its value round-trips correctly through encode/decode.
            h = {'typedef struct CrossByte { uint8_t a:4; uint16_t b:12; } CrossByte;'};
            f = writeFixtureHeader(testCase.TempFolder, 'crossbyte.h', h);
            testCase.verifyWarningFree(@() ScapyML.HeaderParser.parseFile(f, 'little'));

            pkt = ScapyML.Packet('CrossByte');
            pkt.set('a', 15);      % 0xF
            pkt.set('b', 2748);    % 0xABC
            bytes = pkt.build();

            decoded = ScapyML.Packet.fromBytes('CrossByte', bytes);
            testCase.verifyEqual(decoded.get('a'), 15);
            testCase.verifyEqual(decoded.get('b'), 2748);
        end

        function tcHdrFunc007_namedUnionMemberSemantics(testCase)
            % TC-HDR-FUNC-007 — a nested named union member: the top-level
            % type is a union (IsUnion=true), the nested struct member is
            % NOT a union (IsUnion=false), field names flatten to
            % raw/bytes_lo/bytes_hi, and totalBytes() is the MAX of member
            % sizes (2), not the sum.
            h = {
                'typedef union Word16 {'
                '  uint16_t raw;'
                '  struct { uint8_t lo; uint8_t hi; } bytes;'
                '} Word16;'
            };
            f = writeFixtureHeader(testCase.TempFolder, 'word16.h', h);
            protos = ScapyML.HeaderParser.parseFile(f, 'little');
            proto = protos{1};

            testCase.verifyTrue(proto.IsUnion, 'Word16 itself must be a union');
            testCase.verifyEqual(proto.totalBytes(), 2, ...
                'Union size must be the max of its members (2), not the sum');

            % The nested inline struct member ('bytes') must itself be a
            % plain struct (IsUnion=false), not inherit the parent union's
            % IsUnion flag.
            nestedChild = [];
            for i = 1:numel(proto.Fields)
                fEntry = proto.Fields{i};
                if isa(fEntry, 'ScapyML.ProtocolDef') && strcmp(fEntry.Name, 'bytes')
                    nestedChild = fEntry;
                end
            end
            testCase.verifyNotEmpty(nestedChild, ...
                'Nested "bytes" struct member should be represented as a child ProtocolDef');
            testCase.verifyFalse(nestedChild.IsUnion, ...
                'Nested struct-in-union member must not itself be flagged as a union');

            names = proto.fieldNames();
            testCase.verifyTrue(any(strcmp(names, 'raw')));
            testCase.verifyTrue(any(strcmp(names, 'bytes_lo')));
            testCase.verifyTrue(any(strcmp(names, 'bytes_hi')));
        end

        function tcHdrFunc008_anonymousInlineStructFlattensWithNoPrefix(testCase)
            % TC-HDR-FUNC-008 — a truly anonymous inline struct member (no
            % member name after the closing brace) flattens its fields
            % directly into the parent with NO name prefix.
            h = {
                'typedef struct Anon {'
                '  struct { uint8_t x; uint8_t y; };'
                '  uint8_t z;'
                '} Anon;'
            };
            f = writeFixtureHeader(testCase.TempFolder, 'anon.h', h);
            protos = ScapyML.HeaderParser.parseFile(f, 'little');
            proto = protos{1};
            names = proto.fieldNames();

            testCase.verifyTrue(any(strcmp(names, 'x')), ...
                'Anonymous inline struct field x must appear unprefixed');
            testCase.verifyTrue(any(strcmp(names, 'y')), ...
                'Anonymous inline struct field y must appear unprefixed');
            testCase.verifyTrue(any(strcmp(names, 'z')));
        end

        function tcHdrFunc009_enumExplicitValueResetsAutoIncrement(testCase)
            % TC-HDR-FUNC-009 — an explicit mid-sequence enum value resets
            % the auto-increment counter for subsequent unlabeled entries.
            h = {
                'typedef enum Status {'
                '  STATUS_IDLE = 0,'
                '  STATUS_ACTIVE = 1,'
                '  STATUS_ERROR = 5,'
                '  STATUS_UNKNOWN'
                '} Status;'
            };
            f = writeFixtureHeader(testCase.TempFolder, 'status_enum.h', h);
            ScapyML.HeaderParser.parseFile(f, 'little');

            e = ScapyML.ProtocolRegistry.instance().getEnum('Status');
            testCase.verifyEqual(e.getValue('STATUS_IDLE'), 0);
            testCase.verifyEqual(e.getValue('STATUS_ACTIVE'), 1);
            testCase.verifyEqual(e.getValue('STATUS_ERROR'), 5);
            testCase.verifyEqual(e.getValue('STATUS_UNKNOWN'), 6, ...
                'Auto-increment must resume from the last explicit value + 1');
        end

        function tcHdrFunc010_commentsAttachAsFieldDescriptions(testCase)
            % TC-HDR-FUNC-010 — line (//) and block (/* */) comments
            % immediately preceding a field attach as that field's
            % Description.
            h = {
                'typedef struct Hdr {'
                '  uint8_t id;   // message identifier'
                '  /* payload length in bytes */'
                '  uint16_t len;'
                '} Hdr;'
            };
            f = writeFixtureHeader(testCase.TempFolder, 'hdr_comments.h', h);
            protos = ScapyML.HeaderParser.parseFile(f, 'little');
            proto = protos{1};

            idField  = testCase.findFieldDef(proto, 'id');
            lenField = testCase.findFieldDef(proto, 'len');
            testCase.verifyEqual(idField.Description, 'message identifier');
            testCase.verifyEqual(lenField.Description, 'payload length in bytes');
        end

        function tcHdrFunc011_preprocessorDirectivesAreSkipped(testCase)
            % TC-HDR-FUNC-011 — #include/#define lines do not break
            % parsing; they are skipped by the tokeniser entirely.
            h = {
                '#include "foo.h"'
                '#define MAX_LEN 16'
                'typedef struct P {'
                '  uint8_t id;'
                '  uint8_t data[16];'
                '} P;'
            };
            f = writeFixtureHeader(testCase.TempFolder, 'preproc.h', h);
            testCase.verifyWarningFree(@() ScapyML.HeaderParser.parseFile(f, 'little'));

            proto = ScapyML.ProtocolRegistry.instance().get('P');
            names = proto.fieldNames();
            testCase.verifyTrue(any(strcmp(names, 'id')));
            testCase.verifyTrue(any(strcmp(names, 'data')));
        end

        function tcHdrFunc012_correctLoadOrderResolvesWithoutAutoFlag(testCase)
            % TC-HDR-FUNC-012 — when files are supplied in dependency-
            % correct order (dependency first), cross-file type resolution
            % succeeds with NO warning and no 'auto' flag needed.
            typesFile = writeFixtureHeader(testCase.TempFolder, 'aa_types.h', ...
                {'typedef enum MyEnum { A_VAL=0, B_VAL=1 } MyEnum;'});
            msgFile = writeFixtureHeader(testCase.TempFolder, 'aa_msg.h', ...
                {'typedef struct Msg { MyEnum e; uint8_t x; } Msg;'});

            testCase.verifyWarningFree(...
                @() ScapyML('load', {typesFile, msgFile}, 'little'));

            proto = ScapyML.ProtocolRegistry.instance().get('Msg');
            offs = proto.getFieldOffsets();
            eInfo = testCase.findByName(offs, 'e');
            testCase.verifyEqual(eInfo.sizeBytes, 4, ...
                'MyEnum field should resolve to 4 bytes when loaded in correct order');
        end

        function tcHdrFunc013_wrongLoadOrderWithoutAutoWarnsUnresolved(testCase)
            % TC-HDR-FUNC-013 — the mirror case of FUNC-012: loading the
            % DEPENDENT file before its dependency, with NO 'auto' flag,
            % must warn UnresolvedType and leave the field at 0 bytes
            % (documented limitation, not a silent corruption).
            typesFile = writeFixtureHeader(testCase.TempFolder, 'bb_types.h', ...
                {'typedef enum MyEnum2 { A_VAL=0, B_VAL=1 } MyEnum2;'});
            msgFile = writeFixtureHeader(testCase.TempFolder, 'bb_msg.h', ...
                {'typedef struct Msg2 { MyEnum2 e; uint8_t x; } Msg2;'});

            % Dependent file first, dependency second, NO 'auto' flag.
            testCase.verifyWarning(...
                @() ScapyML('load', {msgFile, typesFile}, 'little'), ...
                'ScapyML:HeaderParser:UnresolvedType');

            warnState = warning('off', 'ScapyML:HeaderParser:UnresolvedType');
            proto = ScapyML.ProtocolRegistry.instance().get('Msg2');
            warning(warnState);
            offs = proto.getFieldOffsets();
            eInfo = testCase.findByName(offs, 'e');
            testCase.verifyEqual(eInfo.sizeBytes, 0, ...
                'Unresolved cross-file type should fall back to 0 bytes, not crash');
        end

        function tcHdrNeg001_missingHeaderFileErrors(testCase)
            % TC-HDR-NEG-001 — loading a non-existent header file errors
            % with a clear, identifiable message.
            testCase.verifyError(...
                @() ScapyML.HeaderParser.parseFile('does_not_exist_xyz.h', 'little'), ...
                'ScapyML:HeaderParser:FileNotFound');
        end

        function tcHdrNeg003_multiDimensionalArrayRejected(testCase)
            % TC-HDR-NEG-003 — a 2D array declaration is explicitly
            % rejected rather than silently mishandled.
            h = {'typedef struct M { uint8_t matrix[4][4]; } M;'};
            f = writeFixtureHeader(testCase.TempFolder, 'multidim.h', h);
            testCase.verifyError(...
                @() ScapyML.HeaderParser.parseFile(f, 'little'), ...
                'ScapyML:Parser:MultiDimArray');
        end

        function tcHdrNeg004_missingClosingBracketErrors(testCase)
            % TC-HDR-NEG-004 — an array declaration missing its closing
            % ']' errors clearly rather than misparsing subsequent fields.
            h = {'typedef struct B { uint8_t data[16; uint8_t after; } B;'};
            f = writeFixtureHeader(testCase.TempFolder, 'missing_bracket.h', h);
            testCase.verifyError(...
                @() ScapyML.HeaderParser.parseFile(f, 'little'), ...
                'ScapyML:Parser:MissingBracket');
        end

        function tcHdrNeg005_macroArraySizeNowRaisesOneClearError(testCase)
            % TC-HDR-NEG-005 (KI-NEW-06 FIX CONFIRMATION) — an array size
            % given as a macro name (never expanded by this parser) used
            % to raise a WARNING (InvalidArray) immediately followed by an
            % unrelated-looking ERROR (MissingBracket), since the token
            % cursor wasn't advanced past the invalid token before the
            % next check ran. The fix consolidates this into ONE clear,
            % actionable ERROR (still identifier ScapyML:Parser:InvalidArray)
            % that explicitly explains macros aren't expanded, with no
            % separate/confusing MissingBracket error following it.
            h = {'typedef struct P { uint8_t data[MAX_LEN]; } P;'};
            f = writeFixtureHeader(testCase.TempFolder, 'macro_array.h', h);

            testCase.verifyError(...
                @() ScapyML.HeaderParser.parseFile(f, 'little'), ...
                'ScapyML:Parser:InvalidArray');

            % Confirm the error message is genuinely actionable (mentions
            % both the bad token and the "use a literal number" guidance),
            % not just a bare identifier.
            try
                ScapyML.HeaderParser.parseFile(f, 'little');
                testCase.verifyFail('Expected an error to be thrown');
            catch ME
                testCase.verifyTrue(contains(ME.message, 'MAX_LEN'), ...
                    'Error message should name the specific bad token');
                testCase.verifyTrue(contains(lower(ME.message), 'literal number'), ...
                    'Error message should guide the user toward the fix');
                testCase.verifyEqual(ME.identifier, 'ScapyML:Parser:InvalidArray');
            end
        end

        function tcHdrNeg006_completelyUndefinedTypeWarnsUnresolved(testCase)
            % TC-HDR-NEG-006 — referencing a type that is neither a
            % primitive, a locally-known struct/enum, nor a registered one
            % anywhere warns UnresolvedType; the struct still registers
            % (with a 0-byte field) rather than aborting entirely.
            h = {'typedef struct Bad { UnknownType x; uint8_t y; } Bad;'};
            f = writeFixtureHeader(testCase.TempFolder, 'bad_type.h', h);

            testCase.verifyWarning(...
                @() ScapyML.HeaderParser.parseFile(f, 'little'), ...
                'ScapyML:HeaderParser:UnresolvedType');

            warnState = warning('off', 'ScapyML:HeaderParser:UnresolvedType');
            proto = ScapyML.ProtocolRegistry.instance().get('Bad');
            warning(warnState);
            testCase.verifyNotEmpty(proto, ...
                'Struct should still register despite the unresolved field type');
            offs = proto.getFieldOffsets();
            xInfo = testCase.findByName(offs, 'x');
            testCase.verifyEqual(xInfo.sizeBytes, 0);
        end

    end

    methods (Access = private)
        function info = findByName(~, offsets, name)
            info = [];
            for i = 1:numel(offsets)
                if strcmp(offsets{i}.name, name)
                    info = offsets{i};
                    return;
                end
            end
        end

        function fd = findFieldDef(~, proto, name)
            fd = [];
            for i = 1:numel(proto.Fields)
                f = proto.Fields{i};
                if isprop(f, 'Name') && strcmp(f.Name, name)
                    fd = f;
                    return;
                end
            end
        end
    end
end
