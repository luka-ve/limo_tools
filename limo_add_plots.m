function out = limo_add_plots(varargin)

% interactive ploting functon for data generated by
% limo_central_tendency_and_ci, limo_plot_difference or any data in 
% 4D with dim channels * frames * conditions * 3 with this last dim being
% the low end of the confidence interval, the estimator (like eg mean), 
% high end of the confidence interval 
% The variable mame in is called M, TM, Med, HD or diff
% ------------------------------
%  Copyright (C) LIMO Team 2019

out     = 0;
turn    = 1;
channel = [];
infile  = [];

if ~isempty(varargin)
    for i=1:size(varargin,2)
        if strcmpi(varargin{i},'channel')
            channel = varargin{i+1};
        elseif ischar(varargin{i})
            infile{i} = varargin{i};
        end
    end
end

while out == 0
    subjects_plot = 0;

    %% Data selection
     
    if ~isempty(infile) % allows comand line plot
        if turn <= length(infile)
            file = infile{turn}; index = 1; 
        else
            out = 1; return
        end
    else
        [file,path,index]=uigetfile('*mat',['Select Central tendency file n:' num2str(turn) '']);
        file = fullfile(path,file);
    end
    
    if index == 0
        out = 1; return
    else
        data       = load(file);
        data       = getfield(data,cell2mat(fieldnames(data)));
        datatype   = fieldnames(data);
        datatype   = datatype(cellfun(@(x) strcmp(x,'limo'), fieldnames(data))==0);
        options    = {'mean','trimmed_mean','median','Harrell_Davis','diff','data'};
        if sum(strcmpi(datatype,options)) == 0
            errordlg2('unknown file to plot');
            return
        end
        name{turn} = cell2mat(datatype); 
        tmp        = data.(cell2mat(datatype));
        
        if strcmpi(data.limo.Analysis,'Time-Frequency')
            if ~exist('whichdim','var') % second time, don't ask
                whichdim = questdlg('which domain to plot?','option','time','frequency','time');
            end
            
            if isempty(whichdim)
                return
            elseif strcmpi(whichdim,'Time')
                if ~exist('dimvalue','var')
                    if isfield(data.limo,'data')
                        dimvalue = inputdlg('plot data at which frequency ?','option');
                    else
                        dimvalue = inputdlg('no time/freq info available, plot data for which matrix frequency cell','option');
                    end
                end
                
                if isempty(dimvalue)
                    return
                else
                    if iscell(dimvalue)
                        dimvalue     = str2num(cell2mat(dimvalue));
                    end
                    if isfield(data.limo,'data')
                        [~,dimvalue] = min(abs(data.limo.data.tf_freqs - dimvalue));
                        vect         = data.limo.data.tf_times;
                    end
                    tmp              = tmp(:,dimvalue,:,:,:);
                    tmp              = reshape(tmp,size(tmp,1),size(tmp,3),size(tmp,4),size(tmp,5));
                end
            elseif strcmpi(whichdim,'Frequency')
                if ~exist('dimvalue','var')
                    if isfield(data.limo,'data')
                        dimvalue = inputdlg('plot data at which time ?','option');
                    else
                        dimvalue = inputdlg('no time/freq info available, plot data for which matrix time cell','option');
                    end
               end
                
                if isempty(dimvalue)
                    return
                else
                    if iscell(dimvalue)
                        dimvalue     = str2num(cell2mat(dimvalue));
                    end
                    if isfield(data.limo,'data')
                        [~,dimvalue] = min(abs(data.limo.data.tf_times - dimvalue));
                        vect         = data.limo.data.tf_freqs;
                    end
                    tmp              = tmp(:,:,dimvalue,:,:);
                    tmp              = reshape(tmp,size(tmp,1),size(tmp,2),size(tmp,4),size(tmp,5));
                end
            else
                return
            end
        end
        
        % the last dim of data.data can be the number of subjects or the trials 
        % sorted by there weights - use file name to know which estimator was used
        if isfield(data,'data')
            if contains(file, 'Mean','IgnoreCase',true)
                name{turn} = 'Subjects'' Means';
            elseif contains(file, 'Trimmed mean','IgnoreCase',true)
                name{turn} = 'Subjects'' Trimmed Means';
            elseif contains(file, 'HD','IgnoreCase',true)
                name{turn} = 'Subjects'' Mid Deciles HD';
            elseif contains(file, 'Median','IgnoreCase',true)
                name{turn} = 'Subjects'' Medians';
            else
                if strcmpi(file,'subjects_weighted_data.mat')
                    name{turn} = 'Data plotted per weight';
                else
                    underscores = strfind(file, '_');
                    if ~isempty(underscores)
                        file(underscores) = ' ';
                    end
                    ext = strfind(file, '.');
                    file(max(ext):end) = [];
                    name{turn} = file;
                end
            end
            subjects_plot = 1;
        end
    end
    
    if isfield(data,'limo')
        limo = data.limo;
    else
        [limofile,locpath]=uigetfile({'LIMO.mat'},'Select any LIMO with right info');
        if strcmp(limofile,'LIMO.mat')
            LIMO      = load(fullfile(locpath,limofile));
            limo      = LIMO.LIMO; clear LIMO;
            data.limo = limo;
            save(fullfile(path,file),'data')
        else
            warning('selection aborded'); return
        end
    end
    
    % store each iteration into Data
    if strcmpi('diff',datatype)
        Data        = tmp;
    else
        if size(tmp,1) == 1 && size(tmp,3) == 1 % only 1 channel and 1 variable
            D           = squeeze(tmp(:,:,1,:));
            Data        = nan(1,size(tmp,2),size(tmp,4));
            Data(1,:,:) = D; clear D;
        elseif size(tmp,1) > 1 && size(tmp,3) == 1 % only 1 variable
            Data        = squeeze(tmp(:,:,1,:));
        else
            if nargin >= 2
                v = varargin{2};
            elseif ~exist('v','var')
                if subjects_plot == 0
                    v = cell2mat(inputdlg(['which variable to plot, 1 to ' num2str(size(tmp,3))],'plotting option'));
                    if isempty(v)
                        out = 1; return
                    elseif ischar(v)
                        v = eval(v);
                    end
                end
            end
            
            if  subjects_plot == 0 && length(v)>1
                errordlg2('only 1 parameter value expected'); return
            else
                if size(tmp,1) == 1 && size(tmp,3) > 1
                    D           = squeeze(tmp(:,:,v,:));
                    Data        = nan(1,size(tmp,2),size(tmp,4));
                    Data(1,:,:) = D; clear D;
                else
                    Data        = squeeze(tmp(:,:,v,:));
                end
            end
        end
    end
    clear tmp
    
    
    %% prep figure the 1st time rounnd
    % ------------------------------
    if turn == 1
        figure('Name','Central Tendency Estimate','color','w'); hold on
        
        % frame info
        % ----------
        if strcmpi(limo.Analysis,'Time')
            if isfield(data.limo.data,'timevect')
                vect = data.limo.data.timevect;
            else
                vect = limo.data.start:(1000/limo.data.sampling_rate):limo.data.end;  % in msec
            end
        elseif strcmpi(limo.Analysis,'Frequency')
            if isfield(data.limo.data,'freqlist')
                vect = data.limo.data.freqlist;
            else
                vect = linspace(limo.data.start,limo.data.end,size(Data,2));
            end
        elseif ~exist('vect','var')
            v = inputdlg('no axis info? enter x axis interval e.g. [0:0.5:200]');
            try
                vect = eval(cell2mat(v));
                if length(vect) ~= size(Data,2)
                    disp('interval invalid - using defaults');
                    vect = 1:size(Data,2);
                end
            catch ME
                disp('interval invalid format');
                vect = 1:size(Data,2);
            end
        end
    end
    
    %% channel to plot
    % ----------------
    if size(Data,1) == 1
        Data = squeeze(Data(1,:,:)); 
    else
        if isempty(channel)
            channel = inputdlg(['which channel to plot 1 to' num2str(size(Data,1))],'channel choice');
        end
        
        if strcmp(channel,'') 
            tmp = Data(:,:,2); 
            if sum(isnan(tmp(:))) == numel(tmp)
                error('the data file appears empty (only NaNs)')
            else
                if abs(max(tmp(:))) > abs(min(tmp(:)))
                    [channel,~,~] = ind2sub(size(tmp),find(tmp==max(tmp(:))));
                else
                    [channel,~,~] = ind2sub(size(tmp),find(tmp==min(tmp(:))));
                end
                if length(channel) ~= 1; channel = channel(1); end
                Data = squeeze(Data(channel,:,:)); fprintf('ploting channel %g\n',channel)
            end
        else
            try
                Data = squeeze(Data(channel,:,:));
            catch
                Data = squeeze(Data(eval(cell2mat(channel)),:,:));
            end
        end
    end
    
    % finally plot
    % ---------------
    plotted_data.xvect = vect;    
    if turn==1
        if subjects_plot == 1
            plot(vect,Data,'LineWidth',2); 
            plotted_data.data  = Data;
        else
            plot(vect,Data(:,2)','LineWidth',3);
            plotted_data.data  = Data';
        end
        assignin('base','plotted_data',plotted_data)
        colorOrder = get(gca, 'ColorOrder');
        colorindex = 1;
    else
        if size(vect,2) ~= size(Data,1)
            warndlg('the new data selected have a different size, plot skipped')
        else
            if subjects_plot == 0
                plot(vect,Data(:,2)','Color',colorOrder(colorindex,:),'LineWidth',3);
                plotted_data.data  = Data';
            else
                plot(vect,Data,'LineWidth',2);
                plotted_data.data  = Data;
            end
            assignin('base','plotted_data',Data')
        end
    end
    
    if subjects_plot == 0 && size(vect,2) == size(Data,1)
        fillhandle = patch([vect fliplr(vect)], [Data(:,1)',fliplr(Data(:,3)')], colorOrder(colorindex,:));
        set(fillhandle,'EdgeColor',colorOrder(colorindex,:),'FaceAlpha',0.2,'EdgeAlpha',0.8);%set edge color
    end
    grid on; axis tight; box on;
    
    if exist('whichdim','var')
        xlabel(whichdim,'FontSize',14)
    else
        xlabel(limo.Analysis,'FontSize',14)
    end
    ylabel('Amplitude','FontSize',14)
        
    if turn == 1
        mytitle = name{1};
    else
        mytitle = sprintf('%s & %s',mytitle,name{turn});
    end
    
    if iscell(channel)
        channel = eval(cell2mat(channel));
    end
    title(sprintf('channel %g \n %s',channel,mytitle),'Fontsize',16,'Interpreter','none');
    
    % updates
    turn = turn+1;
    if colorindex <7
        colorindex = colorindex + 1;
    else
        colorindex = 1;
    end
    clear data tmp
    pause(1);
end
    
