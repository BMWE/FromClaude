classdef Crc
% ScapyML.Crc - Ready-made checksum/CRC functions for use in checksums.txt
%
% All methods take a uint8 array (or numeric vector of byte values) and
% return a non-negative scalar, so they can be used directly as the
% right-hand side of a checksum definition:
%
%   crc16 = @(data) ScapyML.Crc.crc16ccitt(data)
%
% Standard "check" values for the ASCII input '123456789':
%   crc8          0xF4        (CRC-8, poly 0x07, init 0x00)
%   crc16ccitt    0x29B1      (CRC-16/CCITT-FALSE, poly 0x1021, init 0xFFFF)
%   crc16modbus   0x4B37      (CRC-16/MODBUS, poly 0xA001 reflected, init 0xFFFF)
%   crc32         0xCBF43926  (CRC-32/ISO-HDLC, as used by Ethernet/zip)
%   fletcher16    0x1EDE
%
% Bitwise (table-free) implementations: simple and portable, but written
% for clarity rather than speed.

    methods (Static)

        function c = crc8(data)
            d = double(data(:))';
            c = 0;
            for b = d
                c = bitxor(c, b);
                for k = 1:8
                    if c >= 128
                        c = bitxor(mod(c*2, 256), 7);
                    else
                        c = mod(c*2, 256);
                    end
                end
            end
        end

        function c = crc16ccitt(data)
            d = double(data(:))';
            c = 65535;
            for b = d
                c = bitxor(c, b*256);
                for k = 1:8
                    if c >= 32768
                        c = bitxor(mod(c*2, 65536), 4129);   % 0x1021
                    else
                        c = mod(c*2, 65536);
                    end
                end
            end
        end

        function c = crc16modbus(data)
            d = double(data(:))';
            c = 65535;
            for b = d
                c = bitxor(c, b);
                for k = 1:8
                    if bitand(c, 1)
                        c = bitxor(floor(c/2), 40961);       % 0xA001
                    else
                        c = floor(c/2);
                    end
                end
            end
        end

        function c = crc32(data)
            d = double(data(:))';
            c = 4294967295;
            for b = d
                c = bitxor(c, b);
                for k = 1:8
                    if bitand(c, 1)
                        c = bitxor(floor(c/2), 3988292384);  % 0xEDB88320
                    else
                        c = floor(c/2);
                    end
                end
            end
            c = bitxor(c, 4294967295);
        end

        function c = internetChecksum(data)
            % RFC 1071 ones'-complement sum of 16-bit big-endian words
            d = double(data(:))';
            if mod(numel(d), 2) == 1
                d(end+1) = 0;
            end
            s = sum(d(1:2:end)*256 + d(2:2:end));
            while s > 65535
                s = mod(s, 65536) + floor(s/65536);
            end
            c = 65535 - s;
        end

        function c = fletcher16(data)
            d = double(data(:))';
            s1 = 0;
            s2 = 0;
            for b = d
                s1 = mod(s1 + b, 255);
                s2 = mod(s2 + s1, 255);
            end
            c = s2*256 + s1;
        end

    end
end
