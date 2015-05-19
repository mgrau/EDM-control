% experiment class to abstract communicating with labview
classdef experiment < handle
    properties (Access = private)
        tcp
        commands
        controls         
    end
    properties (Hidden = true)
        host
        port  
    end
    properties
        com
        read
        write
    end
    methods (Access = private)
        function send(obj,msg)
            % appends a 4 byte message length before sending messages, so
            % labview knows how much data to expect.
            fwrite(obj.tcp,length(msg),'uint32');
            fwrite(obj.tcp,msg);
        end
        
        function out = command(obj,state,varargin)
            out = 0;
            if ismember(state,obj.commands)
                for i=1:length(varargin)
                    if isnumeric(varargin{i})
                        varargin{i} = num2str(varargin{i});
                    end
                end                
                if isempty(varargin)
                    str = state;
                elseif length(varargin)==1
                    str = sprintf('%s >> %s',state,varargin{1});
                else
                    str = strcat(sprintf('%s >> %s',state,varargin{1}),sprintf(',%s',varargin{2:end}));
                end
                fopen(obj.tcp);
                obj.send(str);
                fclose(obj.tcp);
                out = 1;
            end
        end
            
        function commands = get_commands(obj)
            fopen(obj.tcp);
            obj.send('commands')
            dim = fread(obj.tcp,1,'uint32');
            obj.commands = cell(dim,1);
            for i=1:dim
                x = fread(obj.tcp,1,'uint32');
                obj.commands{i} = fread(obj.tcp,x,'char');
                obj.commands{i} = char(obj.commands{i}');
            end
            fclose(obj.tcp);
            obj.com = struct;
            for i=1:length(obj.commands)
                var = obj.commands{i};
                var(var==':')='';
                obj.com.(matlab.lang.makeValidName(var)) = mfunction(@(varargin) command(obj,obj.commands{i},varargin{:}));
                obj.com.(matlab.lang.makeValidName(var)).doc = ['Labview function <strong>' var '</strong>\n\n'];
            end
            commands = obj.commands;
        end
        
        function get_documentation(obj)
            fopen(obj.tcp);
            obj.send('documentation')
            dim = fread(obj.tcp,1,'uint32');
            for i=1:dim
                var = obj.commands{i};
                var(var==':')='';        
                x = fread(obj.tcp,1,'uint32');
                if x>0
                    append_doc(obj.com.(matlab.lang.makeValidName(var)),char(fread(obj.tcp,x,'uint8')'));
                end
            end
            fclose(obj.tcp);
        end
        
        function controls = get_controls(obj)
            fopen(obj.tcp);
            obj.send('controls')
            dim = fread(obj.tcp,1,'uint32');
            obj.controls = cell(dim,1);
            for i=1:dim
                x = fread(obj.tcp,1,'uint32');
                obj.controls{i} = fread(obj.tcp,x,'char');
                obj.controls{i} = char(obj.controls{i}');
            end
            fclose(obj.tcp);
            obj.controls = sort(obj.controls);
            controls = obj.controls;
            for i=1:numel(controls)
                obj.read.(matlab.lang.makeValidName(controls{i})) = mfunction(@(varargin) read_control(obj,controls{i}));
                obj.write.(matlab.lang.makeValidName(controls{i})) = mfunction(@(new_value) write_control(obj,controls{i},new_value));                
            end
        end        
    end
    methods (Hidden = true)
        function obj = experiment()
            obj.host = 'localhost';
            obj.port = 8888;
            obj.connect();
        end
        
        function connect(obj)
            obj.open();
            obj.get_commands();
            obj.get_documentation();
            obj.get_controls();
        end
        
        function delete(obj)
            fclose(obj.tcp);
        end
        
        function open(obj)
            try
                obj.tcp = tcpip(obj.host,obj.port);
            catch
                fprintf('Error: no labview interface running on %s:%d\n',obj.host,obj.port);
                return;
            end            
            % Set the input and output buffers to be pretty large. This
            % reduces communication overhead and doesn't seem to use up too
            % much memory.
            obj.tcp.InputBufferSize = 2^16;
            obj.tcp.OutputBufferSize = 2^16;
        end
        
        function header = read_type(obj,control)
            if ismember(control,obj.controls)
                fopen(obj.tcp);
                obj.send('type');
                obj.send(control);
                dim = fread(obj.tcp,1,'uint32');
                header = uint8(fread(obj.tcp,dim,'uint8')');
                fclose(obj.tcp);
            end
        end
        
        function display(obj)
            fprintf('    <strong>Controls</strong>');
            fprintf(repmat(' ',1,38));
            fprintf('<strong>Commands</strong>\n');

            for i=1:max(length(obj.controls),length(obj.commands))
                fprintf('    ');
                if i<=length(obj.controls)
                    fprintf(obj.controls{i});
                    fprintf(repmat(' ',1,46-length(obj.controls{i})));
                else
                    fprintf(repmat(' ',1,46));
                end
                if i<=length(obj.commands)
                    fprintf(obj.commands{i});
                end
                fprintf('\n');
            end
            fprintf('<strong>TCP Status</strong>\n');
            fprintf('Connected to %s:%d\n',obj.tcp.RemoteHost,obj.tcp.RemotePort);
        end
    end
    methods
        function [x,type_header] = read_control(obj,control)
            if ismember(control,obj.controls)
                header = obj.read_type(control);
                fopen(obj.tcp);                
                obj.send('read');
                obj.send(control);                
                dim = fread(obj.tcp,1,'uint32');
                data = [];                
                while dim
                    data = [data; fread(obj.tcp,min(dim,obj.tcp.InputBufferSize),'uint8')];
                    dim  = dim - min(dim,obj.tcp.InputBufferSize);
                end
%                 data = fread(obj.tcp,dim,'uint8');
                fclose(obj.tcp);
                data = uint8(data');
                [x,type_header] = parse_binary(header,data);
                x = struct2cell(x);
                x = x{1}; 
            end
        end  
        
        function out = write_control(obj,control,data)
            out = 0;
            if ismember(control,obj.controls)
                header = obj.read_type(control);
                [~,header] = parse_binary(header);
                data_str = binary_labview(data,header);
                fopen(obj.tcp);
                obj.send('write');
                obj.send(control);
                obj.send(data_str);
                fclose(obj.tcp);
                out = 1;
            end
        end
        
        function x = sync(obj)
            fopen(obj.tcp);
            obj.send('sync')
            x = fread(obj.tcp,1,'uint8');
            fclose(obj.tcp);
        end    
    end
end