classdef mfunction < handle
    properties
        f
        doc
    end
    
    methods
        function obj = mfunction(func)
            if  exist('func','var')
                obj.f = func;
            else
                obj.f = @(x) x;
            end
            obj.doc = '';
        end
        
        function out = subsref(obj,arg)
            out = obj.f(arg.subs{:});
        end
        
        function display(obj)
            fprintf(obj.doc);
        end
        
        function help(obj)
            fprintf(obj.doc);
        end
        
        function append_doc(obj,more_doc)
            obj.doc = strcat(obj.doc,more_doc,'\n');
        end
    end
end