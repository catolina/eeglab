function rt_neuralynxproxy(cfg)

% RT_NEURALYNXPROXY reads continuous data from a Neuralynx Cheetah
% acquisition system and writes it to a FieldTrip buffer.
%
% The FieldTrip buffer is a network transparent server that allows the
% acquisition client to stream data to it. An analysis client can connect
% to read the data upon request. Multiple clients can connect simultaneously,
% each analyzing a specific aspect of the data concurrently.
%
% Use as
%   rt_neuralynxproxy(cfg)
%
% The configuration should contain
%   cfg.acquisition          = string, name of computer running the Cheetah software (default = 'fcdc284')
%   cfg.channel              = cell-array, see CHANNELSELECTION (default = 'all')
%
% The target to write the data to is configured as
%   cfg.target.datafile      = string, target destination for the data (default = 'buffer://localhost:1972')
%   cfg.target.dataformat    = string, default is determined automatic
%
% To stop this realtime function, you have to press Ctrl-C

% Copyright (C) 2008, Robert Oostenveld
%
% $Log: not supported by cvs2svn $
% Revision 1.8  2008/12/16 15:41:33  roboos
% added channelselection and implemented selection of subset of channels
% use channel names from neuralynx in the header
% slightly less verbose when writing
% changed method for collecting all data prior to writing (now explicit for loop)
%
% Revision 1.7  2008/11/03 16:09:03  roboos
% added defaults for target.eventxxx
% write all records data at once instead of using for-loop, this speeds the writing up because only one network connection has to be made
%
% Revision 1.6  2008/10/28 17:23:55  roboos
% added support for writing events
%
% Revision 1.5  2008/10/28 14:21:52  roboos
% first start with events
%
% Revision 1.4  2008/10/24 08:51:18  roboos
% renamed some cfg options, extended documentation
%
% Revision 1.3  2008/10/23 09:11:30  roboos
% also create and write header
% more efficient method of keeping track of the timstamp and completeness of records
% some other small improvements
%
% Revision 1.2  2008/10/21 07:26:04  roboos
% changed to unix format, added some comments, some small cleanup
%
% Revision 1.1  2008/10/21 07:19:38  roboos
% first implementation, not yet tested on streaming data
%

% set the defaults
if ~isfield(cfg, 'acquisition'),        cfg.acquisition = 'fcdc284';                      end
if ~isfield(cfg, 'target'),             cfg.target = [];                                  end
if ~isfield(cfg, 'channel'),            cfg.channel = 'all';                              end
if ~isfield(cfg.target, 'datafile'),    cfg.target.datafile = 'buffer://localhost:1972';  end
if ~isfield(cfg.target, 'dataformat'),  cfg.target.dataformat = [];                       end % default is to use autodetection of the output format
if ~isfield(cfg.target, 'eventfile'),   cfg.target.eventfile = 'buffer://localhost:1972'; end
if ~isfield(cfg.target, 'eventformat'), cfg.target.eventformat = [];                      end % default is to use autodetection of the output format

% this requires an external Neuralynx toolbox for the communication with Cheetah
hastoolbox('nlxnetcom', 1);

%% the record pool is used to collect the fragments while they become available
recordPool        = [];
recordStamp       = [];
recordComplete    = [];

%% Initialize
if ~NlxAreWeConnected
  disp(sprintf('Connecting to %s...', cfg.acquisition));
  succeeded = NlxConnectToServer(cfg.acquisition);
  if succeeded ~= 1
    fprintf('FAILED connect to %s. Exiting script.', cfg.acquisition);
    return;
  else
    fprintf('Connected to %s.', cfg.acquisition);
  end
end

%% Identify this program to the server we're connected to.
succeeded = NlxSetApplicationName('My Matlab Script');
if succeeded ~= 1
  disp 'FAILED set the application name'
else
  disp 'PASSED set the application name'
end

%% get a list of all objects in Cheetah, along with their types.
[succeeded, cheetahObjects, cheetahTypes] = NlxGetCheetahObjectsAndTypes;
if succeeded == 0
  disp 'FAILED get cheetah objects and types'
else
  disp 'PASSED get cheetah objects and types'
end

%% open up a stream for all objects
for index = 1:length(cheetahObjects)
  succeeded = NlxOpenStream(cheetahObjects(index));
  if succeeded == 0
    fprintf('FAILED to open stream for %s', char(cheetahObjects(index)));
    break;
  end
end;
if succeeded == 1
  disp 'PASSED open stream for all current objects'
end


cscIndex = find(strcmp('CscAcqEnt', cheetahTypes))';
cscCount = length(cscIndex);
evtIndex = find(strcmp('EventAcqEnt', cheetahTypes))';
evtCount = length(evtIndex);

% select a subset of channels
cfg.channel = channelselection(cfg.channel, cheetahObjects(cscIndex));
selIndex    = match_str(cheetahObjects, cfg.channel)';

hdr = []; % FIXME
targethdr = [];

numSamples = 0;
pass = 0;
again = true;

while again
  pass = pass + 1;

  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  % get the events
  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

  for objectIndex = evtIndex(:)'
    objectToRetrieve = cheetahObjects{objectIndex};
    [succeeded,  timeStampArray, eventIDArray, ttlValueArray, eventStringArray, numRecordsReturned, numRecordsDropped ] = NlxGetNewEventData(objectToRetrieve);

    if ~succeeded
      fprintf('FAILED to get new new events from stream %s on pass %d', objectToRetrieve, pass);
      break;

    elseif numRecordsReturned==0
      disp(sprintf('FAILED to get new events from stream %s on pass %d', objectToRetrieve, pass));
      break;

    else
      disp(sprintf('Retrieved %d new events from %s with %d dropped.', numRecordsReturned, objectToRetrieve, numRecordsDropped));

      if ~isempty(targethdr) && isfield(targethdr, 'FirstSampleTimeStamp') && isfield(targethdr, 'TimeStampPerSample')
        % convert to event array
        event = [];
        for i=1:numRecordsReturned
          event(i).type     = 'ttl';
          event(i).value    = ttlValueArray(i);
          event(i).sample   = double(uint64(timeStampArray(i))-targethdr.FirstSampleTimeStamp)/targethdr.TimeStampPerSample;
          event(i).offset   = 0;
          event(i).duration = 0;
        end
        % write the events
        write_event(cfg.target.eventfile, event, 'eventformat', cfg.target.eventformat);
      end
    end % if succeeded
  end % for all event streams

  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  % get the continuous data
  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  objectData = [];

  for objectIndex = cscIndex(selIndex)
    objectToRetrieve = cheetahObjects{objectIndex};
    % determine the type of acquisition entity we are currently indexed to and call the appropriate function for that type
    [succeeded, dataArray, timeStampArray, channelNumberArray, samplingFreqArray, numValidSamplesArray, numRecordsReturned, numRecordsDropped ] = NlxGetNewCSCData(objectToRetrieve);

    if ~succeeded
      fprintf('FAILED to get new data for CSC stream %s on pass %d', objectToRetrieve, pass);
      break;

    elseif numRecordsReturned==0
      disp(sprintf('FAILED to get new data for CSC stream %s on pass %d', objectToRetrieve, pass));
      break;

    else
      disp(sprintf('Retrieved %d CSC records for %s with %d dropped.', numRecordsReturned, objectToRetrieve, numRecordsDropped));

      objectData(objectIndex).dataArray            = reshape(dataArray, 512, numRecordsReturned);
      objectData(objectIndex).timeStampArray       = timeStampArray;
      objectData(objectIndex).channelNumberArray   = channelNumberArray;
      objectData(objectIndex).samplingFreqArray    = samplingFreqArray;
      objectData(objectIndex).numValidSamplesArray = numValidSamplesArray;
      objectData(objectIndex).numRecordsReturned   = numRecordsReturned;
      objectData(objectIndex).numRecordsDropped    = numRecordsDropped;

      selectValid = (numValidSamplesArray==512);
      if ~all(selectValid)
        warning('some samples were not valid')
      end

      % remove the records that are somehow corrupted
      objectData(objectIndex).dataArray            = objectData(objectIndex).dataArray(:,selectValid);
      objectData(objectIndex).timeStampArray       = objectData(objectIndex).timeStampArray(selectValid);
      objectData(objectIndex).channelNumberArray   = objectData(objectIndex).channelNumberArray(selectValid);
      objectData(objectIndex).samplingFreqArray    = objectData(objectIndex).samplingFreqArray(selectValid);
      objectData(objectIndex).numValidSamplesArray = objectData(objectIndex).numValidSamplesArray(selectValid);
      objectData(objectIndex).numRecordsValid      = sum(selectValid);
      objectData(objectIndex).numRecordsReturned   = numRecordsReturned;
      objectData(objectIndex).numRecordsDropped    = numRecordsDropped;

    end % if succeeded

  end % for objectIndex

  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  % create a fieldtrip compatible header structure
  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  if isempty(hdr) && ~isempty(objectData) && ~isempty(objectData(1))
    hdr.Fs                 = objectData(1).samplingFreqArray(1);  % sampling frequency
    hdr.nChans             = length(selIndex);                    % number of channels
    hdr.nSamples           = 0;                                   % number of samples per trial
    hdr.nSamplesPre        = 0;                                   % number of pre-trigger samples in each trial
    hdr.nTrials            = 1;                                   % number of trials, 1 means continuous
    hdr.label              = cheetahObjects(cscIndex(selIndex));  % cell-array with labels of each channel
    hdr.FirstTimeStamp     = nan;
    hdr.TimeStampPerSample = nan;
  end

  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  % reorganize the objects into records that each contain a Nchan X Nsamples
  % data matrix
  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

  for i=1:numel(objectData)
    nrec = numel(objectData(i).channelNumberArray);
    for j=1:nrec

      if ~isempty(recordPool)
        % The temporary variable is to work around a MATLAB bug in version 7.5 on windows
        % see http://www.mathworks.com/support/bugreports/details.html?rp=425978
        tmp = objectData(i).timeStampArray(j);
        sel = find(recordStamp==tmp);
      else
        sel = [];
      end

      if isempty(sel)
        % create a new record in the pool
        recordComplete(end+1)       = false;
        recordStamp(end+1)          = objectData(i).timeStampArray(j);
        recordPool(end+1).timeStamp = objectData(i).timeStampArray(j);
        recordPool(end  ).chanCount = 0;
        recordPool(end  ).skipCount = 0;
        recordPool(end  ).present   = false(cscCount, 1);
        recordPool(end  ).dat       = zeros(cscCount, 512);
        sel = numel(recordPool);
      end

      % add this data to the selected record
      chan = objectData(i).channelNumberArray(j) + 1; % should be offset 1 instead of 0
      recordPool(sel).present(chan) = true;
      recordPool(sel).dat(chan,:)   = objectData(i).dataArray(:,j);
      recordPool(sel).chanCount     = recordPool(sel).chanCount + 1;
      recordComplete(sel)           = all(recordPool(sel).present(selIndex));
    end
  end % for all objects that were acuired

  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  % write the records that are complete
  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  if any(recordComplete)
    last = find(recordComplete, 1, 'last');

    % give some feedback and fix the recordComplete vector
    fprintf('writing %d records\n', last);

%     for i=1:last
%       if recordComplete(i)
%         fprintf('writing complete record with timestamp %d\n', recordPool(i).timeStamp);
%       else
%         fprintf('writing incomplete record with timestamp %d\n', recordPool(i).timeStamp);
%       end
%     end

    % all records up to the last complete one will be written
    recordComplete(1:last) = true;

    if ~isempty(last)
      % concatenate all data in a single Nchans X Nsamples array
      % only use the selected channels, the other channels will all be zero
      alldata = zeros(length(selIndex), last*512);
      for i=1:last
        begsample = (i-1)*512+1;
        endsample = (i  )*512;
        alldata(:,begsample:endsample) = recordPool(i).dat(selIndex,:);
      end

      if numSamples==0
        % write the header and write data of this record to the buffer
        write_data(cfg.target.datafile, alldata, 'dataformat', cfg.target.dataformat, 'header', hdr, 'append', false);
        targethdr.FirstSampleTimeStamp = uint64(recordPool(1).timeStamp); % this is only defined once
      else
        % write the data of this record to the buffer
        write_data(cfg.target.datafile, alldata, 'dataformat', cfg.target.dataformat, 'append', true);
      end
      targethdr.TimeStampPerSample   = double(uint64(recordPool(i).timeStamp) - targethdr.FirstSampleTimeStamp)/numSamples;
      numSamples                     = numSamples + size(recordPool(i).dat,2);

      clear alldata
    end
  end

  % remove the records that have been written, i.e. keep all others
  recordPool      = recordPool(~recordComplete);
  recordStamp     = recordStamp(~recordComplete);
  recordComplete  = recordComplete(~recordComplete);

  fprintf('pass %d, there are %d records remaining in the pool\n', pass, numel(recordPool));

end % while again
