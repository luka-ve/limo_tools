function model = limo_glm_wboot(varargin)

% Wild boostrap for limo_glm. This function for one channel only.
% It will run N bootstraps to obtain the distributon of Parameters and 
% associated statistical values.
%
% FORMAT:
% model = limo_glm_wboot(Yhat,E,'Model',LIMO,'Nullify','on/off','Sampling',boot_table,'Metrics','on/off')
% model = limo_glm_wboot(Yhat,E,'Model',X,Weights,nb_conditions,nb_interactions,nb_continuous,method,analysis)
%
% INPUTS
%         Yhat = 2D matrix of modelled EEG data with format trials x time frames
%         E    = 2D matrix of Residuals with format trials x time frames
%         'Model' is mandatory followed by either the LIMO structure or the different model parameters
%         LIMO contains information below
%         - LIMO.design.X               = 2 dimensional design matrix
%         - LIMO.Weights                = a vector or matrix of Weights for X and Y (typically LIMO.design.weights(channel,:))
%         - LIMO.design.nb_conditions   = a vector indicating the number of conditions per factor
%         - LIMO.design.nb_interactions = a vector indicating number of columns per interactions
%         - LIMO.design.nb_continuous   = number of covariates
%         - LIMO.design.method          = 'WLS', 'IRLS' 
%         - LIMO.Analysis               =  'Time', 'Frequency' or 'Time-Frequency'
%         'Nullify' is 'on' (default) or 'off' indicating if the bootstrap is under H0 or not (see below)
%         'Resample' indicates to use an already made boot_table
%                    boot_table being a resampling table that matches the 1st dim of Yhat and E
%                    if one calls limo_glm_boot to loop throughout channels, this might a good idea
%                    to provide such table so that the same resampling applies to each channel
%         'Metrics' is 'on' or 'off' (defaults) to return 95% CI and % of signitifcant results (=type 1 error if nullify is 'on')
%
% H0 is obtained by centered data (categorical designs) and resampling them using a wild bootstrap and 
% leaving X intact. If there this is a pure regression based design, Yhat is resampled using , i.e. breaking the link between Y and X. 
%
% NOTE
% Unlike limo_glm this function doesn't handle Time-Frequency data meaning that a frequency loop should be created 
% outside the function to iterate - allowing the save directly 5D H0 data 
%
% Resampling 
% Stabilize residuals by 'forcing' symmetry using a Rademeker variables
% Yboot = Yhat+rboot, since Yhat = WX* one keeps the initial weights intact  
%
% See also
% limo_glm_handling, limo_glm, limo_glm_boot
%
% Cyril Pernet
% ------------------------------
%  Copyright (C) LIMO Team 2020

%% varagin

if nargin == 3 || nargin == 4
    Yhat            = varargin{1};
    Res             = varargin{2};
    X               = varargin{3}.design.X;
    nb_conditions   = varargin{3}.design.nb_conditions;
    nb_interactions = varargin{3}.design.nb_interactions;
    nb_continuous   = varargin{3}.design.nb_continuous;
    method          = varargin{3}.design.method;
    Analysis        = varargin{3}.Analysis;
    Weights         = varargin{3}.Weights;
    
    if nargin == 3
        nboot      = 800; 
        boot_table = randi(size(Yhat,1),size(Yhat,1),nboot);
    elseif nargin ==4
        boot_table = varargin{4};
        nboot = size(boot_table,2);
    end
    
elseif nargin == 9 || nargin == 10
    Yhat            = varargin{1};
    Res             = varargin{2};
    X               = varargin{3};
    Weights         = varargin{4};
    nb_conditions   = varargin{5};
    nb_interactions = varargin{6};
    nb_continuous   = varargin{7};
    method          = varargin{8};
    Analysis        = varargin{9};
    
    if nargin == 9
        nboot       = 800; 
        boot_table  = randi(size(Yhat,1),size(Yhat,1),nboot);
    elseif nargin == 10
        boot_table  = varargin{10};
        nboot       = size(boot_table,2);
    end
    
else
    error('varargin error in limo_glm_wboot')
end

if isempty(nb_conditions);   nb_conditions   = 0; end
if isempty(nb_interactions); nb_interactions = 0; end
if isempty(nb_continuous);   nb_continuous   = 0; end

nb_factors = numel(nb_conditions);
if nb_factors == 1 && nb_conditions == 0
    nb_factors = 0;
end

% -----------
%% Data check
% -----------
if ndims(Yhat) > 2 %#ok<ISMAT>
   error('limo_glm_boot runs only on 2D data') 
end

if size(Yhat,1)~=size(X,1)
    error('The number of events in Y and the design matrix are different')
end

if nb_interactions == 0
    nb_interactions = [];
end

clear varargin 

% compute for each bootstrap
% ---------------------------
BETASB  = cell(1,nboot);
MODELR2 = cell(1,nboot);
MODELF  = cell(1,nboot);
MODELp  = cell(1,nboot);

if nb_factors ~= 0
    F_CONDVALUES = cell(1,nboot);
    p_CONDVALUES = cell(1,nboot);
end

if ~isempty(nb_interactions)
    F_INTERVALUES  = cell(1,nboot);
    p_INTERVALUES  = cell(1,nboot);
end

if nb_continuous ~=0
    F_CONTVALUES  = cell(1,nboot);
    p_CONTVALUES  = cell(1,nboot);
end

switch method
       
    % -----------------------------------------------------------------
    case {'OLS','WLS'}
        
        parfor B = 1:nboot
            
            %% Compute model parameters
            % ------------------------------
            
            % recreated weighted Y
            stab  = ones(size(Yhat)); stab(1:round(length(stab)/2),:) = -1;
            Yboot = Yhat(boot_table(:,B),:)+ Res(randi(size(Yhat,1),size(Yhat,1),1),:)+stab;% this is WY

            % compute Beta parameters
            WX    = X .* repmat(Weights,1,size(X,2));
            Betas = pinv(WX)*Yboot;
            
            % Betas bootstap
            BETASB{B} = Betas';
            
            %% Compute model statistics
            % ------------------------------
            % total sum of squares, projection matrix for errors, residuals
            % --------------------------------------------------------------
            T   = (Yboot-repmat(mean(Yboot),size(Yboot,1),1))'*(Yboot-repmat(mean(Yboot),size(Yboot,1),1));  % SS Total (the data)
            R   = eye(size(Yboot,1)) - WX*pinv(WX);                                      % Projection onto E
            E   = Yboot'*R*Yboot;                                                            % SS Error
            
            % degrees of freedom
            % -------------------
            df = rank(WX)-1;
            if strcmp(method,'OLS')
                dfe = size(Yboot,1)-rank(WX);
            else
                HM  = WX*pinv(WX); % Hat matrix, projection onto X
                dfe = trace((eye(size(HM))-HM)'*(eye(size(HM))-HM)); % in most cases same as OLS
            end
            
            % model R^2
            % -----------
            C              = eye(size(X,2));
            C(:,size(X,2)) = 0;                                  % all columns but the constant
            C0             = eye(size(X,2)) - C*pinv(C);         % only the constant
            X0             = WX*C0;                              % Reduced model design matrix
            R0             = eye(size(Yboot,1)) - (X0*pinv(X0)); % Projection onto error
            M              = R0 - R;                             % Projection matrix onto Xc
            H              = (Betas'*X'*M*X*Betas);              % SS Effects
            Rsquare        = diag(H)./diag(T);                   % Variance explained
            F_Rsquare      = (diag(H)./df) ./ (diag(E)/dfe);
            p_Rsquare      = 1 - fcdf(F_Rsquare, df, dfe);
            
            % ----------------------------
            %% update the model structure
            % ----------------------------
            MODELR2{B} = Rsquare;
            MODELF{B}  = F_Rsquare;
            MODELp{B}  = p_Rsquare;
            
            %% Compute effects
            % ------------------
            
            % -------------------------
            if nb_factors == 1   %  1-way ANOVA
                % -------------------------
                
                % compute F for categorical variables
                % -----------------------------------
                if nb_conditions ~= 0 && nb_continuous == 0
                    F_conditions                     = F_Rsquare;
                    pval_conditions                  = p_Rsquare;
                    
                elseif nb_conditions ~= 0 && nb_continuous ~= 0
                    C                                = eye(size(X,2));
                    C(:,(nb_conditions+1):size(X,2)) = 0;
                    C0                               = eye(size(X,2)) - C*pinv(C);
                    X0                               = WX*C0; % here the reduced model includes the covariates
                    R0                               = eye(size(Yboot,1)) - (X0*pinv(X0));
                    M                                = R0 - R; % hat matrix for all categorical regressors (1 factor)
                    H                                = (Betas'*X'*M*X*Betas);
                    df_conditions                    = trace(M'*M)^2/trace((M'*M)*(M'*M)); % same as rank(C)-1 if OLS; same as tr(M)?
                    F_conditions                     = (diag(H)/df) ./ (diag(E)/dfe);
                    pval_conditions                  = 1 - fcdf(F_conditions(:), df_conditions, dfe);
                end
                
                F_CONDVALUES{B}  = F_conditions;
                p_CONDVALUES{B}  = pval_conditions;
                
                % ------------------------------------------------
            elseif nb_factors > 1  && isempty(nb_interactions) % N-ways ANOVA without interactions
                % ------------------------------------------------
                
                % --------------------------------------
                % compute F and p values of each factor
                % --------------------------------------
                
                df_conditions                = NaN(1,length(nb_conditions));
                F_conditions                 = NaN(length(nb_conditions),size(Yboot,2));
                pval_conditions              = NaN(length(nb_conditions),size(Yboot,2));
                
                % define the effect of interest (eoi)
                eoi                          = zeros(1,size(X,2));
                eoi(1:nb_conditions(1))      = 1:nb_conditions(1);
                eoni                         = 1:size(X,2);
                eoni                         = find(eoni - eoi);
                
                for f = 1:length(nb_conditions)
                    C                        = eye(size(X,2));
                    C(:,eoni)                = 0; % set all but factor of interest to 0
                    C0                       = eye(size(X,2)) - C*pinv(C);
                    X0                       = WX*C0; % the reduced model include all but the factor f
                    R0                       = eye(size(Yboot,1)) - (X0*pinv(X0));
                    M                        = R0 - R; % hat matrix for factor f
                    H                        = (Betas'*X'*M*X*Betas);
                    df_conditions(f)         = trace(M'*M)^2/trace((M'*M)*(M'*M)); % same as rank(C)-1 if OLS;
                    F_conditions(f,:)        = (diag(H)/df_conditions(f)) ./ (diag(E)/dfe);
                    pval_conditions(f,:) = 1 - fcdf(F_conditions(f,:), df_conditions(f), dfe);
                    
                    % update factors
                    if f<length(nb_conditions)
                        update              = find(eoi,1,'last'); % max(find(eoi));
                        eoi                 = zeros(1,size(X,2));
                        eoi((update+1):(update+nb_conditions(f+1))) = update + (1:nb_conditions(f+1));
                        eoni                = 1:size(X,2);
                        eoni                = find(eoni - eoi);
                    end
                end
                
                F_CONDVALUES{B}  = F_conditions;
                p_CONDVALUES{B}  = pval_conditions;
                
                % ------------------------------------------------
            elseif nb_factors > 1  && ~isempty(nb_interactions) % N-ways ANOVA with interactions
                % ------------------------------------------------
                
                % ---------------------------------------------------
                % start by ANOVA without interaction for main effects
                % ---------------------------------------------------
                
                H                 = NaN(length(nb_conditions),size(Yboot,2));
                df_conditions     = NaN(1,length(nb_conditions));
                F_conditions      = NaN(length(nb_conditions),size(Yboot,2));
                pval_conditions   = NaN(length(nb_conditions),size(Yboot,2));
                HI                = NaN(length(nb_interactions),size(Yboot,2));
                df_interactions   = NaN(1,length(nb_interactions));
                F_interactions    = NaN(length(nb_interactions),size(Yboot,2));
                pval_interactions = NaN(length(nb_interactions),size(Yboot,2));
                
                % covariates
                covariate_columns = (sum(nb_conditions)+sum(nb_interactions)+1):(size(X,2)-1);
                
                % main effects
                dummy_columns = 1:sum(nb_conditions);
                
                % re-define X
                x = [X(:,dummy_columns) X(:,covariate_columns) ones(size(X,1),1)];
                
                % run same model as above with re-defined model x and
                % using the weights from the full model
                wx                           = x.*repmat(W,1,size(x,2));
                betas                        = pinv(wx)*(Yboot.*repmat(W,1,size(Yboot,2)));
                R                            = eye(size(Yboot,1)) - wx*pinv(wx);
                eoi                          = zeros(1,size(x,2));
                eoi(1:nb_conditions(1))      = 1:nb_conditions(1);
                eoni                         = 1:size(x,2);
                eoni                         = find(eoni - eoi);
                
                for f = 1:length(nb_conditions)
                    C                        = eye(size(x,2));
                    C(:,eoni)                = 0;
                    C0                       = eye(size(x,2)) - C*pinv(C);
                    X0                       = wx*C0;
                    R0                       = eye(size(Yboot,1)) - (X0*pinv(X0));
                    M                        = R0 - R;
                    H(f,:)                   = diag((betas'*x'*M*x*betas));
                    df_conditions(f)         = trace(M'*M)^2/trace((M'*M)*(M'*M)); % same as rank(C)-1 if OLS;
                    F_conditions(f,:)        = (H(f,:)./df_conditions(f)) ./ (diag(E)./dfe)'; % note dfe from full model
                    pval_conditions(f,:) = 1 - fcdf(F_conditions(f,:), df_conditions(f), dfe);
                    
                    % update factors
                    if f<length(nb_conditions)
                        update              = find(eoi,1,'last'); % max(find(eoi));
                        eoi                 = zeros(1,size(x,2));
                        eoi((update+1):(update+nb_conditions(f+1))) = update + (1:nb_conditions(f+1));
                        eoni                = 1:size(x,2);
                        eoni                = find(eoni - eoi);
                    end
                end
                
                F_CONDVALUES{B}  = F_conditions;
                p_CONDVALUES{B}  = pval_conditions;
                
                % ---------------------------
                % now deal with interactions
                % ---------------------------
                
                if nb_factors == 2 && nb_continuous == 0 % the quick way with only one interaction
                    HI                 = diag(T)' - H(1,:) - H(2,:) - diag(E)';
                    df_interactions    = prod(df_conditions);
                    F_interactions     = (HI./df_interactions) ./ (diag(E)/dfe)';
                    pval_interactions  = 1 - fcdf(F_interactions, df_interactions, dfe);
                    
                else % run through each interaction
                    
                    % part of X unchanged
                    Main_effects      = X(:,dummy_columns);
                    Cov_and_Mean      = [X(:,covariate_columns) ones(size(Yboot,1),1)];
                    
                    index             = 1;
                    Ifactors          = NaN(1,length(nb_interactions));
                    interaction       = cell(1,length(nb_interactions));
                    for n=2:nb_factors
                        combinations  = nchoosek(1:nb_factors,n); % note it matches X below because computed the same way in limo_design_matrix
                        for c = 1:size(combinations,1)
                            Ifactors(index)    = length(combinations(c,:));
                            interaction{index} = combinations(c,:);
                            index              = index + 1;
                        end
                    end
                    
                    % loop through interactions
                    % substituting and/or incrementing parts of X
                    Istart     = size(Main_effects,2)+1; % where we start interaction in X
                    Ilowbound  = size(Main_effects,2)+1;
                    for f=1:length(nb_interactions)
                        I              = X(:,Istart:(Istart+nb_interactions(f)-1));
                        if length(interaction{f}) == 2 % 1st oder interaction is main + I
                            x          = [Main_effects I Cov_and_Mean];
                        else % higher oder inteaction includes lower levels
                            Isize      = sum(nb_interactions(1:find(Ifactors == Ifactors(f),1) - 1));
                            Ihighbound = size(Main_effects,2)+Isize;
                            x          = [Main_effects X(:,Ilowbound:Ihighbound) I Cov_and_Mean];
                        end
                        eoibound       = size(x,2) - size(I,2) - size(Cov_and_Mean,2);
                        
                        % run same model as above
                        wx                         = x.*repmat(W,1,size(x,2));
                        betas                      = pinv(wx)*(Yboot.*repmat(W,1,size(Yboot,2)));
                        R                          = eye(size(Yboot,1)) - (wx*pinv(wx));
                        eoi                        = zeros(1,size(x,2));
                        eoi(eoibound+1:(eoibound+nb_interactions(f))) = eoibound+1:(eoibound+nb_interactions(f));
                        eoni                       = 1:size(x,2);
                        eoni                       = find(eoni - eoi);
                        C                          = eye(size(x,2));
                        C(:,eoni)                  = 0; %#ok<FNDSB>
                        C0                         = eye(size(x,2)) - C*pinv(C);
                        X0                         = wx*C0;
                        R0                         = eye(size(Yboot,1)) - (X0*pinv(X0));
                        M                          = R0 - R;
                        HI(f,:)                    = diag((betas'*x'*M*x*betas))';
                        df_interactions(f)         = prod(df_conditions(interaction{f}));
                        F_interactions(f,:)        = (HI(f,:)./df_interactions(f)) ./ (diag(E)/dfe)';
                        pval_interactions(f,:) = 1 - fcdf(F_interactions(f,:), df_interactions(f), dfe);
                        Istart                     = Istart+nb_interactions(f);
                    end
                end
                
                F_INTERVALUES{B}  = F_interactions;
                p_INTERVALUES{B}  = pval_interactions;
                
            end
            
            % -----------------------------------
            %% compute F for continuous variables
            % -----------------------------------
            
            if nb_continuous ~=0
                
                if nb_factors == 0 && nb_continuous == 1 % simple regression
                    F_CONTVALUES{B}  = F_Rsquare;
                    p_CONTVALUES{B}  = p_Rsquare;
                    
                else  % ANCOVA
                    
                    % pre-allocate space
                    df_continuous   = NaN(nb_continuous,size(Yboot,2));
                    F_continuous    = NaN(nb_continuous,size(Yboot,2));
                    pval_continuous = NaN(nb_continuous,size(Yboot,2));
                    
                    % compute
                    N_conditions = sum(nb_conditions) + sum(nb_interactions);
                    for n = 1:nb_continuous
                        C                                    = zeros(size(X,2));
                        C(N_conditions+n,N_conditions+n)     = 1; % pick up one regressor at a time
                        C0                                   = eye(size(X,2)) - C*pinv(C);
                        X0                                   = WX*C0; % all but rehressor of interest
                        R0                                   = eye(size(Yboot,1)) - (X0*pinv(X0));
                        M                                    = R0 - R; % hat matrix for regressor of interest
                        H                                    = Betas'*X'*M*X*Betas;
                        df_continuous(n)                     = trace(M'*M)^2/trace((M'*M)*(M'*M)); % same as rank(C) if OLS;
                        F_continuous(n,:)                    = (diag(H)./(df_continuous(n))) ./ (diag(E)/dfe);
                        pval_continuous(n,:)                 = 1 - fcdf(F_continuous(n,:), 1, dfe); % dfe same as size(Y,1)-rank(X) if OLS
                    end
                    
                    F_CONTVALUES{B}  = F_continuous';
                    p_CONTVALUES{B}  = pval_continuous';
                end
            end
        end
        
        %% ---------------------------------------------------------------------
    case 'IRLS'

%         % get residuals
%         noise = ones(size(y,1),1);
%         noise(1:round(length(noise)/2)) = -1;
%         for frame = size(y,2):-1:1
%             WY                  = y(:,frame) .*repmat(Weights(frame,:)',1,1);
%             WX                  = X.*repmat(Weights(frame,:)',1,size(X,2));
%             H                   = WX*pinv(WX);
%             Yhat(:,frame)       = X*pinv(WX)*WY;
%             E(:,frame)          = y(:,frame)-Yhat(:,frame); % residuals of observed data
%             E(:,frame)          = E(:,frame).*(1 - diag(H)); % HC3 standardization
%         end
% 
%         parfor B = 1:nboot
%             Yboot = Yhat+E(boot_table(:,B),:)+repmat(noise(randperm(size(y,1),size(y,1)),:),1,size(y,2));
%             % compute passing resampled Yboot and W
%             [BETASB{B},MODELR2{B}, MODELF{B},MODELp{B},...
%                 F_CONDVALUES{B}, p_CONDVALUES{B}, F_INTERVALUES{B}, p_INTERVALUES{B}, ...
%                 F_CONTVALUES{B},p_CONTVALUES{B}]=glm_iterate(Yboot,X,...
%                 Weights(:,boot_table(:,B))',nb_conditions, nb_interactions, nb_continuous)
%         end
end

fprintf('channel type 1 error rate: %g\n',mean(mean(cell2mat(MODELp)<0.05,2)))
model.R2_univariate  = MODELR2; clear MODELR2
model.F              = MODELF;  clear MODELF
model.p              = MODELp;  clear MODELp
model.betas          = BETASB;  clear BETASB
if nb_factors ~= 0
    model.conditions.F   = F_CONDVALUES; clear F_CONDVALUES
    model.conditions.p   = p_CONDVALUES; clear p_CONDVALUES
end
if ~isempty(nb_interactions)
    model.interactions.F = F_INTERVALUES; clear F_INTERVALUES
    model.interactions.p = p_INTERVALUES; clear p_INTERVALUES
end
if nb_continuous ~=0
    model.continuous.F   = F_CONTVALUES; clear F_CONTVALUES
    model.continuous.p   = p_CONTVALUES; clear p_CONTVALUES
end
end


%% ----------------------------------------------------------------------------------------
function [Betas,Rsquare, F_Rsquare,p_Rsquare,...
    F_conditions, pval_conditions, F_interactions, pval_interactions, ...
    F_continuous,pval_continuous] = glm_iterate(Yboot,X,W,nb_conditions, nb_interactions, nb_continuous)

nb_factors = numel(nb_conditions);
if nb_factors == 1 && nb_conditions == 0
    nb_factors = 0;
end

% pre-allocate memory space
Rsquare   = NaN(1,size(Yboot,2));
F_Rsquare = NaN(1,size(Yboot,2));
p_Rsquare = NaN(1,size(Yboot,2));
df        = NaN(1,size(Yboot,2));
dfe       = NaN(1,size(Yboot,2));
dof       = NaN(2,size(Yboot,2));

if nb_factors ~=0
    F_conditions    = NaN(length(nb_conditions),size(Yboot,2));
    pval_conditions = NaN(length(nb_conditions),size(Yboot,2));
else
    F_conditions      = [];
    pval_conditions   = [];
end

if nb_interactions ~=0
    HI                = NaN(length(nb_interactions),size(Yboot,2));
    F_interactions    = NaN(length(nb_interactions),size(Yboot,2));
    pval_interactions = NaN(length(nb_interactions),size(Yboot,2));
    df_interactions   = NaN(length(nb_interactions),size(Yboot,2));
    
    % check interaction level sizes in X
    index = 1;
    Ifactors = NaN(1,length(nb_interactions));
    interaction = cell(1,length(nb_interactions));
    for n=2:nb_factors
        combinations = nchoosek(1:nb_factors,n); % note it matches X below because computed the same way in limo_design_matrix
        for c = 1:size(combinations,1)
            Ifactors(index) = length(combinations(c,:));
            interaction{index} = combinations(c,:);
            index = index + 1;
        end
    end
else
    F_interactions    = [];
    pval_interactions = [];
end

if nb_continuous ~=0
    F_continuous    = NaN(nb_continuous,size(Yboot,2));
    pval_continuous = NaN(nb_continuous,size(Yboot,2));
    df_continuous   = NaN(nb_continuous,size(Yboot,2));
else
    F_continuous      = [];
    pval_continuous   = [];
end

% start computing
T   = (Yboot-repmat(mean(Yboot),size(Yboot,1),1))'*(Yboot-repmat(mean(Yboot),size(Yboot,1),1));
for frame = 1:size(Yboot,2)
    % model stats
    % -------------------------------------------------------------
    WX                     = X.*repmat(W(:,frame),1,size(X,2));
    HM                     = WX*pinv(WX);
    R                      = eye(size(Yboot,1)) - WX*pinv(WX);
    E                      = Yboot(:,frame)'*R*Yboot(:,frame);
    % The number of degrees of freedom can be defined as the minimum number of
    % independent coordinates that can specify the position of the system completely.
    % This gives the same as [rank(X)-1 (size(Yboot,1)-rank(X))] if OLS, here we
    % use the Satterthwaite approximation
    df(frame)              = trace(HM'*HM)^2/trace((HM'*HM)*(HM'*HM))-1;
    dfe(frame)             = trace((eye(size(HM))-HM)'*(eye(size(HM))-HM));
    R_ols                  = eye(size(Yboot,1)) - X*pinv(X);
    E_ols                  = Yboot(:,frame)'*R_ols*Yboot(:,frame);
    % MSE adjustment, E cannot be smaller than OLS since the
    % hyperplane we fit is farther away from some observations
    if E < E_ols
        n = size(X,1); p = rank(X);
        sigmar = E/(n-p); sigmals = E_ols/(n-p);
        MSE = (n*sigmar + p^2*sigmals) / (n+p^2);
        E = MSE * dfe(frame);
    end
    WY                = Yboot(:,frame) .*repmat(W(:,frame),1,1);
    Betas(:,frame)    = pinv(WX)*WY;
    C                 = eye(size(X,2));
    C(:,size(X,2))    = 0;
    C0                = eye(size(X,2)) - C*pinv(C);
    X0                = WX*C0;
    R0                = eye(size(Yboot,1)) - (X0*pinv(X0));
    M                 = R0 - R;
    H                 = (Betas(:,frame)'*X'*M*X*Betas(:,frame));
    Rsquare(frame)    = H./T(frame,frame);
    F_Rsquare(frame)  = (H/df(frame))/(E/dfe(frame));
    p_Rsquare(frame)  = 1 - fcdf(F_Rsquare(frame), df(frame), dfe(frame));
    dof(:,frame)      = [df(frame) dfe(frame)];
    
    %% Compute effects
    % ------------------
    
    % ---------------------------------
    if nb_factors == 1   %  1-way ANOVA
        % ---------------------------------
        
        % compute F for categorical variables
        % -----------------------------------
        if nb_conditions ~= 0 && nb_continuous == 0
            df_conditions(frame)             = df(frame);
            F_conditions(frame)              = F_Rsquare(frame);
            pval_conditions(frame)           = p_Rsquare(frame);
            
        elseif nb_conditions ~= 0 && nb_continuous ~= 0
            C                                = eye(size(X,2));
            C(:,(nb_conditions+1):size(X,2)) = 0;
            C0                               = eye(size(X,2)) - C*pinv(C);
            X0                               = WX*C0; % here the reduced model includes the covariates
            R0                               = eye(size(Yboot,1)) - (X0*pinv(X0));
            M                                = R0 - R; % hat matrix for all categorical regressors (1 factor)
            H                                = (Betas(:,frame)'*X'*M*X*Betas(:,frame));
            df_conditions(frame)             = trace(M'*M)^2/trace((M'*M)*(M'*M)); % same as rank(C)-1 if OLS; same as tr(M)?
            F_conditions(frame)              = (H/df_conditions(frame)) ./ (E/dfe(frame));
            pval_conditions(frame)           = 1 - fcdf(F_conditions(frame), df_conditions(frame), dfe(frame));
        end
        
        % ------------------------------------------------
    elseif nb_factors > 1  && isempty(nb_interactions) % N-ways ANOVA without interactions
        % ------------------------------------------------
        
        % --------------------------------------
        % compute F and p values of each factor
        % --------------------------------------
        
        % define the effect of interest (eoi)
        eoi                      = zeros(1,size(X,2));
        eoi(1:nb_conditions(1))  = 1:nb_conditions(1);
        eoni                     = 1:size(X,2);
        eoni                     = find(eoni - eoi);
        
        for f = 1:length(nb_conditions)
            C                        = eye(size(X,2));
            C(:,eoni)                = 0; % set all but factor of interest to 0
            C0                       = eye(size(X,2)) - C*pinv(C);
            X0                       = WX*C0; % the reduced model include all but the factor f
            R0                       = eye(size(Yboot,1)) - (X0*pinv(X0));
            M                        = R0 - R; % hat matrix for factor f
            H                        = (Betas(:,frame)'*X'*M*X*Betas(:,frame));
            df_conditions(f,frame)   = trace(M'*M)^2/trace((M'*M)*(M'*M)); % same as rank(C)-1 if OLS;
            F_conditions(f,frame)    = (H/df_conditions(f,frame)) ./ (E/dfe(frame));
            pval_conditions(f,frame) = 1 - fcdf(F_conditions(f,frame), df_conditions(f,frame), dfe(frame));
            
            % update factors
            if f<length(nb_conditions)
                update           = find(eoi,1,'last'); % max(find(eoi));
                eoi              = zeros(1,size(X,2));
                eoi((update+1):(update+nb_conditions(f+1))) = update + (1:nb_conditions(f+1));
                eoni             = 1:size(X,2);
                eoni             = find(eoni - eoi);
            end
        end
        
        % ------------------------------------------------
    elseif nb_factors > 1  && ~isempty(nb_interactions) % N-ways ANOVA with interactions
        % ------------------------------------------------
        
        % ---------------------------------------------------
        % start by ANOVA without interaction for main effects
        % ---------------------------------------------------
        
        % covariates
        covariate_columns = (sum(nb_conditions)+sum(nb_interactions)+1):(size(X,2)-1);
        
        % main effects
        dummy_columns = 1:sum(nb_conditions);
        
        % re-define X
        x = [X(:,dummy_columns) X(:,covariate_columns) ones(size(X,1),1)];
        
        % run same model as above with re-defined model x and
        % using the weights from the full model
        wx                       = x.*repmat(W(:,frame),1,size(x,2));
        betas                    = pinv(wx)*(Yboot(:,frame).*W(:,frame));
        R                        = eye(size(Yboot,1)) - wx*pinv(wx);
        eoi                      = zeros(1,size(x,2));
        eoi(1:nb_conditions(1))  = 1:nb_conditions(1);
        eoni                     = 1:size(x,2);
        eoni                     = find(eoni - eoi);
        
        for f = 1:length(nb_conditions)
            C                        = eye(size(x,2));
            C(:,eoni)                = 0;
            C0                       = eye(size(x,2)) - C*pinv(C);
            X0                       = wx*C0;
            R0                       = eye(size(Yboot,1)) - (X0*pinv(X0));
            M                        = R0 - R;
            H(f,frame)               = betas'*x'*M*x*betas;
            df_conditions(f,frame)   = trace(M'*M)^2/trace((M'*M)*(M'*M)); % same as rank(C)-1 if OLS;
            F_conditions(f,frame)    = (H(f,frame)./df_conditions(f,frame)) ./ (E./dfe(frame))'; % note dfe from full model
            pval_conditions(f,frame) = 1 - fcdf(F_conditions(f,frame), df_conditions(f,frame), dfe(frame));
            
            % update factors
            if f<length(nb_conditions)
                update           = find(eoi,1,'last'); % max(find(eoi));
                eoi              = zeros(1,size(x,2));
                eoi((update+1):(update+nb_conditions(f+1))) = update + (1:nb_conditions(f+1));
                eoni             = 1:size(x,2);
                eoni             = find(eoni - eoi);
            end
        end
        
        % ---------------------------
        % now deal with interactions
        % ---------------------------
        
        if nb_factors == 2 && nb_continuous == 0 % the quick way with only one interaction
            HI(frame)                = T(frame,frame) - sum(H(:,frame)) - E;
            df_interactions(frame)   = prod(df_conditions(frame));
            F_interactions(frame)    = (HI(frame)./df_interactions(frame)) ./ (E/dfe(frame))';
            pval_interactions(frame) = 1 - fcdf(F_interactions(frame), df_interactions(frame), dfe(frame));
            
        else % run through each interaction
            
            % part of X unchanged
            Main_effects = X(:,dummy_columns);
            Cov_and_Mean = [X(:,covariate_columns) ones(size(Yboot,1),1)];
            
            % loop through interactions
            % substituting and/or incrementing parts of X
            Istart     = size(Main_effects,2)+1; % where we start interaction in X
            Ilowbound  = size(Main_effects,2)+1;
            for f=1:length(nb_interactions)
                I              = X(:,Istart:(Istart+nb_interactions(f)-1));
                if length(interaction{f}) == 2 % 1st oder interaction is main + I
                    x          = [Main_effects I Cov_and_Mean];
                else % higher oder inteaction includes lower levels
                    Isize      = sum(nb_interactions(1:find(Ifactors == Ifactors(f),1) - 1));
                    Ihighbound = size(Main_effects,2)+Isize;
                    x          = [Main_effects X(:,Ilowbound:Ihighbound) I Cov_and_Mean];
                end
                eoibound = size(x,2) - size(I,2) - size(Cov_and_Mean,2);
                
                % run same model as above
                wx                     = x.*repmat(W(:,frame),1,size(x,2));
                betas                  = pinv(wx)*(Yboot(:,frame).*W(:,frame));
                R                      = eye(size(Yboot,1)) - (wx*pinv(wx));
                eoi                    = zeros(1,size(x,2));
                eoi(eoibound+1:(eoibound+nb_interactions(f))) = eoibound+1:(eoibound+nb_interactions(f));
                eoni                   = 1:size(x,2);
                eoni                   = find(eoni - eoi);
                C                      = eye(size(x,2));
                C(:,eoni)              = 0;
                C0                     = eye(size(x,2)) - C*pinv(C);
                X0                     = wx*C0;
                R0                     = eye(size(Yboot,1)) - (X0*pinv(X0));
                M                      = R0 - R;
                HI(f,frame)              = betas'*x'*M*x*betas;
                df_interactions(f,frame) = prod(df_conditions(interaction{f},frame));
                F_interactions(f,frame)  = (HI(f,frame)./df_interactions(f,frame)) ./ (E/dfe(frame))';
                pval_interactions(f,:)   = 1 - fcdf(F_interactions(f,frame), df_interactions(f,frame), dfe(frame));
                Istart                   = Istart+nb_interactions(f);
            end
        end
    end
    
    % -----------------------------------
    %% compute F for continuous variables
    % -----------------------------------
    
    if nb_continuous ~=0
        
        N_conditions = sum(nb_conditions) + sum(nb_interactions);
        for n = 1:nb_continuous
            C                                = zeros(size(X,2));
            C(N_conditions+n,N_conditions+n) = 1; % pick up one regressor at a time
            C0                               = eye(size(X,2)) - C*pinv(C);
            X0                               = WX*C0; % all but rehressor of interest
            R0                               = eye(size(Yboot,1)) - (X0*pinv(X0));
            M                                = R0 - R; % hat matrix for regressor of interest
            H                                = Betas(:,frame)'*X'*M*X*Betas(:,frame);
            df_continuous(n,frame)           = trace(M'*M)^2/trace((M'*M)*(M'*M)); % same as rank(C) if OLS;
            F_continuous(n,frame)            = (H./(df_continuous(n,frame))) ./ (E/dfe(frame));
            pval_continuous(n,frame)         = 1 - fcdf(F_continuous(n,frame), 1, dfe(frame)); % dfe same as size(Y,1)-rank(X) if OLS
        end
    end
end
Betas = Betas'; % back to frame/regressors
end
