classdef experiment < handle
    properties
        host
        port
        tcp
        commands
        controls
        com
        doc
        dio64
        dac
        dac_tasks
        scope
    end
    methods
        function obj = experiment()
            obj.host = 'localhost';
            obj.port = 8888;
            try
            obj.open();
            obj.get_commands();
            obj.get_documentation();
            obj.get_controls();
            catch
                fprintf('Error: no labview interface running on %s:%d',obj.host,obj.port);
            end
        end
        
        function delete(obj)
            fclose(obj.tcp);
        end
        
        function open(obj)
            obj.tcp = tcpip(obj.host,obj.port);  
        end
        
        function send(obj,msg)
            fwrite(obj.tcp,length(msg),'uint32');
            fwrite(obj.tcp,msg);
        end
        
        function test(obj,msg)
            fopen(obj.tcp);
            obj.send(msg);
            fclose(obj.tcp);
        end
        
        function command(obj,state,varargin)
            for i=1:length(varargin)
                if isnumeric(varargin{i})
                    varargin{i} = num2str(varargin{i});
                end
            end
            if ismember(state,obj.commands)
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
                 obj.com.(matlab.lang.makeValidName(var)) = @(varargin) command(obj,obj.commands{i},varargin{:});
            end
            commands = obj.commands;
        end
        
        function get_documentation(obj)
            fopen(obj.tcp);
            obj.send('documentation')
            dim = fread(obj.tcp,1,'uint32');
            obj.doc = struct;
            for i=1:dim
                var = obj.commands{i};
                var(var==':')='';        
                x = fread(obj.tcp,1,'uint32');
                obj.doc.(matlab.lang.makeValidName(var))  = char(fread(obj.tcp,x,'char'))';
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
        end        
        
        function x = sync(obj)
            fopen(obj.tcp);
            obj.send('sync')
            x = fread(obj.tcp,1,'uint8');
            fclose(obj.tcp);
        end
        
        function read_dio64(obj)
            obj.dio64 = obj.recv_object('dio64:read');
            obj.dio64 = struct2table(obj.dio64.DIO64);
            for i=1:size(obj.dio64,1)
                obj.dio64.Chops{i} = obj.dio64.Chops{i}';
            end
        end 
        
        function write_dio64(obj)
            fopen(obj.tcp);
            obj.send('dio64:write')
            obj.send_table(obj.dio64);
            fclose(obj.tcp);
        end
        
        function read_dac(obj)
            obj.dac = obj.recv_object('dac:read');
            obj.dac = struct2table(obj.dac.DAC);
            for i=1:size(obj.dac,1)
                obj.dac.Chops{i} = obj.dac.Chops{i}';
            end
        end 
        
        function write_dac(obj)
            fopen(obj.tcp);
            obj.send('dac:write')
            obj.send_table(obj.dac);
            fclose(obj.tcp);
        end
        
        function read_dac_tasks(obj)
            obj.dac_tasks = obj.recv_object('dac_tasks:read');
%             obj.dac_tasks = struct2table(obj.dac_tasks.DACTasks);

        end 
        
        function write_dac_tasks(obj)
            fopen(obj.tcp);
            obj.send('dac_tasks:write')
            obj.send_table(obj.dac_tasks);
            fclose(obj.tcp);
        end
        
        function read_scope(obj)
            obj.scope = obj.recv_object('scope:read');
            obj.scope.data = table;
            if ~isempty(obj.scope.WaveformGraph)
                dt = obj.scope.WaveformGraph{1}.dt;
                obj.scope.data.x = (0:length(obj.scope.WaveformGraph{1}.Y)-1)'*dt;
                for i=1:length(obj.scope.WaveformGraph)
                    obj.scope.data.(strcat('y',num2str(i))) = obj.scope.WaveformGraph{i}.Y;
                end
            end
        end     
        
        function x = read_control(obj,control)
            if ismember(control,obj.controls)
                fopen(obj.tcp);
                obj.send('read');
                obj.send(control);
                dim = fread(obj.tcp,1,'uint32');
                header = [];
                while dim
                    header = [header; fread(obj.tcp,min(dim,obj.tcp.InputBufferSize),'uint8')];
                    dim  = dim - min(dim,obj.tcp.InputBufferSize);
                end
                dim = fread(obj.tcp,1,'uint32');
                data = [];
                while dim
                    data = [data; fread(obj.tcp,min(dim,obj.tcp.InputBufferSize),'uint8')];
                    dim  = dim - min(dim,obj.tcp.InputBufferSize);
                end            
                fclose(obj.tcp);
                header = uint8(header');
                data = uint8(data');
                x = parse_binary(header,data);
                x = struct2cell(x);
                x = x{1};
            end
        end        
        
        function x = recv_object(obj,command)
            fopen(obj.tcp);
            obj.send(command)
            dim = fread(obj.tcp,1,'uint32');
            x = [];
            while dim
                x = [x; fread(obj.tcp,min(dim,obj.tcp.InputBufferSize),'uint8')];
                dim  = dim - min(dim,obj.tcp.InputBufferSize);
            end
            fclose(obj.tcp);
            x = uint8(x');
            x = parse_binary(x,1);
        end
        
        function send_table(obj,s)
            fwrite(obj.tcp,size(s,1),'uint32');
            for i=1:size(s,1)
                buffer = [];
                for j=1:size(s,2)
                    if iscell(s{i,j})
                        temp = s{i,j};
                        buffer = [buffer typecast(uint32(length(temp{:})),'uint8')];
                        if islogical(temp{:})
                            buffer = [buffer uint8(temp{:})];
                        elseif ischar(temp{:})
                            buffer = [buffer uint8(temp{:})];
                        else
                            buffer = [buffer typecast(temp{:},'uint8')];
                        end
                    elseif isnumeric(s{i,j})
                        buffer = [buffer typecast(s{i,j},'uint8')];
                    elseif islogical(s{i,j})
                        buffer = [buffer uint8(s{i,j})];
                    end
                end
                obj.send(buffer);
            end
        end
    end
end

