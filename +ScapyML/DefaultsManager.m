classdef DefaultsManager
% ScapyML.DefaultsManager  Create and load default values files for protocols.
%
% Purpose:
%   Generate a text file listing all protocol fields with default values (0).
%   User can edit this file to set custom defaults.
%   Load defaults from file to initialize packet fields.
%   CSV data can then override specific fields while keeping other defaults.
%
% Usage:
%   % 1. Generate defaults file
%   ScapyML.DefaultsManager.create('MyProtocol', 'my_defaults.txt');
%
%   % 2. Edit my_defaults.txt manually to set desired defaults
%
%   % 3. Load defaults into a packet
%   pkt = ScapyML.Packet('MyProtocol');
%   pkt = ScapyML.DefaultsManager.apply(pkt, 'my_defaults.txt');
%
%   % 4. CSV can override specific fields
%   pkt.set('field1', csvValue1);
%   pkt.set('field2', csvValue2);
%
% File Format:
%   Each line: fieldname = value
%   Comments start with #
%   Blank lines ignored
%
% Example my_defaults.txt:
%   # Sensor packet defaults
%   header_msg_id = 1001
%   header_version = 2
%   temperature = 20.0
%   pressure = 101.325
%   status_active = 1
%   # status_calibrated defaults to 0 (not set)

    methods (Static)
        
        function create(protoName, outFile)
            % Generate a defaults file with all fields set to 0
            %
            % ScapyML.DefaultsManager.create('SensorData', 'defaults.txt')
            
            proto = ScapyML.ProtocolRegistry.instance().get(protoName);
            fields = proto.fieldNames();
            
            fid = fopen(outFile, 'w');
            if fid < 0
                error('ScapyML:DefaultsManager:WriteError', ...
                    'Cannot write file: %s', outFile);
            end
            
            % Write header
            fprintf(fid, '# Default values for protocol: %s\n', protoName);
            fprintf(fid, '# Generated: %s\n', datestr(now));
            fprintf(fid, '#\n');
            fprintf(fid, '# Format: fieldname = value\n');
            fprintf(fid, '# Lines starting with # are comments\n');
            fprintf(fid, '# Edit values as needed, then load with:\n');
            fprintf(fid, '#   pkt = ScapyML.Packet(''%s'');\n', protoName);
            fprintf(fid, '#   pkt = ScapyML.DefaultsManager.apply(pkt, ''%s'');\n', outFile);
            fprintf(fid, '#\n');
            fprintf(fid, '# Total fields: %d\n', numel(fields));
            fprintf(fid, '#\n\n');
            
            % Write all fields with default value 0
            for k = 1:numel(fields)
                fn = fields{k};
                % Find the field def to check type
                fd = ScapyML.DefaultsManager.findFieldInProto(proto, fn);
                
                if ~isempty(fd)
                    if strcmp(fd.CType, 'float') || strcmp(fd.CType, 'double')
                        defaultVal = '0.0';
                    else
                        defaultVal = '0';
                    end
                    fprintf(fid, '%-40s = %s\n', fn, defaultVal);
                else
                    fprintf(fid, '%-40s = 0\n', fn);
                end
            end
            
            fclose(fid);
            fprintf('[ScapyML] Defaults file created: %s (%d fields)\n', ...
                outFile, numel(fields));
        end
        
        function pkt = apply(pkt, defaultsFile)
            % Load default values from file and apply to packet
            %
            % pkt = ScapyML.DefaultsManager.apply(pkt, 'defaults.txt')
            
            if ~exist(defaultsFile, 'file')
                error('ScapyML:DefaultsManager:FileNotFound', ...
                    'Defaults file not found: %s', defaultsFile);
            end
            
            fid = fopen(defaultsFile, 'r');
            if fid < 0
                error('ScapyML:DefaultsManager:ReadError', ...
                    'Cannot read file: %s', defaultsFile);
            end
            
            lineNum = 0;
            count = 0;
            
            while ~feof(fid)
                line = fgetl(fid);
                lineNum = lineNum + 1;
                
                if ~ischar(line), break; end
                
                % Strip leading/trailing whitespace
                line = strtrim(line);
                
                % Skip empty lines and comments
                if isempty(line) || startsWith(line, '#')
                    continue;
                end
                
                % Parse line: fieldname = value
                parts = strsplit(line, '=');
                if numel(parts) ~= 2
                    warning('ScapyML:DefaultsManager:ParseError', ...
                        'Line %d: Invalid format (expected "field = value"): %s', ...
                        lineNum, line);
                    continue;
                end
                
                fieldName = strtrim(parts{1});
                valueStr  = strtrim(parts{2});
                
                % Parse value
                try
                    % Try as numeric first
                    if contains(valueStr, '.') || contains(lower(valueStr), 'e')
                        % Float/double
                        value = str2double(valueStr);
                    else
                        % Integer (could be hex)
                        if startsWith(lower(valueStr), '0x')
                            value = hex2dec(valueStr(3:end));
                        else
                            value = str2double(valueStr);
                        end
                    end
                    
                    if isnan(value)
                        warning('ScapyML:DefaultsManager:ParseError', ...
                            'Line %d: Cannot parse value: %s', lineNum, valueStr);
                        continue;
                    end
                    
                    % Set field value
                    pkt.set(fieldName, value);
                    count = count + 1;
                    
                catch ME
                    warning('ScapyML:DefaultsManager:SetError', ...
                        'Line %d: Cannot set field "%s": %s', ...
                        lineNum, fieldName, ME.message);
                end
            end
            
            fclose(fid);
            fprintf('[ScapyML] Loaded %d default values from: %s\n', ...
                count, defaultsFile);
        end
        
        function fd = findFieldInProto(proto, fieldName)
            % Recursively find a field definition by name
            fd = [];
            for k = 1:numel(proto.Fields)
                f = proto.Fields{k};
                if isa(f, 'ScapyML.FieldDef')
                    if strcmp(f.Name, fieldName)
                        fd = f;
                        return;
                    end
                elseif isa(f, 'ScapyML.ProtocolDef')
                    fd = ScapyML.DefaultsManager.findFieldInProto(f, fieldName);
                    if ~isempty(fd)
                        return;
                    end
                end
            end
        end
        
    end
end
