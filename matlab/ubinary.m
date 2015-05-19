function data = ubinary(filename)
    % UBINARY(filename)
    %     Opens a Labview binary file, with interspersed metadata.
    %     
    %     Looks for text descriptor tags fitting the following pattern
    %     
    %         @@@@@TAG}}}}}
    %         
    %     following the tag we expect a labview binary chunk. Each labview binary
    %     chunk is epxected to have a ubinary binary header, which we can
    %     interpret using parse_binary. Each chunk is interpreted and stored in
    %     a struct.

    % open file and read in the character stream. Hopefully this isn't too
    % slow?
    
    f = fopen(filename,'r');
    str = fread(f,[1 inf],'uint8=>uint8');
    fclose(f);

    ptr = 1;
    if strcmp(char(str(1:18)),'@@@@@ubinary4}}}}}')
        ptr = ptr + 18;
        num_elements = swapbytes(typecast(str(ptr:ptr+3),'uint32'));
        ptr = ptr + 4;
        data = struct;
        for i=1:num_elements
            name_len = swapbytes(typecast(str(ptr:ptr+3),'uint32'));
            ptr = ptr + 4;
            name = char(str(ptr:ptr+name_len-1));
            ptr = ptr + name_len;            
            header_len = swapbytes(typecast(str(ptr:ptr+3),'uint32'));
            ptr = ptr + 4;
            header_str = str(ptr:ptr+header_len-1);
            ptr = ptr + header_len;
            data_len = swapbytes(typecast(str(ptr:ptr+3),'uint32'));
            ptr = ptr + 4;
            data_str = str(ptr:ptr+data_len-1);
            ptr = ptr + data_len;
            try
                if strcmp(name,'DIO64 Labels');
                    name
                end
                x = parse_binary(header_str,data_str);
                field_names = fields(x);
                for j=1:numel(field_names)
                    data.(field_names{j}) = x.(field_names{j});
                end
            catch
                fprintf('Couldnt load control %s\n.',name); 
            end
        end
    end
end