%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% these are the data specific parameters
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

m_array = [0 1 8 64 128];       % number of channels
n_array = [0 10 100 500 1000];  % number of samples
niter   = 10;                   % number of iterations with the same parameter/variable set

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% these are the function specific parameters
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

funname = 'preproc_detrend';

clear argname 
argname{1} = 'begsample';
argname{2} = 'endsample';
argname{3} = 'order';

clear argval 
argval{1} = [];
argval{2} = [];
argval{3} = nan;

% use varying polynomial order
argval{3} = 1;
benchmark(funname, argname, argval, m_array, n_array, niter, 'feedback', 'table', 'tableheader', true, 'tabledata', true)
argval{3} = 2;
benchmark(funname, argname, argval, m_array, n_array, niter, 'feedback', 'table', 'tableheader', false, 'tabledata', true)
argval{3} = 3;
benchmark(funname, argname, argval, m_array, n_array, niter, 'feedback', 'table', 'tableheader', false, 'tabledata', true)
