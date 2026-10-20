classdef ProtocolRegistry < handle
% ScapyML.ProtocolRegistry - Central registry for all defined protocols
% Maintains a map of protocol name -> ProtocolDef objects

    properties (Access = private)
        Registry  % containers.Map: name -> ProtocolDef
        Enums     % containers.Map: name -> EnumDef
    end

    methods
        function obj = ProtocolRegistry()
            obj.Registry = containers.Map('KeyType','char','ValueType','any');
            obj.Enums = containers.Map('KeyType','char','ValueType','any');
        end

        function register(obj, protoDef)
            % BUG FIX (KI-NEW-03): previously this silently overwrote an
            % existing protocol definition with the same name -- any
            % Packet objects constructed AFTER a silent overwrite would
            % use the new layout, which could confusingly appear as a
            % different byte layout for a "same-named" protocol across a
            % long-running session (e.g. the GUI, which loads headers
            % repeatedly without restarting). REQUIREMENTS.md section 8.3
            % claims unique protocol names are enforced; this warning
            % makes that claim actually true in observable behaviour
            % without breaking legitimate re-registration (e.g.
            % deliberately reloading an edited header).
            if obj.Registry.isKey(protoDef.Name)
                warning('ScapyML:ProtocolRegistry:Overwrite', ...
                    ['Protocol "%s" is already registered and is being overwritten. ' ...
                     'Any existing Packet objects built from the previous definition ' ...
                     'are unaffected, but new Packet(''%s'') calls will use the new layout.'], ...
                    protoDef.Name, protoDef.Name);
            end
            obj.Registry(protoDef.Name) = protoDef;
        end

        function proto = get(obj, name)
            if obj.Registry.isKey(name)
                proto = obj.Registry(name);
            else
                error('ScapyML:ProtocolRegistry:NotFound', ...
                    'Protocol "%s" not registered.', name);
            end
        end

        function tf = has(obj, name)
            tf = obj.Registry.isKey(name);
        end

        function names = list(obj)
            names = keys(obj.Registry);
        end
        
        % ----------------------------------------------------------------
        % Enum management
        % ----------------------------------------------------------------
        
        function registerEnum(obj, enumDef)
            % Register an enum definition
            if ~isa(enumDef, 'ScapyML.EnumDef')
                error('Must provide EnumDef object');
            end
            obj.Enums(enumDef.Name) = enumDef;
        end
        
        function enumDef = getEnum(obj, name)
            % Get enum by name
            if obj.Enums.isKey(name)
                enumDef = obj.Enums(name);
            else
                error('Enum not found: %s', name);
            end
        end

        function tf = hasEnum(obj, name)
            % Safe existence check for an enum (no error thrown).
            % Added v2.3.3 to support cross-file type resolution in
            % HeaderParser: struct/enum types defined in one .h file must
            % be resolvable when referenced from a field in a DIFFERENT
            % .h file parsed in a separate parseFile() call.
            tf = obj.Enums.isKey(name);
        end
        
        function names = listEnums(obj)
            % Get all enum names
            names = obj.Enums.keys;
        end
        
        function clearAll(obj)
            % Clear all registered protocols and enums
            obj.Registry = containers.Map('KeyType','char','ValueType','any');
            obj.Enums = containers.Map('KeyType','char','ValueType','any');
        end
    end

    methods (Static)
        function reg = instance()
            % Singleton accessor
            persistent inst;
            if isempty(inst) || ~isvalid(inst)
                inst = ScapyML.ProtocolRegistry();
            end
            reg = inst;
        end
        
        function clearInstance()
            % Clear the singleton's registered protocols/enums.
            %
            % Historical note (fixed v2.3.1): this previously called
            % clear('inst'), which clears a variable named 'inst' in
            % clearInstance()'s OWN workspace, not the persistent 'inst'
            % that lives inside instance()'s workspace. That made this
            % method a silent no-op. The fix simply delegates to the
            % singleton's own clearAll(), which is the reliable, already-
            % correct reset mechanism.
            ScapyML.ProtocolRegistry.instance().clearAll();
        end
    end
end
