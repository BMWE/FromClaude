classdef BitFieldGrouper
    % ScapyML.BitFieldGrouper - Groups consecutive bit-fields for Wireshark display
    %
    % Detects sequences of bit-fields that should be grouped together
    % in Wireshark dissector output
    
    methods (Static)
        function groups = findGroups(fields)
            % Find consecutive bit-field groups
            %
            % Returns cell array of group structures:
            %   {startIdx, endIdx, groupName, totalBits, startBitOffset}
            
            groups = {};
            if isempty(fields), return; end
            
            inGroup = false;
            groupStart = 0;
            groupBitOffset = 0;
            currentBitOffset = 0;
            
            for i = 1:numel(fields)
                f = fields{i};
                
                if ~isa(f, 'ScapyML.FieldDef')
                    % Nested structure - end any current group
                    if inGroup
                        groups{end+1} = struct('startIdx', groupStart, ...
                            'endIdx', i-1, ...
                            'startBitOffset', groupBitOffset);
                        inGroup = false;
                    end
                    
                    if isa(f, 'ScapyML.ProtocolDef')
                        currentBitOffset = currentBitOffset + f.TotalBits;
                    end
                    continue;
                end
                
                if f.IsBitField && ~f.IsArray
                    % Bit-field found
                    if ~inGroup
                        % Start new group
                        groupStart = i;
                        groupBitOffset = currentBitOffset;
                        inGroup = true;
                    end
                    currentBitOffset = currentBitOffset + f.BitSize;
                else
                    % Non-bit-field
                    if inGroup
                        % End current group
                        groups{end+1} = struct('startIdx', groupStart, ...
                            'endIdx', i-1, ...
                            'startBitOffset', groupBitOffset);
                        inGroup = false;
                    end
                    
                    % Update offset
                    if f.IsArray
                        if f.IsBitField
                            currentBitOffset = currentBitOffset + f.BitSize * f.ArraySize;
                        elseif strcmp(f.CType, 'float')
                            currentBitOffset = currentBitOffset + 32 * f.ArraySize;
                        elseif strcmp(f.CType, 'double')
                            currentBitOffset = currentBitOffset + 64 * f.ArraySize;
                        else
                            currentBitOffset = currentBitOffset + f.ByteSize * 8 * f.ArraySize;
                        end
                    else
                        if strcmp(f.CType, 'float')
                            currentBitOffset = currentBitOffset + 32;
                        elseif strcmp(f.CType, 'double')
                            currentBitOffset = currentBitOffset + 64;
                        else
                            currentBitOffset = currentBitOffset + f.ByteSize * 8;
                        end
                    end
                end
            end
            
            % Close any remaining group
            if inGroup
                groups{end+1} = struct('startIdx', groupStart, ...
                    'endIdx', numel(fields), ...
                    'startBitOffset', groupBitOffset);
            end
        end
        
        function name = generateGroupName(fields, startIdx, endIdx)
            % Generate a name for a bit-field group
            
            % Collect field names
            names = {};
            for i = startIdx:endIdx
                f = fields{i};
                if isa(f, 'ScapyML.FieldDef')
                    names{end+1} = f.Name; %#ok<AGROW>
                end
            end
            
            if numel(names) == 0
                name = 'bitfields';
                return;
            end
            
            % Try to find common prefix
            if numel(names) == 1
                name = names{1};
                return;
            end
            
            % Find longest common prefix
            prefix = names{1};
            for i = 2:numel(names)
                j = 1;
                while j <= min(length(prefix), length(names{i})) && ...
                      prefix(j) == names{i}(j)
                    j = j + 1;
                end
                prefix = prefix(1:j-1);
                if isempty(prefix), break; end
            end
            
            % Clean up prefix
            if ~isempty(prefix)
                % Remove trailing underscore
                if endsWith(prefix, '_')
                    prefix = prefix(1:end-1);
                end
                
                if length(prefix) >= 3
                    name = [prefix '_bits'];
                else
                    name = 'bitfields';
                end
            else
                name = 'bitfields';
            end
        end
    end
end
