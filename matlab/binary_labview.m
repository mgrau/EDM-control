function [stream,header] = binary_labview(data,header)
    if header(1) == 64
        if header(2) <= 2
            if header(2) == 1
                array_stream = typecast(swapbytes(uint32(length(data))),'uint8');
            elseif header(2) == 2
                array_stream = typecast(swapbytes(uint32(size(data))),'uint8');
                data = data';
            end
            header = header(3:end);
            data = data(:);
            for i=1:length(data)
                [stream,new_header] = binary_labview(data(i),header);
                array_stream = [array_stream stream];
            end
            stream = array_stream;            
            if length(data) == 0
                header = header(2:end);
            else
                header = new_header;
            end
        else
            fprintf('array dimension is more than 2!\n');
        end
    else
        switch class(data)
            case 'struct'
                if header(1) == 80
                    f = fields(data);
                    if numel(f) ~= header(2)
                        fprintf('warning, number of fields should be %d.\n',header(2));
                    end
                    header = header(3:end);
                    struct_stream = [];
                    for i=1:numel(f)
                        [stream,header] = binary_labview(data.(f{i}),header);
                        struct_stream = [struct_stream stream];
                    end
                    stream = struct_stream;
                else
                    fprintf('error, matlab has struct but type should be %d.\n',header(1));
                end
            case 'double'
                if header(1) == 10
                    header = header(2:end);
                    stream = typecast(swapbytes(double(data)),'uint8');
                else
                    fprintf('error, matlab has double but type should be %d.\n',header(1));
                end
            case 'single'
                if header(1) == 9
                    header = header(2:end);
                    stream = typecast(swapbytes(single(data)),'uint8');
                else
                    fprintf('error, matlab has single but type should be %d.\n',header(1));
                end                
            case 'uint32'
                if header(1) == 7
                    header = header(2:end);
                    stream = typecast(swapbytes(uint32(data)),'uint8');
                else
                    fprintf('error, matlab has uint32 but type should be %d.\n',header(1));
                end
            case 'uint16'
                if ismember(header(1),[6 22])
                    header = header(2:end);
                    stream = typecast(swapbytes(uint16(data)),'uint8');
                else
                    fprintf('error, matlab has uint16 but type should be %d.\n',header(1));
                end                
            case 'int32'
                if header(1) == 3
                    header = header(2:end);
                    stream = typecast(swapbytes(int32(data)),'uint8');
                else
                    fprintf('error, matlab has int32 but type should be %d.\n',header(1));
                end                
            case 'logical'
                if header(1) == 33
                    header = header(2:end);
                    stream = typecast(swapbytes(uint8(data)),'uint8');
                else
                    fprintf('error, matlab has logical but type should be %d.\n',header(1));
                end                
            case 'char'
                if ismember(header(1),[48 55 112])
                    header = header(2:end);
                    stream = typecast(swapbytes(uint32(length(data))),'uint8');
                    stream = [stream uint8(data(:)')];                
                else
                    fprintf('error, matlab has char but type should be %d.\n',header(1));
                end
            case 'cell'
                if ismember(header(1),48)
                    header = header(2:end);
                    stream = typecast(swapbytes(uint32(length(data{:}))),'uint8');
                    stream = [stream uint8(data{:})];                
                else
                    fprintf('error, matlab has char but type should be %d.\n',header(1));
                end                
            otherwise
                fprintf('class is %s and type is %d.\n',class(data),header(1));
        end
    end
end