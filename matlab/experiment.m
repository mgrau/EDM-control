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
        dac_kick
        scope
    end
    methods
        function obj = experiment()
            obj.host = 'localhost';
            obj.port = 8888;
            obj.connect();
        end
        
        function connect(obj)
            try
                obj.open();
            catch
                fprintf('Error: no labview interface running on %s:%d\n',obj.host,obj.port);
            end
            obj.get_commands();
            obj.get_documentation();
            obj.get_controls();
        end
        
        function delete(obj)
            fclose(obj.tcp);
        end
        
        function open(obj)
            obj.tcp = tcpip(obj.host,obj.port);
            obj.tcp.InputBufferSize = 2^16;
            obj.tcp.OutputBufferSize = 2^16;
        end
        
        function send(obj,msg)
            fwrite(obj.tcp,length(msg),'uint32');
            fwrite(obj.tcp,msg);
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
                if x>0
                    obj.doc.(matlab.lang.makeValidName(var))  = char(fread(obj.tcp,x,'char'))';
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
                fclose(obj.tcp);
                data = uint8(data');
                [x,type_header] = parse_binary(header,data);
                x = struct2cell(x);
                x = x{1};
            end
        end  
        
        function write_control(obj,control,data)
            if ismember(control,obj.controls)
                header = obj.read_type(control);
                [~,header] = parse_binary(header);
                data_str = binary_labview(data,header);
                fopen(obj.tcp);
                obj.send('write');
                obj.send(control);
                obj.send(data_str);
                fclose(obj.tcp);
            end
        end
        
        function x = sync(obj)
            fopen(obj.tcp);
            obj.send('sync')
            x = fread(obj.tcp,1,'uint8');
            fclose(obj.tcp);
        end
        
        function read_dio64(obj)
            obj.dio64 = struct2table(obj.read_control('dio64'));
            for i=1:size(obj.dio64,1)
                obj.dio64.Chops{i} = obj.dio64.Chops{i}';
            end
        end 
        
        function write_dio64(obj)
            obj.write_control('dio64',table2struct(obj.dio64))
        end
        
        function read_dac(obj)
            obj.dac = struct2table(obj.read_control('dac'));
            for i=1:size(obj.dac,1)
                obj.dac.Chops{i} = obj.dac.Chops{i}';
            end
        end 
        
        function write_dac(obj)
            fopen(obj.tcp);
            obj.send('write:dac')
            obj.send_table(obj.dac);
            fclose(obj.tcp);
        end
        
        function read_dac_tasks(obj)
            obj.dac_tasks = struct2table(obj.read_control('dac:tasks'));
        end 
        
        function write_dac_tasks(obj)
            fopen(obj.tcp);
            obj.send('write:dac:tasks')
            obj.send_table(obj.dac_tasks);
            fclose(obj.tcp);
        end
        
        function read_dac_kick(obj)
            obj.dac_kick = struct2table(obj.read_control('dac:kick'));
        end 
        
        function write_dac_kick(obj)
            fopen(obj.tcp);
            obj.send('write:dac:kick')
            obj.send_table(obj.dac_kick);
            fclose(obj.tcp);
        end
        
        function read_scope(obj)
            waveform = obj.read_control('scope');
            obj.scope = table;
            if ~isempty(waveform)
                dt = waveform{1}.dt;
                obj.scope.x = (0:length(waveform{1}.Y)-1)'*dt;
                for i=1:numel(waveform)
                    obj.scope.(strcat('y',num2str(i))) = waveform{i}.Y;
                end
            end
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
                        elseif isstruct(temp{:})
                            temp_struct = struct2cell(temp{:});
                            for k=1:size(temp_struct,2)
                                for l=1:size(temp_struct,1)
                                    if length(temp_struct{l,k})>1
                                        buffer = [buffer typecast(uint32(length(temp_struct{l,k})),'uint8')];
                                        buffer = [buffer typecast(temp_struct{l,k}','uint8')];
                                    else
                                        buffer = [buffer typecast(temp_struct{l,k},'uint8')];
                                    end
                                end
                            end
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