classdef DiscriminatorConfig < handle
    % ScapyML.DiscriminatorConfig - Configuration for multi-protocol message discrimination
    %
    % Manages the configuration needed to distinguish between different protocols
    % that share the same UDP port. Each protocol can have its own discriminator
    % field at different offsets and sizes.
    %
    % Usage:
    %   config = ScapyML.DiscriminatorConfig();
    %   config.addProtocol('TemperatureSensor', 'msg_id', 0, 1, 0x01);
    %   config.addProtocol('PressureSensor', 'msg_id', 0, 1, 0x02);
    %   config.addProtocol('StatusMessage', 'msg_type', 2, 2, 0x1000);
    
    properties
        Protocols           % containers.Map: protocol name -> struct with config
        GlobalFieldName     % Common field name if all use same (optional)
        GlobalOffset        % Common offset if all use same (optional)
        GlobalSize          % Common size if all use same (optional)
    end
    
    methods
        function obj = DiscriminatorConfig()
            obj.Protocols = containers.Map('KeyType', 'char', 'ValueType', 'any');
            obj.GlobalFieldName = '';
            obj.GlobalOffset = [];
            obj.GlobalSize = [];
        end
        
        function addProtocol(obj, protoName, fieldName, offset, size, value)
            % Add protocol with its discriminator configuration
            %
            % Args:
            %   protoName  - Protocol name (e.g., 'TemperatureSensor')
            %   fieldName  - Discriminator field name (e.g., 'msg_id', 'msg_type')
            %   offset     - Byte offset from start of packet (0-based)
            %   size       - Size in bytes (1, 2, or 4)
            %   value      - Discriminator value for this protocol (e.g., 0x01)
            
            if ~ismember(size, [1, 2, 4])
                error('Discriminator size must be 1, 2, or 4 bytes');
            end
            
            config = struct();
            config.FieldName = fieldName;
            config.Offset = offset;
            config.Size = size;
            config.Value = value;
            
            obj.Protocols(protoName) = config;
        end
        
        function setGlobalConfig(obj, fieldName, offset, size)
            % Set global discriminator config (if all protocols use same field)
            obj.GlobalFieldName = fieldName;
            obj.GlobalOffset = offset;
            obj.GlobalSize = size;
        end
        
        function tf = hasGlobalConfig(obj)
            % Check if global configuration is set
            tf = ~isempty(obj.GlobalFieldName) && ...
                 ~isempty(obj.GlobalOffset) && ...
                 ~isempty(obj.GlobalSize);
        end
        
        function [fieldName, offset, size] = getProtocolConfig(obj, protoName)
            % Get discriminator config for a specific protocol
            if ~obj.Protocols.isKey(protoName)
                error('Protocol not found: %s', protoName);
            end
            
            config = obj.Protocols(protoName);
            fieldName = config.FieldName;
            offset = config.Offset;
            size = config.Size;
        end
        
        function value = getProtocolValue(obj, protoName)
            % Get discriminator value for a specific protocol
            if ~obj.Protocols.isKey(protoName)
                error('Protocol not found: %s', protoName);
            end
            
            config = obj.Protocols(protoName);
            value = config.Value;
        end
        
        function names = getProtocolNames(obj)
            % Get all protocol names
            names = obj.Protocols.keys();
        end
        
        function tf = validateUniqueness(obj)
            % Verify all discriminator values are unique for same field location
            %
            % Returns true if configuration is valid
            
            tf = true;
            
            % Group protocols by discriminator field location
            locationMap = containers.Map();
            
            protoNames = obj.Protocols.keys();
            for i = 1:numel(protoNames)
                name = protoNames{i};
                config = obj.Protocols(name);
                
                % Create unique key for this discriminator location
                locKey = sprintf('%s_%d_%d', config.FieldName, config.Offset, config.Size);
                
                if ~locationMap.isKey(locKey)
                    locationMap(locKey) = {};
                end
                
                % Add to list of protocols using this location
                protoList = locationMap(locKey);
                protoList{end+1} = struct('name', name, 'value', config.Value);
                locationMap(locKey) = protoList;
            end
            
            % Check each location for value collisions
            locations = locationMap.keys();
            for i = 1:numel(locations)
                protoList = locationMap(locations{i});
                
                % Check for duplicate values
                values = cellfun(@(x) x.value, protoList);
                if numel(unique(values)) < numel(values)
                    warning('Duplicate discriminator values found at location: %s', locations{i});
                    
                    % Find duplicates
                    [~, idx] = unique(values);
                    duplicateIdx = setdiff(1:numel(values), idx);
                    
                    for j = 1:numel(duplicateIdx)
                        fprintf('  Protocol: %s, Value: 0x%X\n', ...
                            protoList{duplicateIdx(j)}.name, ...
                            protoList{duplicateIdx(j)}.value);
                    end
                    
                    tf = false;
                end
            end
        end
        
        function saveToFile(obj, filename)
            % Save configuration to file
            fid = fopen(filename, 'w');
            if fid < 0
                error('Cannot write file: %s', filename);
            end
            
            fprintf(fid, '# ScapyML Multi-Protocol Discriminator Configuration\n');
            fprintf(fid, '# Generated: %s\n', datestr(now));
            fprintf(fid, '\n');
            
            % Global config (if set)
            if obj.hasGlobalConfig()
                fprintf(fid, '[Global]\n');
                fprintf(fid, 'FieldName = %s\n', obj.GlobalFieldName);
                fprintf(fid, 'Offset = %d\n', obj.GlobalOffset);
                fprintf(fid, 'Size = %d\n', obj.GlobalSize);
                fprintf(fid, '\n');
            end
            
            % Per-protocol config
            fprintf(fid, '[Protocols]\n');
            fprintf(fid, '# Format: ProtocolName = FieldName, Offset, Size, Value\n');
            
            protoNames = obj.Protocols.keys();
            for i = 1:numel(protoNames)
                name = protoNames{i};
                config = obj.Protocols(name);
                
                fprintf(fid, '%s = %s, %d, %d, 0x%X\n', ...
                    name, config.FieldName, config.Offset, config.Size, config.Value);
            end
            
            fclose(fid);
            fprintf('Discriminator configuration saved to: %s\n', filename);
        end
    end
    
    methods (Static)
        function obj = fromFile(filename)
            % Load configuration from file
            obj = ScapyML.DiscriminatorConfig();
            
            fid = fopen(filename, 'r');
            if fid < 0
                error('Cannot read file: %s', filename);
            end
            
            section = '';
            while ~feof(fid)
                line = fgetl(fid);
                if ~ischar(line), break; end
                
                % Skip comments and empty lines
                line = strtrim(line);
                if isempty(line) || startsWith(line, '#')
                    continue;
                end
                
                % Section headers
                if startsWith(line, '[') && endsWith(line, ']')
                    section = line(2:end-1);
                    continue;
                end
                
                % Parse based on section
                if strcmp(section, 'Global')
                    parts = strsplit(line, '=');
                    if numel(parts) == 2
                        key = strtrim(parts{1});
                        value = strtrim(parts{2});
                        
                        if strcmp(key, 'FieldName')
                            obj.GlobalFieldName = value;
                        elseif strcmp(key, 'Offset')
                            obj.GlobalOffset = str2double(value);
                        elseif strcmp(key, 'Size')
                            obj.GlobalSize = str2double(value);
                        end
                    end
                    
                elseif strcmp(section, 'Protocols')
                    parts = strsplit(line, '=');
                    if numel(parts) == 2
                        protoName = strtrim(parts{1});
                        configStr = strtrim(parts{2});
                        
                        % Parse: FieldName, Offset, Size, Value
                        configParts = strsplit(configStr, ',');
                        if numel(configParts) == 4
                            fieldName = strtrim(configParts{1});
                            offset = str2double(strtrim(configParts{2}));
                            size = str2double(strtrim(configParts{3}));
                            valueStr = strtrim(configParts{4});
                            
                            % Parse hex value
                            if startsWith(valueStr, '0x') || startsWith(valueStr, '0X')
                                value = hex2dec(valueStr(3:end));
                            else
                                value = str2double(valueStr);
                            end
                            
                            obj.addProtocol(protoName, fieldName, offset, size, value);
                        end
                    end
                end
            end
            
            fclose(fid);
            fprintf('Discriminator configuration loaded from: %s\n', filename);
        end
        
        function obj = fromGUI(protoNames)
            % Interactive GUI to configure discriminator
            obj = ScapyML.DiscriminatorConfig();
            
            % Create dialog
            fig = uifigure('Name', 'Protocol Discriminator Configuration', ...
                'Position', [100 100 800 500]);
            
            grid = uigridlayout(fig, [numel(protoNames) + 3, 5]);
            grid.ColumnWidth = {'2x', '1x', '1x', '1x', '1x'};
            grid.RowHeight = repmat({25}, 1, numel(protoNames) + 3);
            
            % Headers
            uilabel(grid, 'Text', 'Protocol', 'FontWeight', 'bold');
            uilabel(grid, 'Text', 'Field Name', 'FontWeight', 'bold');
            uilabel(grid, 'Text', 'Offset', 'FontWeight', 'bold');
            uilabel(grid, 'Text', 'Size', 'FontWeight', 'bold');
            uilabel(grid, 'Text', 'Value (hex)', 'FontWeight', 'bold');
            
            % Create input fields for each protocol
            fieldInputs = cell(numel(protoNames), 4);
            for i = 1:numel(protoNames)
                uilabel(grid, 'Text', protoNames{i});
                fieldInputs{i, 1} = uieditfield(grid, 'text', 'Value', 'msg_id');
                fieldInputs{i, 2} = uieditfield(grid, 'numeric', 'Value', 0);
                fieldInputs{i, 3} = uidropdown(grid, 'Items', {'1', '2', '4'}, 'Value', '1');
                fieldInputs{i, 4} = uieditfield(grid, 'text', 'Value', sprintf('0x%02X', i));
            end
            
            % Buttons
            uilabel(grid, 'Text', '');
            uilabel(grid, 'Text', '');
            uilabel(grid, 'Text', '');
            btnOK = uibutton(grid, 'Text', 'OK', 'ButtonPushedFcn', @(~,~) uiresume(fig));
            btnCancel = uibutton(grid, 'Text', 'Cancel', 'ButtonPushedFcn', @(~,~) delete(fig));
            
            % Wait for user
            uiwait(fig);
            
            % Process results if OK was pressed
            if isvalid(fig)
                for i = 1:numel(protoNames)
                    fieldName = fieldInputs{i, 1}.Value;
                    offset = fieldInputs{i, 2}.Value;
                    size = str2double(fieldInputs{i, 3}.Value);
                    valueStr = fieldInputs{i, 4}.Value;
                    
                    % Parse hex value
                    if startsWith(valueStr, '0x') || startsWith(valueStr, '0X')
                        value = hex2dec(valueStr(3:end));
                    else
                        value = str2double(valueStr);
                    end
                    
                    obj.addProtocol(protoNames{i}, fieldName, offset, size, value);
                end
                
                delete(fig);
            else
                obj = [];
            end
        end
    end
end
