classdef TestManualMultiProtocolSuite < matlab.unittest.TestCase
% Automated equivalents of the manual MultiProtocolDissector /
% DiscriminatorConfig test cases in STR.md Section 14 (TC-MWSD-*). This
% file intentionally does NOT re-implement cases already covered by
% TestMultiProtocolDissector.m (two-protocol dissector generation,
% one-field-per-line output regression, ASCII hygiene,
% validateUniqueness() returning false for duplicate values).
%
% This file ALSO includes regression-guard tests for KI-NEW-02, now FIXED.
% ScapyML_GUI.m's discriminator dialog previously called DiscriminatorConfig
% methods (setDefaults, addMappingSimple, getMapping) and read
% ProtocolRegistry.Enums directly — none of which exist / are accessible on
% the real classes. The fix updated the GUI's CALLING code to use the real,
% already-existing public API (addProtocol, getProtocolValue, listEnums()/
% getEnum()) — it deliberately did NOT add stub methods to
% DiscriminatorConfig or make Enums public, since the real API was already
% correct and sufficient. tcMwsdEdgeKi02* below therefore remain valid,
% PASSING regression guards confirming that intentional, unchanged API
% surface (see TestManualGuiAndE2ESuite.m's tcGuiKi02* for confirmation
% that the GUI's calling code was the part that changed).

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

        function tcMwsdFunc002_generateThrowsOnDuplicateDiscriminatorValues(testCase)
            % TC-MWSD-FUNC-002 — beyond validateUniqueness() merely
            % returning false (already covered by the existing suite),
            % calling MultiProtocolDissector.generate() with a duplicate
            % configuration must actually throw an error and produce no
            % output file.
            h = {'typedef struct MsgX { uint8_t msgId; uint8_t v1; } MsgX;', ...
                 'typedef struct MsgY { uint8_t msgId; uint8_t v2; } MsgY;'};
            f = writeFixtureHeader(testCase.TempFolder, 'dup.h', h);
            ScapyML.HeaderParser.parseFile(f, 'little');

            disc = ScapyML.DiscriminatorConfig();
            disc.addProtocol('MsgX', 'msgId', 0, 1, 9);
            disc.addProtocol('MsgY', 'msgId', 0, 1, 9);  % duplicate value

            out = fullfile(testCase.TempFolder, 'dup.lua');
            testCase.verifyError(...
                @() ScapyML.MultiProtocolDissector.generate({'MsgX','MsgY'}, out, [], {}, disc), ...
                ?MException);
            testCase.verifyFalse(isfile(out), ...
                'No dissector file should be produced when discriminator values collide');
        end

        function tcMwsdFunc003_saveToFileFromFileRoundTrip(testCase)
            % TC-MWSD-FUNC-003 — DiscriminatorConfig.saveToFile()/
            % fromFile() round-trips field name, offset, size, and value
            % exactly for every configured protocol.
            cfg = ScapyML.DiscriminatorConfig();
            cfg.addProtocol('TemperatureSensor', 'msg_id', 0, 1, hex2dec('01'));
            cfg.addProtocol('PressureSensor', 'msg_id', 0, 1, hex2dec('02'));
            cfg.addProtocol('StatusMessage', 'msg_type', 2, 2, hex2dec('1000'));

            discFile = fullfile(testCase.TempFolder, 'disc_roundtrip.txt');
            cfg.saveToFile(discFile);

            cfg2 = ScapyML.DiscriminatorConfig.fromFile(discFile);

            [fn1, off1, sz1] = cfg2.getProtocolConfig('TemperatureSensor');
            testCase.verifyEqual(fn1, 'msg_id');
            testCase.verifyEqual(off1, 0);
            testCase.verifyEqual(sz1, 1);
            testCase.verifyEqual(cfg2.getProtocolValue('TemperatureSensor'), hex2dec('01'));

            [fn2, off2, sz2] = cfg2.getProtocolConfig('PressureSensor');
            testCase.verifyEqual(fn2, 'msg_id');
            testCase.verifyEqual(off2, 0);
            testCase.verifyEqual(sz2, 1);
            testCase.verifyEqual(cfg2.getProtocolValue('PressureSensor'), hex2dec('02'));

            [fn3, off3, sz3] = cfg2.getProtocolConfig('StatusMessage');
            testCase.verifyEqual(fn3, 'msg_type');
            testCase.verifyEqual(off3, 2);
            testCase.verifyEqual(sz3, 2);
            testCase.verifyEqual(cfg2.getProtocolValue('StatusMessage'), hex2dec('1000'));
        end

        function tcMwsdFunc001_endToEndProgrammaticMultiProtocolGeneration(testCase)
            % TC-MWSD-FUNC-001 — confirms the underlying generation engine
            % itself is sound when driven with a correctly-constructed
            % DiscriminatorConfig (the working, non-GUI path), producing
            % unique per-protocol ProtoField names and a discriminator
            % if/elseif chain.
            h = {'typedef struct TempSensor { uint8_t msgId; int16_t temp; } TempSensor;', ...
                 'typedef struct PressSensor { uint8_t msgId; uint32_t pressure; } PressSensor;'};
            f = writeFixtureHeader(testCase.TempFolder, 'sensors.h', h);
            ScapyML.HeaderParser.parseFile(f, 'little');

            cfg = ScapyML.DiscriminatorConfig();
            cfg.addProtocol('TempSensor', 'msgId', 0, 1, 1);
            cfg.addProtocol('PressSensor', 'msgId', 0, 1, 2);

            out = fullfile(testCase.TempFolder, 'sensors.lua');
            ScapyML.MultiProtocolDissector.generate(...
                {'TempSensor','PressSensor'}, out, 5000, {}, cfg);

            txt = fileread(out);
            testCase.verifyTrue(contains(txt, 'tempsensor_temp'), ...
                'Field ProtoField names should be prefixed per-protocol to avoid collisions');
            testCase.verifyTrue(contains(txt, 'presssensor_pressure'));
            testCase.verifyTrue(contains(txt, 'disc_value'), ...
                'A discriminator value read should drive an if/elseif dispatch chain');
        end

        % -----------------------------------------------------------
        % KI-NEW-02 characterization tests (GUI multi-protocol defect)
        % -----------------------------------------------------------

        function tcMwsdEdgeKi02a_discriminatorConfigLacksGuiExpectedMethods(testCase)
            % TC-MWSD-FUNC-004 (KI-NEW-02 fixed in the GUI; this class-level
            % guard remains valid) — ScapyML_GUI.m's discriminator dialog
            % USED TO call setDefaults(), addMappingSimple(), and
            % getMapping() on a DiscriminatorConfig instance -- it no
            % longer does (see TestManualGuiAndE2ESuite.m's tcGuiKi02*).
            % None of these methods exist on the real class, and the fix
            % deliberately did not add them (the GUI's calling code was
            % updated to use the real API instead). If this test starts
            % FAILING, it means one of these methods has been added —
            % update ScapyML_GUI.m accordingly and then delete/rewrite
            % this guard test, since its purpose (documenting the gap) is
            % then obsolete.
            cfg = ScapyML.DiscriminatorConfig();
            testCase.verifyFalse(ismethod(cfg, 'setDefaults'), ...
                'KI-NEW-02: setDefaults() does not exist on DiscriminatorConfig, but ScapyML_GUI.m calls it');
            testCase.verifyFalse(ismethod(cfg, 'addMappingSimple'), ...
                'KI-NEW-02: addMappingSimple() does not exist on DiscriminatorConfig, but ScapyML_GUI.m calls it');
            testCase.verifyFalse(ismethod(cfg, 'getMapping'), ...
                'KI-NEW-02: getMapping() does not exist on DiscriminatorConfig, but ScapyML_GUI.m calls it');

            % Confirm the REAL equivalents do exist, so this test fails
            % for the right reason (missing GUI-expected names) rather
            % than a totally broken class.
            testCase.verifyTrue(ismethod(cfg, 'setGlobalConfig'));
            testCase.verifyTrue(ismethod(cfg, 'addProtocol'));
            testCase.verifyTrue(ismethod(cfg, 'getProtocolConfig'));
            testCase.verifyTrue(ismethod(cfg, 'getProtocolValue'));
        end

        function tcMwsdEdgeKi02b_directCallToGuiExpectedMethodsErrors(testCase)
            % TC-MWSD-FUNC-004 (characterization) — actually attempting to
            % call the GUI's assumed methods must error with MATLAB's
            % standard "no method" error, precisely reproducing what
            % ScapyML_GUI.m's createConfigFromTable() experiences.
            cfg = ScapyML.DiscriminatorConfig();
            testCase.verifyError(...
                @() cfg.setDefaults('msg_id', 0, 1), ...
                ?MException);
            testCase.verifyError(...
                @() cfg.addMappingSimple('SomeProto', 1), ...
                ?MException);
            testCase.verifyError(...
                @() cfg.getMapping('SomeProto'), ...
                ?MException);
        end

        function tcMwsdEdgeKi02c_protocolRegistryEnumsPropertyIsPrivate(testCase)
            % TC-MWSD-FUNC-004 (characterization) — locks in the third
            % sub-defect behind KI-NEW-02: ScapyML_GUI.m's doGenerateMulti()
            % reads reg.Enums directly, but Enums is declared
            % 'properties (Access = private)' on ProtocolRegistry. External
            % access must error.
            reg = ScapyML.ProtocolRegistry.instance();
            testCase.verifyError(@() reg.Enums, ?MException);
        end

        function tcMwsdEdgeKi02d_correctPublicApiForEnumsExistsAsWorkaround(testCase)
            % Companion to Ki02c — confirms the CORRECT, already-public way
            % to obtain the same information (listEnums()/getEnum()) does
            % work, which is what ScapyML_GUI.m's doGenerateMulti() SHOULD
            % be using instead of the private reg.Enums access.
            h = {'typedef enum Kind { KIND_A=0, KIND_B=1 } Kind;'};
            f = writeFixtureHeader(testCase.TempFolder, 'kind.h', h);
            ScapyML.HeaderParser.parseFile(f, 'little');

            reg = ScapyML.ProtocolRegistry.instance();
            names = reg.listEnums();
            testCase.verifyTrue(any(strcmp(names, 'Kind')));
            e = reg.getEnum('Kind');
            testCase.verifyEqual(e.Name, 'Kind');
        end

    end
end
