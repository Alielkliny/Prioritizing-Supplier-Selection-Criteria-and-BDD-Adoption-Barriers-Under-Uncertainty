% =====================================================================
% Five_Rev_01_G_OPA_Model.m  –  Grey OPA with 5 categories  
%                              *confidence × contribution* expert weights
% =====================================================================
% • All experts share the same nominal ordinal rank
%   → weight driven solely by:
%       – Confidence    = 1 / average grey-width they provide
%       – Contribution  = 1 / average ordinal rank they assign
% • Expert grey weight  =  score · [0.8  1.2] / Σscore  (Model-11)
% • Criteria layer and each of five alternative categories are then
%   aggregated with classic OPA and rescaled to Model-11.
% • Blank / text cells are tolerated (ignored in averages).
% ---------------------------------------------------------------------
% Needs only base MATLAB (no GLP).
% =====================================================================

clear, clc
file = 'OPA5.xlsx';                % workbook
eps  = 1e-6;                       % tiny floor
C    = 5;                          % number of alternative categories

%% 1 ─── LOAD EXPERTS & CRITERIA ---------------------------------------
raw = readcell(file,'Sheet','Experts'); raw=raw(~cellfun(@isempty,raw));
if ischar(raw{1})||isstring(raw{1}), raw=raw(2:end); end
p  = numel(raw);  gE = cellfun(@cell2grey,raw,'Uni',false);

raw = readcell(file,'Sheet','Criteria');
if ischar(raw{1})||isstring(raw{1}), raw=raw(2:end,:); end
[p2,n] = size(raw);  assert(p2==p,'Criteria rows ≠ #experts');
gC = reshape(cellfun(@cell2grey,raw,'Uni',false),[p n]);

%% 2 ─── LOAD 5 CATEGORIES OF ALTERNATIVES -----------------------------
gB = cell(C,1);  m  = zeros(C,1);
for c = 1:C
    gB{c} = cell(p,n);
    for i = 1:p
        sh  = sprintf('Cat%d_E%d',c,i);
        raw = readcell(file,'Sheet',sh);
        if ischar(raw{1})||isstring(raw{1}), raw=raw(2:end,:); end
        [n2,m0] = size(raw);  if i==1, m(c)=m0; end
        if n2 < n, raw(n2+1:n,1) = {[]}; elseif n2 > n, raw = raw(1:n,:); end
        for j = 1:n
            gB{c}{i,j} = cellfun(@cell2grey, raw(j,:)','Uni',false);
        end
    end
end

%% 3 ─── CONFIDENCE & CONTRIBUTION SCORES ------------------------------
conf = zeros(p,1);  contr = conf;
for i = 1:p
    % ---------- confidence ------------------------------------------
    widths = [];                                 % column vector
    for j = 1:n
        widths = [widths; gC{i,j}(2)-gC{i,j}(1)];          % one value
    end
    for c = 1:C
        for j = 1:n
            wtmp = cellfun(@(x) x(2)-x(1), gB{c}{i,j});
            widths = [widths; wtmp(:)];                  % append column
        end
    end
    widths = widths(~isnan(widths));                     % drop blanks
    conf(i) = 1 / mean(widths);

    % ---------- contribution ---------------------------------------
    ranks = [];
    for j = 1:n, ranks = [ranks; mean(gC{i,j})]; end
    for c = 1:C, for j = 1:n
            rtmp = cellfun(@mean, gB{c}{i,j});
            ranks = [ranks; rtmp(:)];
    end,end
    ranks = ranks(~isnan(ranks));
    contr(i) = 1 / mean(ranks);
end
score = conf .* contr;

% ---------- expert grey weights (Model-11) ---------------------------
wE_L = 0.8 * score / sum(score);
wE_U = 1.2 * score / sum(score);

%% 4 ─── CRITERIA WEIGHTS (Model-11) -----------------------------------
[wC_L,wC_U] = deal(zeros(n,1));
for j = 1:n
    lo = 0; up = 0;
    for i = 1:p
        [wcL,wcU] = opaWeights(squeeze(gC(i,:)));
        lo = lo + wE_L(i)*wcL(j);
        up = up + wE_U(i)*wcU(j);
    end
    wC_L(j)=lo; wC_U(j)=up;
end
[wC_L,wC_U] = fixLU(wC_L,wC_U,eps);
wC_L=wC_L*(0.8/sum(wC_L)); wC_U=wC_U*(1.2/sum(wC_U));
[wC_L,wC_U] = fixLU(wC_L,wC_U,eps);

%% 5 ─── ALTERNATIVE WEIGHTS (per category) ----------------------------
wB_L=cell(C,1); wB_U=cell(C,1); rankAlt=cell(C,1);
for c = 1:C
    mc = m(c); [wL,wU]=deal(zeros(mc,1));
    for k = 1:mc
        lo=0; up=0;
        for j = 1:n
            loAlt=0; upAlt=0;
            for i = 1:p
                [aL,aU]=opaWeights(gB{c}{i,j});
                if k<=numel(aL) && isfinite(aL(k))
                    loAlt=loAlt+wE_L(i)*aL(k);
                    upAlt=upAlt+wE_U(i)*aU(k);
                end
            end
            lo=lo+wC_L(j)*loAlt;   up=up+wC_U(j)*upAlt;
        end
        wL(k)=lo;  wU(k)=up;
    end
    [wL,wU] = fixLU(wL,wU,eps);
    wL=wL*(0.8/sum(wL)); wU=wU*(1.2/sum(wU));
    [wL,wU] = fixLU(wL,wU,eps);
    wB_L{c}=wL; wB_U{c}=wU;
    [~,rankAlt{c}] = sort((wL+wU)/2,'descend');
end

%% 6 ─── DISPLAY -------------------------------------------------------
fprintf('\n======== OPA-G  (confidence × contribution) ========\n')
dispLayer('Experts' ,wE_L,wE_U)
dispLayer('Criteria',wC_L,wC_U)
for c=1:C
    fprintf('\n── Category %d (m = %d) ──\n',c,m(c))
    dispLayer(sprintf('Alt-Cat%d',c),wB_L{c},wB_U{c})
    fprintf('Kernel ranking: %s\n',mat2str(rankAlt{c}))
end

%% ─── HELPER FUNCTIONS ───────────────────────────────────────────────
function g = cell2grey(v)
    if isnumeric(v)
        v=v(~isnan(v));
        if isempty(v), g=[NaN NaN];
        elseif numel(v)==1, g=[v-0.5 v+0.5];
        else, g=[v(1)-0.5 v(2)+0.5];
        end
    else
        s=strtrim(string(v));
        if s=="", g=[NaN NaN];
        elseif contains(s,'-')
            d=str2double(split(s,'-')); g=[d(1)-0.5 d(2)+0.5];
        else
            n=str2double(s); g=[n-0.5 n+0.5];
        end
    end
end

function [wL,wU]=opaWeights(g)
    g=g(~cellfun(@(x) any(isnan(x)),g));
    n=numel(g); if n==0, wL=0; wU=0; return, end
    rMin=zeros(n,1); rMax=rMin;
    for t=1:n
        rMin(t)=g{t}(1)+0.5;  rMax(t)=g{t}(2)-0.5;
    end
    Smin=1./rMax; Smax=1./rMin; wL=zeros(n,1); wU=wL;
    for t=1:n
        wL(t)=Smin(t)/(Smin(t)+sum(Smax([1:t-1,t+1:end])));
        wU(t)=Smax(t)/(Smax(t)+sum(Smin([1:t-1,t+1:end])));
    end
end

function [L,U]=fixLU(L,U,eps)
    L(isnan(L))=eps; U(isnan(U))=eps;
    L=max(L,eps);
    ix=L>U; tmp=L(ix); L(ix)=U(ix); U(ix)=tmp;
end

function dispLayer(name,L,U)
    k=(L+U)/2;
    fprintf('\n★ %s\n  #   Lower       Upper       Kernel\n',name)
    for i=1:numel(L)
        fprintf('%3d  %11.4f  %11.4f  %11.4f\n',i,L(i),U(i),k(i));
    end
end
