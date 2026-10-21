classdef Codec
% ScapyML.Codec  Bit-accurate encode/decode engine for ProtocolDef objects.
%
% Handles:
%   - Primitive fields: uint8_t..uint64_t, int variants, float, double
%   - Bit-fields (arbitrary width, MSB-first packing)
%   - Big-endian and little-endian byte ordering (per field)
%   - Nested structs stored as ProtocolDef children in the field tree
%   - Unions: all direct children start at the SAME bit offset;
%     size = max child size (not sum)
%
% Union encoding:
%   Only fields that were explicitly set by the user are written inside
%   a union context.  Fields still at default (0) inside a union are
%   skipped so they cannot overwrite the member the user actually set.
%   The 'dirty' containers.Map passed to encodeFields tracks set fields.

    methods (Static)

        % ================================================================
        % ENCODE
        % encode(protoDef, values)           -- encode all fields
        % encode(protoDef, values, dirty)    -- dirty = containers.Map of
        %                                       field names explicitly set
        % ================================================================
        function bytes = encode(protoDef, values, dirty)
            if nargin < 3, dirty = []; end
            buf = zeros(1, protoDef.totalBytes(), 'uint8');
            buf = ScapyML.Codec.encodeFields(buf, protoDef.Fields, values, 0, ...
                                              protoDef.IsUnion, dirty);
            bytes = buf;
        end

        % ================================================================
        % DECODE
        % ================================================================
        function values = decode(protoDef, bytes)
            values = struct();
            values = ScapyML.Codec.decodeFields(protoDef.Fields, bytes, values, 0, ...
                                                 protoDef.IsUnion);
        end

        % ================================================================
        % Internal recursive encode
        %
        % requireDirty: propagated flag meaning "a union ancestor exists".
        %   When true, every field (even inside nested structs) must be in
        %   'dirty' to be written.  This prevents default-value fields in a
        %   struct-inside-union from overwriting the union member the user set.
        % ================================================================
        function buf = encodeFields(buf, fields, values, startBit, isUnion, dirty, requireDirty)
            if nargin < 7, requireDirty = false; end
            bitPos = startBit;

            for k = 1:numel(fields)
                f = fields{k};

                if isa(f, 'ScapyML.ProtocolDef')
                    childRequireDirty = requireDirty;
                    if isUnion
                        childStart        = startBit;   % all children at same offset
                        childRequireDirty = true;       % propagate dirty requirement
                    else
                        % Align nested struct/union start position (v2.3.1, KI-001)
                        alignBits = ScapyML.ProtocolDef.structAlignBits(f);
                        bitPos    = ScapyML.ProtocolDef.alignBitPos(bitPos, alignBits);
                        childStart = bitPos;
                    end

                    buf = ScapyML.Codec.encodeFields(buf, f.Fields, values, childStart, ...
                                                      f.IsUnion, dirty, childRequireDirty);
                    if ~isUnion
                        bitPos = bitPos + f.TotalBits;
                    end

                elseif isa(f, 'ScapyML.FieldDef')
                    if isUnion
                        fieldStart = startBit;
                    else
                        % Align field start position, except bit-fields
                        % which pack with no inter-field padding (v2.3.1, KI-001)
                        if ~f.IsBitField
                            alignBits = ScapyML.ProtocolDef.fieldAlignBytes(f) * 8;
                            bitPos    = ScapyML.ProtocolDef.alignBitPos(bitPos, alignBits);
                        end
                        fieldStart = bitPos;
                    end

                    % Write the field only if:
                    %   (a) no union ancestor -> always write, OR
                    %   (b) union ancestor exists -> only write if explicitly set (dirty)
                    needDirtyCheck = isUnion || requireDirty;
                    shouldWrite    = true;
                    if needDirtyCheck && ~isempty(dirty) && isa(dirty,'containers.Map')
                        shouldWrite = dirty.isKey(f.Name);
                    end

                    if shouldWrite
                        buf = ScapyML.Codec.encodeOne(buf, f, values, fieldStart);
                    end

                    if ~isUnion
                        bitPos = fieldStart + ScapyML.Codec.fieldBits(f);
                    end
                end
            end
        end

        function buf = encodeOne(buf, f, values, bitPos)
            % Get field value(s)
            if ~isfield(values, f.Name) || isempty(values.(f.Name))
                val = zeros(1, max(1, f.ArraySize));
            else
                val = values.(f.Name);
            end
            
            isFloat  = strcmp(f.CType, 'float');
            isDouble = strcmp(f.CType, 'double');
            
            % Determine if signed - handle ALL C integer types
            ctype = lower(f.CType);
            if contains(ctype, 'unsigned') || contains(f.CType, 'uint') || ...
               strcmp(ctype, 'byte') || strcmp(ctype, 'word') || ...
               strcmp(ctype, 'dword') || strcmp(ctype, 'qword') || ...
               startsWith(ctype, 'u_') || startsWith(ctype, 'u8') || ...
               startsWith(ctype, 'u16') || startsWith(ctype, 'u32') || startsWith(ctype, 'u64')
                isSigned = false;
            elseif (contains(f.CType, 'int') && ~contains(f.CType, 'uint')) || ...
                   contains(ctype, 'short') || contains(ctype, 'long') || ...
                   startsWith(ctype, 'signed') || strcmp(ctype, 'signed') || ...
                   startsWith(ctype, 's8') || startsWith(ctype, 's16') || ...
                   startsWith(ctype, 's32') || startsWith(ctype, 's64')
                isSigned = true;
            elseif contains(ctype, 'char')
                isSigned = ~contains(ctype, 'unsigned');
            else
                isSigned = false;
            end
            
            % Handle arrays
            if f.IsArray
                % Ensure val is correct length
                if numel(val) < f.ArraySize
                    val(end+1:f.ArraySize) = 0;  % Pad with zeros
                elseif numel(val) > f.ArraySize
                    val = val(1:f.ArraySize);  % Truncate
                end
                
                % Encode each element
                currentBitPos = bitPos;
                for idx = 1:f.ArraySize
                    elemVal = val(idx);
                    
                    % For signed integers, convert negative to two's complement
                    if isSigned && elemVal < 0 && ~isFloat && ~isDouble
                        if f.ByteSize == 1  % int8
                            elemVal = uint64(typecast(int8(elemVal), 'uint8'));
                        elseif f.ByteSize == 2  % int16
                            elemVal = uint64(typecast(int16(elemVal), 'uint16'));
                        elseif f.ByteSize == 4  % int32
                            elemVal = uint64(typecast(int32(elemVal), 'uint32'));
                        elseif f.ByteSize == 8  % int64
                            elemVal = typecast(int64(elemVal), 'uint64');
                        end
                    end
                    
                    if f.IsBitField
                        buf = ScapyML.Codec.writeBits(buf, currentBitPos, f.BitSize, uint64(elemVal), f.Endian, false, true);
                        currentBitPos = currentBitPos + f.BitSize;
                    elseif isFloat
                        buf = ScapyML.Codec.writeBits(buf, currentBitPos, 32, elemVal, f.Endian, true, false);
                        currentBitPos = currentBitPos + 32;
                    elseif isDouble
                        buf = ScapyML.Codec.writeBits(buf, currentBitPos, 64, elemVal, f.Endian, true, false);
                        currentBitPos = currentBitPos + 64;
                    else
                        buf = ScapyML.Codec.writeBits(buf, currentBitPos, f.ByteSize*8, uint64(elemVal), f.Endian, false, false);
                        currentBitPos = currentBitPos + f.ByteSize*8;
                    end
                end
            else
                % Single value (not array)
                if numel(val) > 1
                    val = val(1);  % Take first element if array passed
                end
                val = double(val);
                
                % Encode single value
                isFloat  = strcmp(f.CType, 'float');
                isDouble = strcmp(f.CType, 'double');
                
                % Determine if signed - handle ALL C integer types
                ctype = lower(f.CType);
                if contains(ctype, 'unsigned') || contains(f.CType, 'uint') || ...
                   strcmp(ctype, 'byte') || strcmp(ctype, 'word') || ...
                   strcmp(ctype, 'dword') || strcmp(ctype, 'qword') || ...
                   startsWith(ctype, 'u_') || startsWith(ctype, 'u8') || ...
                   startsWith(ctype, 'u16') || startsWith(ctype, 'u32') || startsWith(ctype, 'u64')
                    isSigned = false;
                elseif (contains(f.CType, 'int') && ~contains(f.CType, 'uint')) || ...
                       contains(ctype, 'short') || contains(ctype, 'long') || ...
                       startsWith(ctype, 'signed') || strcmp(ctype, 'signed') || ...
                       startsWith(ctype, 's8') || startsWith(ctype, 's16') || ...
                       startsWith(ctype, 's32') || startsWith(ctype, 's64')
                    isSigned = true;
                elseif contains(ctype, 'char')
                    isSigned = ~contains(ctype, 'unsigned');
                else
                    isSigned = false;
                end
                
                % For signed integers, convert to unsigned using two's complement
                if isSigned && val < 0 && ~isFloat && ~isDouble
                    % Two's complement conversion
                    if f.ByteSize == 1  % int8
                        val = uint64(typecast(int8(val), 'uint8'));
                    elseif f.ByteSize == 2  % int16
                        val = uint64(typecast(int16(val), 'uint16'));
                    elseif f.ByteSize == 4  % int32
                        val = uint64(typecast(int32(val), 'uint32'));
                    elseif f.ByteSize == 8  % int64
                        val = typecast(int64(val), 'uint64');
                    end
                end
                
                if f.IsBitField
                    buf = ScapyML.Codec.writeBits(buf, bitPos, f.BitSize, uint64(val), f.Endian, false, true);
                elseif isFloat
                    buf = ScapyML.Codec.writeBits(buf, bitPos, 32, val, f.Endian, true, false);
                elseif isDouble
                    buf = ScapyML.Codec.writeBits(buf, bitPos, 64, val, f.Endian, true, false);
                else
                    buf = ScapyML.Codec.writeBits(buf, bitPos, f.ByteSize*8, uint64(val), f.Endian, false, false);
                end
            end
        end

        % ================================================================
        % Internal recursive decode
        %
        % Union decode strategy:
        %   A union is inherently ambiguous — multiple members share the same
        %   bytes. We decode ALL members (for informational completeness) but
        %   also store the raw bytes under a special key so callers can apply
        %   their own discriminator.
        %   The 'activeUnionMember' hint is NOT set here — that is a caller
        %   responsibility based on a discriminator field outside the union.
        % ================================================================
        function values = decodeFields(fields, bytes, values, startBit, isUnion)
            bitPos = startBit;

            for k = 1:numel(fields)
                f = fields{k};

                if isa(f, 'ScapyML.ProtocolDef')
                    if isUnion
                        childStart = startBit;
                    else
                        % Align nested struct/union start position (v2.3.1, KI-001)
                        alignBits = ScapyML.ProtocolDef.structAlignBits(f);
                        bitPos    = ScapyML.ProtocolDef.alignBitPos(bitPos, alignBits);
                        childStart = bitPos;
                    end
                    values = ScapyML.Codec.decodeFields(f.Fields, bytes, values, childStart, f.IsUnion);

                    % For unions: store raw bytes covering the union range
                    % so callers can apply a discriminator if needed
                    if f.IsUnion
                        byteStart  = floor(childStart / 8) + 1;
                        nBytes     = ceil(f.TotalBits / 8);
                        byteEnd    = min(byteStart + nBytes - 1, numel(bytes));
                        rawKey     = sprintf('%s__raw', f.Name);
                        values.(rawKey) = bytes(byteStart:byteEnd);
                    end

                    if ~isUnion
                        bitPos = bitPos + f.TotalBits;
                    end

                elseif isa(f, 'ScapyML.FieldDef')
                    if isUnion
                        fieldStart = startBit;
                    else
                        % Align field start position, except bit-fields
                        % which pack with no inter-field padding (v2.3.1, KI-001)
                        if ~f.IsBitField
                            alignBits = ScapyML.ProtocolDef.fieldAlignBytes(f) * 8;
                            bitPos    = ScapyML.ProtocolDef.alignBitPos(bitPos, alignBits);
                        end
                        fieldStart = bitPos;
                    end
                    values = ScapyML.Codec.decodeOne(f, bytes, values, fieldStart);
                    if ~isUnion
                        bitPos = fieldStart + ScapyML.Codec.fieldBits(f);
                    end
                end
            end
        end

        function values = decodeOne(f, bytes, values, bitPos)
            isFloat  = strcmp(f.CType, 'float');
            isDouble = strcmp(f.CType, 'double');

            if f.IsArray
                % Decode array elements
                val = zeros(1, f.ArraySize);
                currentBitPos = bitPos;
                
                % Calculate element size in bits
                if f.IsBitField
                    elemBits = f.BitSize;
                elseif isFloat
                    elemBits = 32;
                elseif isDouble
                    elemBits = 64;
                else
                    elemBits = f.ByteSize * 8;
                end
                
                % Check if enough data available
                totalBitsNeeded = f.ArraySize * elemBits;
                availableBits = numel(bytes) * 8;
                if (bitPos + totalBitsNeeded) > availableBits
                    error('ScapyML:Codec:InsufficientData', ...
                        'Insufficient data to decode array field "%s": need %d bits, have %d bits available', ...
                        f.Name, totalBitsNeeded, availableBits - bitPos);
                end
                
                for idx = 1:f.ArraySize
                    if f.IsBitField
                        val(idx) = ScapyML.Codec.readBits(bytes, currentBitPos, f.BitSize, f.Endian, false);
                        currentBitPos = currentBitPos + f.BitSize;
                    elseif isFloat
                        val(idx) = ScapyML.Codec.readBits(bytes, currentBitPos, 32, f.Endian, true);
                        currentBitPos = currentBitPos + 32;
                    elseif isDouble
                        val(idx) = ScapyML.Codec.readBits(bytes, currentBitPos, 64, f.Endian, true);
                        currentBitPos = currentBitPos + 64;
                    else
                        val(idx) = ScapyML.Codec.readBits(bytes, currentBitPos, f.ByteSize*8, f.Endian, false);
                        currentBitPos = currentBitPos + f.ByteSize*8;
                    end
                end
            else
                % Single value - check bounds
                if f.IsBitField
                    bitsNeeded = f.BitSize;
                elseif isFloat
                    bitsNeeded = 32;
                elseif isDouble
                    bitsNeeded = 64;
                else
                    bitsNeeded = f.ByteSize * 8;
                end
                
                availableBits = numel(bytes) * 8;
                if (bitPos + bitsNeeded) > availableBits
                    error('ScapyML:Codec:InsufficientData', ...
                        'Insufficient data to decode field "%s": need %d bits, have %d bits available', ...
                        f.Name, bitsNeeded, availableBits - bitPos);
                end
                
                if f.IsBitField
                    val = ScapyML.Codec.readBits(bytes, bitPos, f.BitSize, f.Endian, false);
                elseif isFloat
                    val = ScapyML.Codec.readBits(bytes, bitPos, 32, f.Endian, true);
                elseif isDouble
                    val = ScapyML.Codec.readBits(bytes, bitPos, 64, f.Endian, true);
                else
                    val = ScapyML.Codec.readBits(bytes, bitPos, f.ByteSize*8, f.Endian, false);
                end
            end
            values.(f.Name) = val;
        end

        function bits = fieldBits(f)
            % Calculate bits for single element
            if f.IsBitField
                bits = f.BitSize;
            elseif strcmp(f.CType, 'float')
                bits = 32;
            elseif strcmp(f.CType, 'double')
                bits = 64;
            else
                bits = f.ByteSize * 8;
            end
            
            % Multiply by array size
            if f.IsArray
                bits = bits * f.ArraySize;
            end
        end

        % ================================================================
        % Bit I/O helpers
        % ================================================================

        function buf = writeBits(buf, startBit, numBits, value, endian, isFloat, isBitField)
            if nargin < 6, isFloat = false; end
            if nargin < 7, isBitField = false; end
            if numBits == 0, return; end

            if isFloat
                if numBits == 32
                    rawBytes = typecast(single(value), 'uint8');
                elseif numBits == 64
                    rawBytes = typecast(double(value), 'uint8');
                else
                    error('ScapyML:Codec:InvalidFloat','Float must be 32 or 64 bits');
                end
                if strcmp(endian, 'little')
                    for b = 0:numel(rawBytes)-1
                        buf = ScapyML.Codec.writeBits(buf, startBit+b*8, 8, rawBytes(b+1), 'big', false, false);  % Not bit-field
                    end
                else
                    for b = 0:numel(rawBytes)-1
                        buf = ScapyML.Codec.writeBits(buf, startBit+b*8, 8, rawBytes(end-b), 'big', false, false);  % Not bit-field
                    end
                end
                return;
            end

            if strcmp(endian, 'big') || numBits <= 8
                % Historical note (fixed v2.3.1): bit-fields previously used
                % a separate "LSB-first" placement branch (isBitField=true)
                % that disagreed with THIS SAME FUNCTION's normal-field
                % MSB-first placement, with readBits() (which has no
                % isBitField concept and always reads MSB-first), and with
                % WiresharkDissector's mask/shift formula (which assumes
                % MSB-first). The result was a three-way inconsistency:
                % encoding then decoding a bit-field through ScapyML's own
                % Codec produced the WRONG value, and Wireshark-generated
                % dissectors could not correctly decode ANY bit-field.
                %
                % Fix: bit-fields now use the identical MSB-first placement
                % as normal fields. isBitField no longer affects placement;
                % the parameter is retained for API compatibility and to
                % document intent at call sites.
                for b = numBits-1:-1:0
                    bitVal = bitand(bitshift(value, -(b)), 1);
                    absPos = startBit + (numBits - 1 - b);
                    byteIdx   = floor(absPos / 8) + 1;
                    bitOffset = 7 - mod(absPos, 8);
                    if byteIdx <= numel(buf) && bitVal
                        buf(byteIdx) = bitor(buf(byteIdx), uint8(bitshift(uint8(1), bitOffset)));
                    end
                end
            else
                nBytes = numBits / 8;
                for b = 0:nBytes-1
                    byteVal = uint8(bitand(bitshift(value, -(b*8)), uint64(255)));
                    buf     = ScapyML.Codec.writeBits(buf, startBit+b*8, 8, byteVal, 'big', false, false);
                end
            end
        end

        function value = readBits(buf, startBit, numBits, endian, isFloat)
            if nargin < 5, isFloat = false; end
            value = uint64(0);
            if numBits == 0, return; end

            if isFloat
                nBytes   = numBits / 8;
                rawBytes = zeros(1, nBytes, 'uint8');
                if strcmp(endian, 'little')
                    for b = 0:nBytes-1
                        rawBytes(b+1) = uint8(ScapyML.Codec.readBits(buf, startBit+b*8, 8, 'big', false));
                    end
                else
                    for b = 0:nBytes-1
                        rawBytes(end-b) = uint8(ScapyML.Codec.readBits(buf, startBit+b*8, 8, 'big', false));
                    end
                end
                if numBits == 32
                    value = double(typecast(rawBytes, 'single'));
                else
                    value = typecast(rawBytes, 'double');
                end
                return;
            end

            if strcmp(endian, 'big') || numBits <= 8
                for b = 0:numBits-1
                    absPos    = startBit + b;
                    byteIdx   = floor(absPos / 8) + 1;
                    bitOffset = 7 - mod(absPos, 8);
                    if byteIdx <= numel(buf)
                        bit = bitand(bitshift(uint64(buf(byteIdx)), -bitOffset), uint64(1));
                    else
                        bit = uint64(0);
                    end
                    value = bitor(bitshift(value, 1), bit);
                end
            else
                nBytes = numBits / 8;
                for b = 0:nBytes-1
                    byteVal = ScapyML.Codec.readBits(buf, startBit+b*8, 8, 'big', false);
                    value   = bitor(value, bitshift(byteVal, b*8));
                end
            end
        end

    end
end
