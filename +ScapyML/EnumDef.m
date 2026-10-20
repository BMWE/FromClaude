classdef EnumDef
    % ScapyML.EnumDef - Represents a C enum definition
    %
    % Properties:
    %   Name        - Enum name
    %   Values      - Map of name -> value
    %   Description - Comment from header
    
    properties
        Name        (1,:) char = ''
        Values             % containers.Map: name -> numeric value
        Description (1,:) char = ''
    end
    
    methods
        function obj = EnumDef(name)
            if nargin == 0, return; end
            obj.Name = name;
            obj.Values = containers.Map('KeyType', 'char', 'ValueType', 'double');
        end
        
        function obj = addValue(obj, name, value)
            % Add an enum value
            obj.Values(name) = value;
        end
        
        function value = getValue(obj, name)
            % Get numeric value for enum name
            if obj.Values.isKey(name)
                value = obj.Values(name);
            else
                error('Enum %s does not have value %s', obj.Name, name);
            end
        end
        
        function name = getName(obj, value)
            % Get enum name for numeric value
            keys = obj.Values.keys;
            vals = obj.Values.values;
            for i = 1:numel(vals)
                if vals{i} == value
                    name = keys{i};
                    return;
                end
            end
            error('Enum %s does not have numeric value %d', obj.Name, value);
        end
        
        function names = allNames(obj)
            % Get all enum value names
            names = obj.Values.keys;
        end
        
        function disp(obj)
            fprintf('Enum: %s\n', obj.Name);
            if ~isempty(obj.Description)
                fprintf('  %s\n', obj.Description);
            end
            names = obj.allNames();
            for i = 1:numel(names)
                fprintf('  %s = %d\n', names{i}, obj.Values(names{i}));
            end
        end
    end
end
