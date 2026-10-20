classdef ConversionManager
% ScapyML.ConversionManager - Convert physical values to wire format
%
% Manages field-specific conversion functions for translating physical
% values from CSV to packet wire representation.
%
% CONVERSION FILE FORMAT:
%   fieldName = conversionFunction
%
% Example conversions.txt:
%   azimuth = @(x) round(x / 360 * 65536)
%   elevation = @(x) round((x + 90) / 180 * 65536)
%   temperature = @(x) round((x + 40) * 10)
%   status = @(x) x
%
% USAGE:
%   % Load conversions
%   cm = ScapyML.ConversionManager('conversions.txt');
%   
%   % Convert value
%   wireValue = cm.convert('azimuth', 60.0);  % Returns 10922
%   
%   % Check if field has conversion
%   if cm.hasConversion('azimuth')
%       ...
%   end

    properties (Access = private)
        Conversions  % containers.Map: fieldName -> function_handle
    end
    
    methods
        function obj = ConversionManager(conversionFile)
            % Constructor - load conversions from file
            % If no file specified or file doesn't exist, creates empty manager
            
            obj.Conversions = containers.Map('KeyType', 'char', 'ValueType', 'any');
            
            if nargin == 0 || isempty(conversionFile)
                return;  % Empty manager - no conversions
            end
            
            if ~isfile(conversionFile)
                warning('ScapyML:ConversionManager:FileNotFound', ...
                    'Conversion file not found: %s', conversionFile);
                return;
            end
            
            try
                obj.loadFromFile(conversionFile);
            catch ME
                warning('ScapyML:ConversionManager:LoadError', ...
                    'Error loading conversions: %s', ME.message);
            end
        end
        
        function wireValue = convert(obj, fieldName, physicalValue)
            % Convert physical value to wire format
            % If no conversion defined, returns physical value unchanged
            
            if obj.Conversions.isKey(fieldName)
                convFunc = obj.Conversions(fieldName);
                try
                    wireValue = convFunc(physicalValue);
                catch ME
                    warning('ScapyML:ConversionManager:ConversionError', ...
                        'Error converting field "%s": %s (using direct value)', ...
                        fieldName, ME.message);
                    wireValue = physicalValue;
                end
            else
                % No conversion defined - direct assignment
                wireValue = physicalValue;
            end
        end
        
        function tf = hasConversion(obj, fieldName)
            % Check if a conversion is defined for this field
            tf = obj.Conversions.isKey(fieldName);
        end
        
        function names = listConversions(obj)
            % Return list of fields with conversions defined
            names = obj.Conversions.keys();
        end
        
        function count = conversionCount(obj)
            % Return number of conversions defined
            count = obj.Conversions.Count;
        end
    end
    
    methods (Access = private)
        function loadFromFile(obj, filename)
            % Load conversion definitions from file
            % Format: fieldName = @(x) expression
            
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
                    
                    % Parse: fieldName = @(x) expression
                    % Split on FIRST '=' only — prevents breaking on == <= >= !=
                    % inside lambda expressions such as: status = @(x) (x == 1)*100
                    eqIdx = strfind(line, '=');
                    if isempty(eqIdx)
                        warning('ScapyML:ConversionManager:ParseError', ...
                            'Line %d: Invalid format (expected "field = @(x) expr")', lineNum);
                        continue;
                    end
                    fieldName = strtrim(line(1 : eqIdx(1)-1));
                    funcStr   = strtrim(line(eqIdx(1)+1 : end));
                    
                    % Evaluate function string to create function handle
                    try
                        convFunc = eval(funcStr);
                        if ~isa(convFunc, 'function_handle')
                            warning('ScapyML:ConversionManager:NotFunction', ...
                                'Line %d: Right side must be a function handle', lineNum);
                            continue;
                        end
                        
                        obj.Conversions(fieldName) = convFunc;
                    catch ME
                        warning('ScapyML:ConversionManager:EvalError', ...
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
            % Display example conversion file
            fprintf('\n');
            fprintf('=== Example Conversion File (conversions.txt) ===\n\n');
            fprintf('%% Azimuth: 0-359.995 deg -> 0-65535 (16-bit)\n');
            fprintf('azimuth = @(x) round(x / 360 * 65536)\n\n');
            fprintf('%% Elevation: -90 to +90 deg -> 0-65535 (16-bit)\n');
            fprintf('elevation = @(x) round((x + 90) / 180 * 65536)\n\n');
            fprintf('%% Temperature: -40 to +85 C -> 0-1250 (0.1 deg resolution)\n');
            fprintf('temperature = @(x) round((x + 40) * 10)\n\n');
            fprintf('%% Pressure: 300-1100 hPa -> 0-65535 (16-bit)\n');
            fprintf('pressure = @(x) round((x - 300) / 800 * 65536)\n\n');
            fprintf('%% Status: direct mapping (no conversion)\n');
            fprintf('status = @(x) x\n\n');
            fprintf('=== End Example ===\n\n');
            fprintf('USAGE:\n');
            fprintf('  cm = ScapyML.ConversionManager(''conversions.txt'');\n');
            fprintf('  wireValue = cm.convert(''azimuth'', 60.0);  %% Returns 10922\n\n');
        end
    end
end
