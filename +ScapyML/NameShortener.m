classdef NameShortener
% ScapyML.NameShortener  Intelligently shorten field names to meet MATLAB's 63-char limit
%
% MATLAB field name limit: 63 characters (namelengthmax)
% 
% Strategy:
%   1. If name <= 63 chars: use as-is
%   2. If name > 63 chars: apply intelligent shortening
%
% Shortening rules (applied in order):
%   1. Remove common prefixes if repeated (level2_level3 → l2_level3)
%   2. Abbreviate structure names in path (MyStructure → MSt)
%   3. Keep final field name intact (preserve clarity)
%   4. Add hash suffix if needed for uniqueness
%
% Examples:
%   level2_level3_level4_deepest_level5_field1 (46 chars) → as-is
%   veryLongStructureNameForTesting_level3_level4_deepest_level5_field1 (69) 
%     → vLSNFT_l3_l4_deepest_l5_field1 (32 chars)

    methods (Static)
        
        function shortName = shorten(longName, maxLen)
            % Shorten a field name to fit within maxLen characters
            % Default maxLen = 63 (MATLAB's namelengthmax)
            if nargin < 2
                maxLen = 63;
            end
            
            % Already short enough?
            if length(longName) <= maxLen
                shortName = longName;
                return;
            end
            
            % Split by underscore to get path components
            parts = strsplit(longName, '_');
            
            if numel(parts) == 1
                % Single word - just truncate with hash
                shortName = ScapyML.NameShortener.truncateWithHash(longName, maxLen);
                return;
            end
            
            % Strategy: Keep last part (field name) intact, shorten path
            fieldName = parts{end};
            pathParts = parts(1:end-1);
            
            % Calculate available space for path
            % Reserve: fieldName + 1 underscore + 8 for hash if needed
            availableForPath = maxLen - length(fieldName) - 1;
            
            % Try progressive shortening strategies
            shortPath = ScapyML.NameShortener.shortenPath(pathParts, availableForPath);
            
            % Combine
            shortName = [shortPath '_' fieldName];
            
            % Still too long? Add hash and truncate
            if length(shortName) > maxLen
                shortName = ScapyML.NameShortener.truncateWithHash(shortName, maxLen);
            end
        end
        
        function shortPath = shortenPath(parts, maxLen)
            % Shorten a path (array of parts) to fit in maxLen
            
            % Strategy 1: Abbreviate repeated prefixes (level1, level2 → l1, l2)
            abbreviated = ScapyML.NameShortener.abbreviateCommonPrefixes(parts);
            testPath = strjoin(abbreviated, '_');
            if length(testPath) <= maxLen
                shortPath = testPath;
                return;
            end
            
            % Strategy 2: Abbreviate all structure names
            abbreviated = ScapyML.NameShortener.abbreviateAll(parts);
            testPath = strjoin(abbreviated, '_');
            if length(testPath) <= maxLen
                shortPath = testPath;
                return;
            end
            
            % Strategy 3: Ultra-short abbreviations (first letter + camelCase)
            abbreviated = ScapyML.NameShortener.ultraShort(parts);
            testPath = strjoin(abbreviated, '_');
            if length(testPath) <= maxLen
                shortPath = testPath;
                return;
            end
            
            % Strategy 4: Truncate to maxLen
            shortPath = testPath;
            if length(shortPath) > maxLen
                shortPath = shortPath(1:maxLen);
            end
        end
        
        function abbrev = abbreviateCommonPrefixes(parts)
            % Abbreviate common patterns: level1 → l1, struct2 → s2, etc.
            abbrev = cell(size(parts));
            for i = 1:numel(parts)
                part = parts{i};
                
                % Check for common prefixes with numbers
                if startsWith(part, 'level') && length(part) > 5
                    % level3 → l3
                    abbrev{i} = ['l' part(6:end)];
                elseif startsWith(part, 'struct') && length(part) > 6
                    % struct2 → s2
                    abbrev{i} = ['s' part(7:end)];
                elseif startsWith(part, 'field') && length(part) > 5
                    % field4 → f4
                    abbrev{i} = ['f' part(6:end)];
                else
                    abbrev{i} = part;
                end
            end
        end
        
        function abbrev = abbreviateAll(parts)
            % Abbreviate all parts using camelCase extraction
            abbrev = cell(size(parts));
            for i = 1:numel(parts)
                abbrev{i} = ScapyML.NameShortener.abbreviateName(parts{i});
            end
        end
        
        function abbrev = abbreviateName(name)
            % Abbreviate a single name using intelligent rules
            % Examples:
            %   MyStructure → MSt
            %   veryLongName → vLN
            %   simple → simple (if short enough)
            
            if length(name) <= 6
                abbrev = name;
                return;
            end
            
            % Find capital letters (camelCase)
            caps = find(isstrprop(name, 'upper'));
            
            if numel(caps) >= 2
                % Has camelCase - use capital letters
                abbrev = name(caps);
                % Add first lowercase if starts with lowercase
                if ~isempty(caps) && caps(1) > 1
                    abbrev = [name(1) abbrev];
                end
            else
                % No camelCase - use first + last + middle
                if length(name) >= 3
                    mid = ceil(length(name)/2);
                    abbrev = [name(1) name(mid) name(end)];
                else
                    abbrev = name;
                end
            end
            
            % Ensure at least 2 characters
            if length(abbrev) < 2 && length(name) >= 2
                abbrev = name(1:2);
            end
        end
        
        function abbrev = ultraShort(parts)
            % Ultra-short: first letter of each part
            abbrev = cell(size(parts));
            for i = 1:numel(parts)
                part = parts{i};
                if isempty(part)
                    abbrev{i} = 'x';
                else
                    % First char + length indicator for uniqueness
                    abbrev{i} = sprintf('%c%d', part(1), length(part));
                end
            end
        end
        
        function shortName = truncateWithHash(name, maxLen)
            % Truncate and add hash for uniqueness
            % Format: truncated_XXXXXXXX (8 hex digits)
            
            if maxLen < 10
                % Not enough space for hash, just truncate
                shortName = name(1:maxLen);
                return;
            end
            
            % Calculate hash
            hashVal = ScapyML.NameShortener.simpleHash(name);
            hashStr = dec2hex(hashVal, 8);  % 8 hex digits
            
            % Truncate to make room for _HASH
            truncLen = maxLen - 9;  % 9 = '_' + 8 hex digits
            shortName = [name(1:truncLen) '_' hashStr];
        end
        
        function hashVal = simpleHash(str)
            % Simple hash function for string uniqueness
            hashVal = 0;
            for i = 1:length(str)
                hashVal = mod(hashVal * 31 + double(str(i)), 2^32);
            end
            hashVal = mod(hashVal, 2^32 - 1);
        end
        
    end
end
