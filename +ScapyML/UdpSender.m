classdef UdpSender < handle
% ScapyML.UdpSender  Persistent UDP socket for efficient multi-packet transmission.
%
% Opens the socket once on construction; reuses it for every send; closes
% it explicitly via close() or automatically when the object is deleted.
%
% Usage (persistent session):
%   u = ScapyML.UdpSender('10.10.10.10', 1234);
%   u.send(pkt.build());
%   u.send(pkt2.build());
%   u.close();
%
% Usage (one-shot static helper):
%   ScapyML.UdpSender.sendOnce(bytes, '10.10.10.10', 1234);

    properties (Access = private)
        Socket      % udpport object, legacy udp object, or java DatagramSocket
        SocketType  % 'modern' | 'legacy' | 'java'
        DestIp      % destination IP string
        DestPort    % destination port integer
        IsOpen      % logical
    end

    methods

        function obj = UdpSender(destIp, destPort)
            % Open a persistent UDP socket to destIp:destPort.
            if nargin < 2, destPort = 1234;        end
            if nargin < 1, destIp   = '127.0.0.1'; end

            obj.DestIp   = destIp;
            obj.DestPort = destPort;
            obj.IsOpen   = false;
            obj.openSocket();
        end

        function send(obj, bytes)
            % Send a byte array through the open socket.
            if ~obj.IsOpen
                error('ScapyML:UdpSender:NotOpen', ...
                    'Socket is closed. Create a new UdpSender.');
            end

            bytes = uint8(bytes(:)');

            try
                switch obj.SocketType
                    case 'modern'
                        write(obj.Socket, bytes, obj.DestIp, obj.DestPort);
                    case 'legacy'
                        fwrite(obj.Socket, bytes, 'uint8');
                    case 'java'
                        import java.net.DatagramPacket
                        import java.net.InetAddress
                        addr   = InetAddress.getByName(obj.DestIp);
                        jBytes = int8(bytes);
                        dgram  = DatagramPacket(jBytes, numel(jBytes), addr, obj.DestPort);
                        obj.Socket.send(dgram);
                end
            catch ME
                error('ScapyML:UdpSender:SendFailed', ...
                    'UDP send failed (%s): %s', obj.SocketType, ME.message);
            end
        end

        function close(obj)
            % Close the socket and release the resource.
            if ~obj.IsOpen, return; end
            try
                switch obj.SocketType
                    case 'modern'
                        clear obj.Socket;
                    case 'legacy'
                        fclose(obj.Socket);
                        delete(obj.Socket);
                    case 'java'
                        obj.Socket.close();
                end
            catch
                % Ignore errors on close
            end
            obj.IsOpen = false;
            obj.Socket = [];
            fprintf('[ScapyML] UDP socket closed.\n');
        end

        function delete(obj)
            % Destructor: ensure socket is released when object goes out of scope.
            obj.close();
        end

    end

    methods (Static)

        function sendOnce(bytes, destIp, destPort)
            % Convenience: open socket, send one datagram, close.
            % Use only for truly one-off sends; prefer a persistent
            % UdpSender instance when sending multiple packets.
            if nargin < 3, destPort = 1234;        end
            if nargin < 2, destIp   = '127.0.0.1'; end
            u = ScapyML.UdpSender(destIp, destPort);
            u.send(bytes);
            u.close();
        end

    end

    methods (Access = private)

        function openSocket(obj)
            % Try modern -> legacy -> Java; store whichever succeeds first.

            % ---- Modern udpport (R2020b+) ----
            try
                obj.Socket     = udpport('byte', 'LocalPort', 0);
                obj.SocketType = 'modern';
                obj.IsOpen     = true;
                fprintf('[ScapyML] UDP socket open (modern) -> %s:%d\n', ...
                    obj.DestIp, obj.DestPort);
                return;
            catch e1
                warning('ScapyML:UdpSender:ModernFailed', ...
                    'udpport failed (%s), trying legacy.', e1.message);
            end

            % ---- Legacy udp (Instrument Control Toolbox) ----
            try
                u = udp(obj.DestIp, obj.DestPort); %#ok<UDPD>
                u.OutputDatagramPacketSize = 65507;
                fopen(u);
                obj.Socket     = u;
                obj.SocketType = 'legacy';
                obj.IsOpen     = true;
                fprintf('[ScapyML] UDP socket open (legacy) -> %s:%d\n', ...
                    obj.DestIp, obj.DestPort);
                return;
            catch e2
                warning('ScapyML:UdpSender:LegacyFailed', ...
                    'Legacy udp() failed (%s), trying Java.', e2.message);
            end

            % ---- Java DatagramSocket ----
            try
                import java.net.DatagramSocket
                obj.Socket     = DatagramSocket();
                obj.SocketType = 'java';
                obj.IsOpen     = true;
                fprintf('[ScapyML] UDP socket open (Java) -> %s:%d\n', ...
                    obj.DestIp, obj.DestPort);
                return;
            catch e3
                error('ScapyML:UdpSender:AllFailed', ...
                    'All UDP socket methods failed. Last error: %s', e3.message);
            end
        end

    end
end
