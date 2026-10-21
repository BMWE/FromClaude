classdef TestManualDependencyResolverSuite < matlab.unittest.TestCase
% Automated equivalent of the one remaining manual DependencyResolver test
% case not already covered by the extensive existing TestDependencyResolver.m
% (which already covers: analyzeFile finding defined struct/enum/anonymous-
% tag-enum types, finding used custom types, linear dependency chain
% ordering, circular dependency detection via dfsVisit, dfsVisit's
% pass-by-value mutation-propagation regression, and independent files
% with no shared types).

    methods (Test)

        function tcDepErr002_analyzeFileOnMissingFileWarnsAndReturnsEmpty(testCase)
            % TC-DEP-ERR-002 — analyzeFile() on an unreadable/missing file
            % warns "Cannot open file: %s" and returns empty
            % defines/uses, rather than erroring — this allows
            % resolveOrder() to continue processing the REMAINING files in
            % a multi-file load even if one path is bad.
            %
            % Note: the source calls plain warning('Cannot open file: %s',
            % filename) with NO custom identifier, so the resulting
            % warning has an empty identifier ('') — matlab.unittest's
            % verifyWarning identifier-matching is unreliable for that
            % case, so we use lastwarn() directly instead.
            lastwarn('');
            [defines, uses] = ScapyML.DependencyResolver.analyzeFile('no_such_header_xyz.h');
            [warnMsg, ~] = lastwarn();

            testCase.verifyNotEmpty(warnMsg, ...
                'Expected a warning to be raised for an unreadable file');
            testCase.verifyTrue(contains(warnMsg, 'Cannot open file'));
            testCase.verifyEmpty(defines);
            testCase.verifyEmpty(uses);
        end

        function tcDepErr002b_resolveOrderContinuesPastOneBadFileInAList(testCase)
            % Companion test: resolveOrder() with one missing file mixed
            % in among otherwise-valid files should not crash outright —
            % the missing file simply contributes no defines/uses to the
            % dependency graph, and the valid files still resolve.
            import matlab.unittest.fixtures.TemporaryFolderFixture
            fixture = testCase.applyFixture(TemporaryFolderFixture);
            fGood = writeFixtureHeader(fixture.Folder, 'good_dep.h', ...
                {'typedef struct GoodDep { uint8_t v; } GoodDep;'});

            warnState = warning('off', 'all');
            ordered = ScapyML.DependencyResolver.resolveOrder(...
                {fGood, 'no_such_header_xyz.h'});
            warning(warnState);

            testCase.verifyEqual(numel(ordered), 2);
            testCase.verifyTrue(any(strcmp(ordered, fGood)));
        end

    end
end
