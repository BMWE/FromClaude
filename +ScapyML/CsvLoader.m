classdef CsvLoader
% ScapyML.CsvLoader  Read a CSV file and produce a cell-array of Packet objects.
%
% Rules:
%   - Column headers must match protocol field names (extra columns are ignored)
%   - Missing columns get their protocol default value (0)
%   - Empty cells leave the field at its default
%   - Numeric strings and hex strings (0x...) are supported
%
% Usage:
%   pkts = ScapyML.CsvLoader.load('data.csv', 'MyProtocol');
%   % pkts is a cell array; pkts{1}, pkts{2} ... are Packet objects

    methods (Static)

        function pkts = load(csvFile, protoName)
            % Load CSV and return a cell array of ScapyML.Packet objects.

            if ~isfile(csvFile)
                error('ScapyML:CsvLoader:FileNotFound', ...
                    'CSV file not found: %s', csvFile);
            end

            % Read the file line by line
            fid   = fopen(csvFile,'r');
            lines = {};
            while ~feof(fid)
                ln = fgetl(fid);
                if ischar(ln)
                    lines{end+1} = ln; %#ok<AGROW>
                end
            end
            fclose(fid);

            if isempty(lines)
                pkts = {};
                return;
            end

            % Parse header row
            headers = ScapyML.CsvLoader.splitLine(lines{1});
            headers = strtrim(headers);

            % Parse data rows
            pkts = {};
            for row = 2:numel(lines)
                ln = strtrim(lines{row});
                if isempty(ln), continue; end

                cells = ScapyML.CsvLoader.splitLine(ln);

                pkt = ScapyML.Packet(protoName);

                for col = 1:min(numel(headers), numel(cells))
                    fname = strtrim(headers{col});
                    raw   = strtrim(cells{col});

                    if isempty(fname) || isempty(raw)
                        continue;
                    end

                    % Convert to number
                    val = ScapyML.CsvLoader.parseNum(raw);
                    if ~isnan(val)
                        try
                            pkt.set(fname, val);
                        catch
                            % Field not in protocol - silently skip
                        end
                    end
                end

                pkts{end+1} = pkt; %#ok<AGROW>
            end
        end

        % ----------------------------------------------------------------
        % Bulk path (used by ScapyML_fromCSV and the GUI)
        % ----------------------------------------------------------------

        function T = readColumns(csvFile, wanted)
            % Read ONLY the columns whose names are in 'wanted' (cellstr).
            % Type detection is identical to readtable(csvFile); unwanted
            % columns are simply not converted/stored, which is the big
            % saving for wide files (e.g. 170 columns x 150k rows).
            opts   = detectImportOptions(csvFile);
            sel    = opts.VariableNames(ismember(opts.VariableNames, wanted));
            opts.SelectedVariableNames = sel;
            T = readtable(csvFile, opts);
        end

        function [pkts, cancelled] = buildPackets(proto, defaultValues, T, converter, progressFcn)
            % Build one Packet per row of table T.
            %   defaultValues - struct of ALL protocol fields at defaults
            %   converter     - ScapyML.ConversionManager
            %   progressFcn   - optional @(i,n) -> true to cancel
            % Conversions are applied once to the raw column (no double scaling).
            if nargin < 5, progressFcn = []; end
            cancelled = false;
            nRows = height(T);
            names = T.Properties.VariableNames;

            % -- extract mapped numeric columns, convert once per column --
            mappedNames = {};
            mappedVecs  = {};
            for j = 1:numel(names)
                fn = names{j};
                if ~isfield(defaultValues, fn), continue; end
                raw = T.(fn);
                if ~isnumeric(raw), continue; end
                if converter.hasConversion(fn)
                    raw = converter.convertVector(fn, raw);
                end
                mappedNames{end+1} = fn;  %#ok<AGROW>
                mappedVecs{end+1}  = raw; %#ok<AGROW>
            end

            % -- template cell row holding every protocol field's default --
            allNames = fieldnames(defaultValues);
            baseCell = struct2cell(defaultValues);          % nAll x 1
            [~, idx] = ismember(mappedNames, allNames);     % positions to override
            nMapped  = numel(mappedNames);

            pkts = cell(1, nRows);
            blockSize = 4096;                               % bounds memory
            updateStep = max(1, floor(nRows/200));
            for b0 = 1:blockSize:nRows
                rows = b0:min(b0+blockSize-1, nRows);
                nb   = numel(rows);
                blk  = cell(nb, nMapped);                   % keeps each column's class
                for k = 1:nMapped
                    blk(:,k) = num2cell(mappedVecs{k}(rows));
                end
                for r = 1:nb
                    i = rows(r);
                    v = baseCell;
                    v(idx) = blk(r,:);
                    pkts{i} = ScapyML.Packet.fromValues(proto, cell2struct(v, allNames, 1));
                    if ~isempty(progressFcn) && mod(i, updateStep) == 0
                        if progressFcn(i, nRows)
                            cancelled = true;
                            pkts = pkts(1:i);
                            return;
                        end
                    end
                end
            end
        end

        % ----------------------------------------------------------------
        % Helpers
        % ----------------------------------------------------------------

        function cells = splitLine(line)
            % Split a CSV line on commas, respecting double-quoted fields.
            cells = {};
            cur   = '';
            inQ   = false;

            for k = 1:numel(line)
                ch = line(k);
                if ch == '"'
                    inQ = ~inQ;
                elseif ch == ',' && ~inQ
                    cells{end+1} = cur; %#ok<AGROW>
                    cur = '';
                else
                    cur = [cur, ch]; %#ok<AGROW>
                end
            end
            cells{end+1} = cur;
        end

        function val = parseNum(s)
            % Parse a numeric string; supports decimal and 0x hex.
            % Returns the value in appropriate numeric type to preserve precision
            % Supports: int8, int16, int32, int64, uint8, uint16, uint32, uint64
            
            s = strtrim(s);
            
            if isempty(s)
                val = NaN;
                return;
            end
            
            % Check for hex notation
            if numel(s) > 2 && s(1) == '0' && (s(2)=='x' || s(2)=='X')
                % Hex value - parse as unsigned
                hexStr = s(3:end);
                
                % Determine size based on number of hex digits
                numDigits = length(hexStr);
                
                if numDigits <= 2
                    % uint8: 0x00 to 0xFF
                    val = uint8(hex2dec(hexStr));
                elseif numDigits <= 4
                    % uint16: 0x0000 to 0xFFFF
                    val = uint16(hex2dec(hexStr));
                elseif numDigits <= 8
                    % uint32: 0x00000000 to 0xFFFFFFFF
                    val = uint32(hex2dec(hexStr));
                else
                    % uint64: 0x0000000000000000 to 0xFFFFFFFFFFFFFFFF
                    % hex2dec maxes out at 2^52, so use sscanf for 64-bit
                    val = uint64(sscanf(hexStr, '%lx'));
                end
                
            else
                % Decimal value - preserve as double initially
                % MATLAB's str2double handles scientific notation and negatives
                val = str2double(s);
                
                % Don't convert to integer here - let Packet.set() handle it
                % This preserves negative values and allows proper range checking
            end
        end

    end
end
