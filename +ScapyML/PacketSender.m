classdef PacketSender
    % ScapyML.PacketSender - Advanced packet transmission with timing control
    %
    % Supports:
    %   - Single packet send
    %   - Periodic sending with fixed interval
    %   - CSV timestamp-based sending
    %   - Unicast and multicast UDP
    
    methods (Static)
        function sendWithTiming(packets, ip, port, mode, varargin)
            % Send packets with timing control
            %
            % Args:
            %   packets - Single packet or cell array
            %   ip      - Destination IP (unicast or multicast)
            %   port    - Destination UDP port
            %   mode    - 'single', 'periodic', or 'csv'
            %   varargin:
            %     For 'periodic': interval_seconds, [checksumManager]
            %     For 'csv': timestamp_data, [checksumManager]
            %     For 'single': [checksumManager]
            %     checksumManager - Optional ScapyML.ChecksumManager object
            
            if ~iscell(packets)
                packets = {packets};
            end
            
            % Extract checksumManager from varargin (last parameter if present)
            checksumManager = [];
            if ~isempty(varargin)
                lastArg = varargin{end};
                if isa(lastArg, 'ScapyML.ChecksumManager')
                    checksumManager = lastArg;
                    varargin = varargin(1:end-1);  % Remove from varargin
                end
            end
            
            % Check if multicast
            isMulticast = ScapyML.PacketSender.isMulticastIP(ip);
            if isMulticast
                fprintf('[PacketSender] Using multicast: %s:%d\n', ip, port);
            else
                fprintf('[PacketSender] Using unicast: %s:%d\n', ip, port);
            end
            
            % Show checksum status
            if ~isempty(checksumManager)
                fprintf('[PacketSender] Checksums: ENABLED ✓\n');
            else
                fprintf('[PacketSender] Checksums: disabled\n');
            end
            
            % Open socket once for the entire send session
            sender = ScapyML.UdpSender(ip, port);
            try
                switch lower(mode)
                    case 'single'
                        % Send all packets immediately
                        fprintf('[PacketSender] Sending %d packet(s)...\n', numel(packets));
                        for i = 1:numel(packets)
                            bytes = ScapyML.PacketSender.buildPacket(packets{i}, checksumManager);
                            sender.send(bytes);
                            fprintf('  Sent packet %d/%d (%d bytes)\n', i, numel(packets), numel(bytes));
                        end

                    case 'periodic'
                        % Send packets periodically with precise timing
                        if numel(varargin) < 1
                            error('Periodic mode requires interval_seconds');
                        end
                        interval = varargin{1};

                        fprintf('[PacketSender] Periodic send: %d packets @ %.3f sec intervals\n', ...
                            numel(packets), interval);
                        fprintf('Press Ctrl+C to stop\n\n');

                        for i = 1:numel(packets)
                            tStart = tic;

                            bytes = ScapyML.PacketSender.buildPacket(packets{i}, checksumManager);
                            sender.send(bytes);
                            fprintf('[%s] Sent packet %d/%d (%d bytes)\n', ...
                                datestr(now, 'HH:MM:SS.FFF'), i, numel(packets), numel(bytes));

                            % Wait for remainder of interval (except after last packet)
                            if i < numel(packets)
                                nextTime = toc(tStart) + interval;
                                while toc(tStart) < nextTime, end
                            end
                        end
                        fprintf('\n[PacketSender] Completed sending %d packets\n', numel(packets));

                    case 'csv'
                        % Send packets at timestamps specified in CSV
                        if numel(varargin) < 1
                            error('CSV mode requires timestamp data');
                        end
                        timestamps = varargin{1};

                        if ~isnumeric(timestamps) || ~isvector(timestamps)
                            error('Timestamps must be a numeric vector');
                        end
                        if numel(timestamps) ~= numel(packets)
                            error('Timestamp count (%d) must match packet count (%d)', ...
                                numel(timestamps), numel(packets));
                        end
                        if any(diff(timestamps) < 0)
                            error('Timestamps must be in ascending order.');
                        end

                        fprintf('[PacketSender] CSV-timed send: %d packets\n', numel(packets));
                        fprintf('Press Ctrl+C to stop\n\n');

                        tStart = tic;

                        % Send first packet immediately
                        bytes = ScapyML.PacketSender.buildPacket(packets{1}, checksumManager);
                        sender.send(bytes);
                        actualTime = toc(tStart);
                        fprintf('[%s] Sent packet 1/%d (%d bytes) @ t=%.4f\n', ...
                            datestr(now, 'HH:MM:SS.FFF'), numel(packets), numel(bytes), actualTime);

                        % Send remaining packets with precise timing
                        for i = 2:numel(packets)
                            targetTime = timestamps(i) - timestamps(1);
                            while toc(tStart) < targetTime, end

                            bytes = ScapyML.PacketSender.buildPacket(packets{i}, checksumManager);
                            sender.send(bytes);
                            actualTime = toc(tStart);
                            timingError = actualTime - targetTime;
                            fprintf('[%s] Sent packet %d/%d (%d bytes) @ t=%.4f (target=%.4f, err=%+.4f)\n', ...
                                datestr(now, 'HH:MM:SS.FFF'), i, numel(packets), ...
                                numel(bytes), actualTime, targetTime, timingError);
                        end

                        fprintf('\n[PacketSender] All packets sent\n');

                    otherwise
                        error('Unknown mode: %s. Use ''single'', ''periodic'', or ''csv''', mode);
                end

            catch ME
                sender.close();
                if strcmp(ME.identifier, 'MATLAB:interrupt')
                    fprintf('\n[PacketSender] Stopped by user\n');
                else
                    rethrow(ME);
                end
                return;
            end

            sender.close();
        end
        
        function bytes = buildPacket(packet, checksumManager)
            % Build packet with optional checksum calculation
            %
            % Args:
            %   packet          - ScapyML.Packet object
            %   checksumManager - Optional ScapyML.ChecksumManager (can be [])
            %
            % Returns:
            %   bytes - uint8 array with checksums applied if manager provided
            
            if ~isempty(checksumManager)
                bytes = packet.buildWithChecksums(checksumManager);
            else
                bytes = packet.build();
            end
        end
        
        function result = isMulticastIP(ip)
            % Check if IP address is multicast (224.0.0.0 - 239.255.255.255)
            parts = strsplit(ip, '.');
            if numel(parts) ~= 4
                result = false;
                return;
            end
            
            firstOctet = str2double(parts{1});
            result = (firstOctet >= 224) && (firstOctet <= 239);
        end
    end
end
