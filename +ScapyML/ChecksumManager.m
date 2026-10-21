classdef ChecksumManager
% ScapyML.ChecksumManager - Calculate checksums using user-defined formulas
%
% Manages checksum calculations with user-defined formulas applied after
% packet encoding. The checksum value is computed from the binary data
% and written back to a designated field.
%
% CHECKSUM FILE FORMAT:
%   fieldName = @(data) expression
%
% Where:
%   - fieldName: Field to store checksum result
%   - data: uint8 array of complete packet binary
%   - expression: MATLAB code that returns checksum value
%
% Example checksums.txt:
%   checksum = @(data) sum(data)
%   crc = @(data) mod(sum(uint16(data)), 65536)
%   xor_checksum = @(data) sum(arrayfun(@(k) mod(sum(bitget(data, k)), 2) * 2^(k-1), 1:8))
%   header_sum = @(data) mod(sum(data(1:10)), 256)
%
% USAGE:
%   % Create manager
%   cm = ScapyML.ChecksumManager('checksums.txt');
%   
%   % Apply checksum to packet
%   pkt = ScapyML.Packet('MyProtocol');
%   pkt.set('msg_id', 42);
%   pkt = cm.applyChecksums(pkt);  % Computes and sets checksum field(s)
%   
%   % Encode with checksums
%   binary = pkt.build();

    properties (Access = private)
        Checksums  % containers.Map: fieldName -> function_handle
    end
    
    methods
        function obj = ChecksumManager(checksumFile)
            % Constructor - load checksum formulas from file
            % If no file specified or file doesn't exist, creates empty manager
            
            obj.Checksums = containers.Map('KeyType', 'char', 'ValueType', 'any');
            
            if nargin == 0 || isempty(checksumFile)
                return;  % Empty manager - no checksums
            end
            
            if ~isfile(checksumFile)
                warning('ScapyML:ChecksumManager:FileNotFound', ...
                    'Checksum file not found: %s', checksumFile);
                return;
            end
            
            try
                obj.loadFromFile(checksumFile);
            catch ME
                warning('ScapyML:ChecksumManager:LoadError', ...
                    'Error loading checksums: %s', ME.message);
            end
        end
        
        function bytes = applyChecksums(obj, bytes, pkt)
            % Apply all checksums to raw byte array.
            %
            % Correct algorithm:
            %   1. Resolve all checksum field offsets first.
            %   2. Sort by byte offset (deterministic order, independent of Map key order).
            %   3. For each checksum field:
            %      a. ZERO the checksum field bytes in the buffer before computing —
            %         prevents the value from a previous build() call from being
            %         included in the sum, which would produce a different result
            %         each time build() is called.
            %      b. Compute the checksum over the zeroed buffer.
            %      c. Write the result back.

            if obj.Checksums.Count == 0
                return;
            end

            offsets = pkt.getFieldOffsets();
            checksumFields = obj.Checksums.keys();

            % Build list of {fieldName, offset, size} and sort by offset
            csEntries = {};
            for i = 1:numel(checksumFields)
                fieldName = checksumFields{i};
                for j = 1:numel(offsets)
                    if strcmp(offsets{j}.name, fieldName)
                        csEntries{end+1} = struct( ...
                            'name',   fieldName, ...
                            'offset', offsets{j}.byteOffset, ...
                            'size',   offsets{j}.sizeBytes);
                        break;
                    end
                end
                if numel(csEntries) < i
                    warning('ScapyML:ChecksumManager:FieldNotFound', ...
                        'Checksum field "%s" not found in protocol', fieldName);
                end
            end

            % Sort by byte offset — deterministic regardless of Map order
            if numel(csEntries) > 1
                offVec = cellfun(@(e) e.offset, csEntries);
                [~, sortIdx] = sort(offVec);
                csEntries = csEntries(sortIdx);
            end

            % Process each checksum in offset order
            for i = 1:numel(csEntries)
                e   = csEntries{i};
                fn  = e.name;
                try
                    checksumFunc = obj.Checksums(fn);

                    % --- Zero the checksum field before computing ---
                    % This ensures identical results on every build() call,
                    % even if the field already contains a previous checksum.
                    bytesForCalc = bytes;
                    bytesForCalc(e.offset+1 : e.offset+e.size) = 0;

                    checksumValue = checksumFunc(bytesForCalc);

                    if ~isnumeric(checksumValue) || ~isscalar(checksumValue)
                        warning('ScapyML:ChecksumManager:InvalidResult', ...
                            'Checksum function for "%s" must return scalar numeric', fn);
                        continue;
                    end

                    checksumValue = round(checksumValue);
                    bytes = obj.writeChecksumToBytes(bytes, checksumValue, ...
                        e.offset, e.size, pkt.getEndian());
                catch ME
                    warning('ScapyML:ChecksumManager:CalculationError', ...
                        'Error calculating checksum for "%s": %s', fn, ME.message);
                end
            end
        end
        
        function bytes = writeChecksumToBytes(~, bytes, value, offset, size, endian)
            % Write checksum value into byte array at specified offset
            %
            % ARGUMENTS:
            %   bytes - uint8 array
            %   value - checksum value (scalar)
            %   offset - byte offset where field starts (0-based)
            %   size - field size in bytes (1, 2, 4, 8)
            %   endian - 'big' or 'little'
            %
            % RETURNS:
            %   bytes - Updated byte array
            
            % Convert to uint64 for manipulation
            val = uint64(value);
            
            % Extract bytes based on size
            switch size
                case 1  % uint8
                    val = uint8(mod(val, 256));
                    bytes(offset+1) = val;
                    
                case 2  % uint16
                    val = uint16(mod(val, 65536));
                    if strcmp(endian, 'big')
                        bytes(offset+1) = uint8(bitshift(val, -8));
                        bytes(offset+2) = uint8(bitand(val, 255));
                    else  % little
                        bytes(offset+1) = uint8(bitand(val, 255));
                        bytes(offset+2) = uint8(bitshift(val, -8));
                    end
                    
                case 4  % uint32
                    val = uint32(val);
                    if strcmp(endian, 'big')
                        bytes(offset+1) = uint8(bitshift(val, -24));
                        bytes(offset+2) = uint8(bitand(bitshift(val, -16), 255));
                        bytes(offset+3) = uint8(bitand(bitshift(val, -8), 255));
                        bytes(offset+4) = uint8(bitand(val, 255));
                    else  % little
                        bytes(offset+1) = uint8(bitand(val, 255));
                        bytes(offset+2) = uint8(bitand(bitshift(val, -8), 255));
                        bytes(offset+3) = uint8(bitand(bitshift(val, -16), 255));
                        bytes(offset+4) = uint8(bitshift(val, -24));
                    end
                    
                case 8  % uint64
                    if strcmp(endian, 'big')
                        for i = 0:7
                            bytes(offset+i+1) = uint8(bitand(bitshift(val, -(56-i*8)), 255));
                        end
                    else  % little
                        for i = 0:7
                            bytes(offset+i+1) = uint8(bitand(bitshift(val, -i*8), 255));
                        end
                    end
                    
                otherwise
                    warning('ScapyML:ChecksumManager:UnsupportedSize', ...
                        'Unsupported checksum field size: %d bytes', size);
            end
        end
        
        function value = calculateChecksum(obj, fieldName, binaryData)
            % Calculate single checksum from binary data
            % Returns NaN if checksum not defined
            
            if ~obj.Checksums.isKey(fieldName)
                value = NaN;
                return;
            end
            
            checksumFunc = obj.Checksums(fieldName);
            
            try
                value = checksumFunc(binaryData);
                
                if ~isnumeric(value) || ~isscalar(value)
                    warning('ScapyML:ChecksumManager:InvalidResult', ...
                        'Checksum must return scalar numeric value');
                    value = NaN;
                end
            catch ME
                warning('ScapyML:ChecksumManager:CalculationError', ...
                    'Error: %s', ME.message);
                value = NaN;
            end
        end
        
        function tf = hasChecksum(obj, fieldName)
            % Check if a checksum is defined for this field
            tf = obj.Checksums.isKey(fieldName);
        end
        
        function names = listChecksums(obj)
            % Return list of fields with checksums defined
            names = obj.Checksums.keys();
        end
        
        function count = checksumCount(obj)
            % Return number of checksums defined
            count = obj.Checksums.Count;
        end
    end
    
    methods (Access = private)
        function loadFromFile(obj, filename)
            % Load checksum definitions from file
            % Format: fieldName = @(data) expression
            
            fid = fopen(filename, 'r');
            if fid < 0
                error('Cannot open file: %s', filename);
            end
            
            lineNum = 0;
            try
                while ~feof(fid)
                    line = fgetl(fid);
                    lineNum = lineNum + 1;
                    
                    if ~ischar(line)
                        continue;
                    end
                    
                    % Remove leading/trailing whitespace
                    line = strtrim(line);
                    
                    % Skip empty lines and comments
                    if isempty(line) || line(1) == '#' || line(1) == '%'
                        continue;
                    end
                    
                    % Parse: fieldName = @(data) expression
                    % Split on FIRST '=' only — prevents breaking on == <= >= !=
                    % inside lambda expressions such as: crc = @(d) mod(sum(d==0),256)
                    eqIdx = strfind(line, '=');
                    if isempty(eqIdx)
                        warning('ScapyML:ChecksumManager:ParseError', ...
                            'Line %d: Invalid format (expected "field = @(data) expr")', lineNum);
                        continue;
                    end
                    fieldName = strtrim(line(1 : eqIdx(1)-1));
                    funcStr   = strtrim(line(eqIdx(1)+1 : end));
                    
                    % Evaluate function string to create function handle
                    try
                        checksumFunc = eval(funcStr);
                        if ~isa(checksumFunc, 'function_handle')
                            warning('ScapyML:ChecksumManager:NotFunction', ...
                                'Line %d: Right side must be a function handle', lineNum);
                            continue;
                        end
                        
                        obj.Checksums(fieldName) = checksumFunc;
                    catch ME
                        warning('ScapyML:ChecksumManager:EvalError', ...
                            'Line %d: Error evaluating function: %s', lineNum, ME.message);
                    end
                end
                fclose(fid);
            catch ME
                fclose(fid);
                rethrow(ME);
            end
        end
    end
    
    methods (Static)
        function example()
            % Display example checksum file
            fprintf('\n');
            fprintf('=== Example Checksum File (checksums.txt) ===\n\n');
            fprintf('%% Simple sum of all bytes (modulo 256 for 8-bit)\n');
            fprintf('checksum = @(data) mod(sum(uint16(data)), 256)\n\n');
            fprintf('%% Sum of all bytes (16-bit result)\n');
            fprintf('checksum16 = @(data) mod(sum(uint16(data)), 65536)\n\n');
            fprintf('%% XOR of all bytes\n');
            fprintf('xor_checksum = @(data) sum(arrayfun(@(k) mod(sum(bitget(data, k)), 2) * 2^(k-1), 1:8))\n\n');
            fprintf('%% CRC-like: sum with carry\n');
            fprintf('crc = @(data) mod(sum(uint32(data)) + floor(sum(uint32(data))/256), 256)\n\n');
            fprintf('%% Header-only checksum (first 10 bytes)\n');
            fprintf('header_sum = @(data) mod(sum(uint16(data(1:min(10,end)))), 256)\n\n');
            fprintf('%% Ones complement sum (like IP checksum)\n');
            fprintf('ones_comp = @(data) bitcmp(mod(sum(uint16(data)), 65536), ''uint16'')\n\n');
            fprintf('%% Even parity (count of 1 bits)\n');
            fprintf('parity = @(data) mod(sum(bitget(data, 1:8, ''uint8'')), 2)\n\n');
            fprintf('=== End Example ===\n\n');
            fprintf('USAGE:\n');
            fprintf('  cm = ScapyML.ChecksumManager(''checksums.txt'');\n');
            fprintf('  pkt = ScapyML.Packet(''MyProtocol'');\n');
            fprintf('  pkt.set(''msg_id'', 42);\n');
            fprintf('  pkt = cm.applyChecksums(pkt);  %% Calculates and sets checksum\n');
            fprintf('  binary = pkt.build();\n\n');
        end
    end
end
