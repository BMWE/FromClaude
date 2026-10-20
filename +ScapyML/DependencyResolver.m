classdef DependencyResolver
    % ScapyML.DependencyResolver - Automatically resolve header file dependencies
    %
    % Analyzes C header files to determine type dependencies and computes
    % the correct load order.
    
    methods (Static)
        function orderedFiles = resolveOrder(files)
            % Analyze dependencies and return files in correct load order
            %
            % Args:
            %   files - Cell array of file paths
            %
            % Returns:
            %   orderedFiles - Cell array of files in dependency order
            
            if ~iscell(files)
                files = {files};
            end
            
            % Parse each file to extract type definitions and dependencies
            typeMap = containers.Map();  % filename -> types it defines
            depsMap = containers.Map();  % filename -> types it uses
            
            fprintf('[DependencyResolver] Analyzing %d files...\n', numel(files));
            
            for i = 1:numel(files)
                file = files{i};
                [defines, uses] = ScapyML.DependencyResolver.analyzeFile(file);
                typeMap(file) = defines;
                depsMap(file) = uses;
                
                fprintf('  %s: defines %d types, uses %d types\n', ...
                    file, numel(defines), numel(uses));
            end
            
            % Build dependency graph
            orderedFiles = ScapyML.DependencyResolver.topologicalSort(files, typeMap, depsMap);
            
            fprintf('[DependencyResolver] Load order determined:\n');
            for i = 1:numel(orderedFiles)
                fprintf('  %d. %s\n', i, orderedFiles{i});
            end
        end
        
        function [defines, uses] = analyzeFile(filename)
            % Extract type definitions and dependencies from a file
            
            defines = {};  % Types this file defines
            uses = {};     % Types this file uses
            
            % Read file
            fid = fopen(filename, 'r');
            if fid < 0
                warning('Cannot open file: %s', filename);
                return;
            end
            content = fread(fid, '*char')';
            fclose(fid);
            
            % Remove comments to avoid false matches
            content = ScapyML.DependencyResolver.removeComments(content);
            
            % Find typedef definitions
            % Pattern: typedef struct/union Name { ... } Name;
            pattern = 'typedef\s+(struct|union)\s+(\w+)?\s*\{[^}]*\}\s*(\w+)\s*;';
            matches = regexp(content, pattern, 'tokens');
            for i = 1:numel(matches)
                typeName = matches{i}{3};  % Name after closing brace
                if ~isempty(typeName)
                    defines{end+1} = typeName; %#ok<AGROW>
                end
            end
            
            % Also catch: typedef struct Name { ... } Name;
            pattern2 = 'typedef\s+(struct|union)\s+(\w+)\s*\{[^}]*\}\s*\2\s*;';
            matches2 = regexp(content, pattern2, 'tokens');
            for i = 1:numel(matches2)
                typeName = matches2{i}{2};
                if ~ismember(typeName, defines)
                    defines{end+1} = typeName; %#ok<AGROW>
                end
            end

            % Fixed v2.3.3: also recognize enum typedefs (anonymous or
            % named tag: typedef enum [Tag] { ... } Name;). Without this,
            % a file defining ONLY an enum (e.g. a shared types.h) was
            % invisible to DependencyResolver, so a file using that enum
            % could be parsed before the enum's file, leaving the enum
            % unresolved and producing a silent 0-byte field
            % (see HeaderParser cross-file type resolution, v2.3.3).
            patternEnum = 'typedef\s+enum\s+(\w+)?\s*\{[^}]*\}\s*(\w+)\s*;';
            matchesEnum = regexp(content, patternEnum, 'tokens');
            for i = 1:numel(matchesEnum)
                typeName = matchesEnum{i}{2};  % Name after closing brace
                if ~isempty(typeName) && ~ismember(typeName, defines)
                    defines{end+1} = typeName; %#ok<AGROW>
                end
            end
            
            % Find type usage in struct/union bodies
            % Look for known patterns: TypeName fieldname;
            structBodies = regexp(content, '\{([^}]*)\}', 'tokens');
            for i = 1:numel(structBodies)
                body = structBodies{i}{1};
                
                % Find field declarations: Type name;
                lines = strsplit(body, {';', '\n'});
                for j = 1:numel(lines)
                    line = strtrim(lines{j});
                    if isempty(line), continue; end
                    
                    % Skip if it's a primitive type or bit-field
                    if contains(line, 'uint') || contains(line, 'int') || ...
                       contains(line, 'float') || contains(line, 'double') || ...
                       contains(line, 'char') || contains(line, ':')
                        continue;
                    end
                    
                    % Extract potential type name (first word)
                    tokens = strsplit(line);
                    if numel(tokens) >= 2
                        potentialType = tokens{1};
                        % Check if it looks like a custom type (starts with capital or contains underscore)
                        if ~isempty(regexp(potentialType, '^[A-Z]', 'once')) || contains(potentialType, '_')
                            if ~ismember(potentialType, uses) && ~ismember(potentialType, defines)
                                uses{end+1} = potentialType; %#ok<AGROW>
                            end
                        end
                    end
                end
            end
        end
        
        function content = removeComments(content)
            % Remove C-style comments from content
            
            % Remove // comments
            content = regexprep(content, '//[^\n]*', '');
            
            % Remove /* */ comments
            content = regexprep(content, '/\*.*?\*/', '', 'dotexceptnewline');
            
            % Remove multi-line /* */ comments
            while true
                [startIdx, endIdx] = regexp(content, '/\*.*?\*/', 'once');
                if isempty(startIdx), break; end
                content = [content(1:startIdx-1), content(endIdx+1:end)];
            end
        end
        
        function orderedFiles = topologicalSort(files, typeMap, depsMap)
            % Perform topological sort on dependency graph with circular detection
            n          = numel(files);
            visited    = false(1, n);
            inProgress = false(1, n);
            result     = {};

            % Build reverse lookup: type -> file that defines it
            typeToFile = containers.Map();
            for i = 1:n
                defines = typeMap(files{i});
                for j = 1:numel(defines)
                    typeToFile(defines{j}) = files{i};
                end
            end

            % Visit each file — receive updated visited/inProgress on each call
            for i = 1:n
                if ~visited(i)
                    [result, visited, inProgress] = ScapyML.DependencyResolver.dfsVisit( ...
                        i, files, visited, inProgress, result, depsMap, typeToFile);
                end
            end

            orderedFiles = result;
        end

        function [result, visited, inProgress] = dfsVisit(idx, files, visited, inProgress, result, depsMap, typeToFile)
            % Depth-first search visit for topological sort.
            %
            % visited and inProgress are returned (not just input) so that
            % mutations made in recursive calls propagate back to the caller.
            % MATLAB passes arrays by value; without returning them, the caller
            % sees stale copies, causing re-visits and missing circular detection.

            % Circular dependency: this node is currently on the DFS stack
            if inProgress(idx)
                error('ScapyML:CircularDependency', ...
                    'Circular dependency detected involving file: %s', files{idx});
            end

            % Already fully processed
            if visited(idx)
                return;
            end

            inProgress(idx) = true;   % Mark as on current DFS path
            file = files{idx};

            % Visit dependencies first
            uses = depsMap(file);
            for i = 1:numel(uses)
                typeName = uses{i};
                if typeToFile.isKey(typeName)
                    depFile = typeToFile(typeName);
                    depIdx  = find(strcmp(files, depFile), 1);
                    if ~isempty(depIdx) && ~visited(depIdx)
                        % *** Return updated visited/inProgress — critical fix ***
                        [result, visited, inProgress] = ScapyML.DependencyResolver.dfsVisit( ...
                            depIdx, files, visited, inProgress, result, depsMap, typeToFile);
                    end
                end
            end

            % Add this file after all its dependencies
            result{end+1}  = file;
            visited(idx)    = true;    % Mark as fully processed
            inProgress(idx) = false;   % Remove from current DFS path
        end
    end
end
