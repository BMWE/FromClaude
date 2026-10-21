classdef TestManualProtocolRegistrySuite < matlab.unittest.TestCase
% Automated test for STR.md TC-REG-EDGE-001, confirming the KI-NEW-03 fix.
% This test case was documented in STR.md during the original manual test
% design pass but was never actually automated at the time (a gap
% discovered while fixing KI-NEW-03) -- added now since the fix directly
% changes this behavior.
%
% Does not re-implement the existing, already-thorough TestProtocolRegistry.m
% (register/get, list, enum registration/lookup, singleton identity,
% clearAll, clearInstance regression guard, NotFound errors).

    methods (TestMethodSetup)
        function clearRegistry(~)
            ScapyML.ProtocolRegistry.instance().clearAll();
        end
    end

    methods (Test)

        function tcRegEdge001_duplicateRegistrationNowWarns(testCase)
            % TC-REG-EDGE-001 (KI-NEW-03 FIX CONFIRMATION) — registering a
            % protocol name that's already registered now warns
            % ScapyML:ProtocolRegistry:Overwrite naming the protocol,
            % instead of silently replacing the old definition with no
            % diagnostic at all.
            reg = ScapyML.ProtocolRegistry.instance();

            protoA = ScapyML.ProtocolDef('P', 'little');
            fdA = ScapyML.FieldDef();
            fdA.Name = 'x';
            fdA.CType = 'uint8_t';
            fdA.ByteSize = 1;
            protoA = protoA.addField(fdA);
            reg.register(protoA);
            testCase.verifyEqual(reg.get('P').totalBytes(), 1);

            protoB = ScapyML.ProtocolDef('P', 'little');  % same name, different layout
            fdB1 = ScapyML.FieldDef();
            fdB1.Name = 'y';
            fdB1.CType = 'uint32_t';
            fdB1.ByteSize = 4;
            protoB = protoB.addField(fdB1);
            fdB2 = ScapyML.FieldDef();
            fdB2.Name = 'z';
            fdB2.CType = 'uint32_t';
            fdB2.ByteSize = 4;
            protoB = protoB.addField(fdB2);

            testCase.verifyWarning(...
                @() reg.register(protoB), ...
                'ScapyML:ProtocolRegistry:Overwrite');

            % The overwrite itself is still allowed to proceed (this is a
            % warning, not a hard block) -- confirms the fix is the
            % minimal, non-breaking version described in STR.md KI-NEW-03.
            warnState = warning('off', 'ScapyML:ProtocolRegistry:Overwrite');
            reg.register(protoB);
            warning(warnState);
            testCase.verifyEqual(reg.get('P').totalBytes(), 8);
        end

        function tcRegEdge001b_firstRegistrationDoesNotWarn(testCase)
            % Sanity companion: registering a NEW (not-yet-registered)
            % protocol name must NOT warn -- the check is specifically for
            % overwriting an existing entry, not a blanket warning on
            % every registration.
            reg = ScapyML.ProtocolRegistry.instance();
            proto = ScapyML.ProtocolDef('BrandNewProto', 'little');
            fd = ScapyML.FieldDef();
            fd.Name = 'x';
            fd.CType = 'uint8_t';
            fd.ByteSize = 1;
            proto = proto.addField(fd);

            testCase.verifyWarningFree(@() reg.register(proto));
        end

    end
end
