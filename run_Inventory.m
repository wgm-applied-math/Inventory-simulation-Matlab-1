%% Run samples of the Inventory simulation
%
% Collect statistics and plot histograms along the way.

%% Set up

% Set-up and administrative cost for each batch requested.
K = 25.00;

% Per-unit production cost.
c = 3.00;

% Lead time for production requests.
L = 2;

% Holding cost per unit per day.
h = 0.05/7;

% Reorder point.
ROP = 141;

% Batch size.
Q = 758;

% How many samples of the simulation to run. NumSamples = 100
NumSamples = 100;

% Run each sample for this many days. MaxTime=1000
MaxTime = 1000;

%% Run simulation samples

% Make this reproducible
rng("default");

% Samples are stored in this cell array of Inventory objects
InventorySamples = cell([NumSamples, 1]);


% Run samples of the simulation.
% Log entries are recorded at the end of every day
for SampleNum = 1:NumSamples
    fprintf("Working on %d\n", SampleNum);
    inventory = Inventory( ...
        RequestCostPerBatch=K, ...
        RequestCostPerUnit=c, ...
        RequestLeadTime=L, ...
        HoldingCostPerUnitPerDay=h, ...
        ReorderPoint=ROP, ...
        OnHand=Q, ...
        RequestBatchSize=Q);
    run_until(inventory, MaxTime);
    InventorySamples{SampleNum} = inventory;
end


%% Collect statistics

% Pull the RunningCost from each complete sample.
TotalCosts = cellfun(@(i) i.RunningCost, InventorySamples);

% Express it as cost per day and compute the mean, so that we get a number
% that doesn't depend directly on how many time steps the samples run for.
meanDailyCost = mean(TotalCosts/MaxTime);
fprintf("Mean daily cost: %f\n", meanDailyCost);

        
%% Daily Cost
% Make a figure with one set of axes.
fig = figure();
t = tiledlayout(fig,1,1);
ax = nexttile(t);

% Histogram of the cost per day.
h = histogram(ax, TotalCosts/MaxTime, Normalization="probability", ...
    BinWidth=5);

% Add title and axis labels
title(ax, "Daily total cost");
xlabel(ax, "Dollars");
ylabel(ax, "Probability");

% Fix the axis ranges
% ylim(ax, [0, 0.5]);
% xlim(ax, [240, 290]);

% Wait for MATLAB to catch up.
pause(2);

% Save figure as a PDF file
exportgraphics(fig, "Daily cost histogram.pdf");

%% Fraction of orders that get backlogged

FractionOrdersBacklogged = zeros([NumSamples,1]);

for SampleNum = 1:NumSamples
    inventory = InventorySamples{SampleNum};
    FractionOrdersBacklogged(SampleNum) = fraction_orders_backlogged(inventory);
end

% create figure for fraction of orders that get backlogged
fig = figure();
t = tiledlayout(fig,1,1);
ax = nexttile(t);

% Histogram of the cost per day.
h = histogram(ax, FractionOrdersBacklogged, Normalization="probability");

% Add title and axis labels
title(ax, "Fraction of Orders that get Backlogged");
xlabel(ax, "Fraction of Orders Backlogged");
ylabel(ax, "Probability");

% Wait for MATLAB to catch up.
pause(2);

% Save figure as a PDF file
exportgraphics(fig, "Fraction of Orders that get Backlogged.pdf");

%% Fraction of days with non-zero backlog

FractionNonZeroBacklog = zeros([NumSamples,1]);

for SampleNum = 1:NumSamples
    inventory = InventorySamples{SampleNum};
    FractionNonZeroBacklog(SampleNum) = fraction_days_backlogged(inventory);
end

MeanFractionNonZeroBacklog = mean(FractionNonZeroBacklog);
fprintf("An estimate of how often backlogs occur: every %f days\n", 1/MeanFractionNonZeroBacklog);

% Make a figure with one set of axes.
fig = figure();
t = tiledlayout(fig,1,1);
ax = nexttile(t);

% Histogram of the cost per day.
h = histogram(ax, FractionNonZeroBacklog, Normalization="probability");

% Add title and axis labels
title(ax, "Fraction of Days with a Non-zero Backlog");
xlabel(ax, "Fraction of Days with Non-zero Backlog");
ylabel(ax, "Probability");

% Wait for MATLAB to catch up.
pause(2);

% Save figure as a PDF file
exportgraphics(fig, "Non-zero Backlog Histogram.pdf");

%% Delay time of order that get backlogged

DelayTimeSamples = cell([NumSamples, 1]);

for SampleNum = 1:NumSamples
    inventory = InventorySamples{SampleNum};
    dt = fulfilled_order_delay_times(inventory);
    DelayTimeSamples{SampleNum} = dt(dt > 0);
end

DelayTimes = vertcat(DelayTimeSamples{:});

% create figure for delay time of orders that get backlogged
fig = figure();
t = tiledlayout(fig,1,1);
ax = nexttile(t);

% Histogram of the cost per day.
h = histogram(ax, DelayTimes, Normalization="probability");

% Add title and axis labels
title(ax, "Delay Times of Backlogged Orders");
xlabel(ax, "Delay Times of Backlogged Orders");
ylabel(ax, "Probability");

% Fix the axis ranges
% ylim(ax, [0, 0.5]);
% xlim(ax, [240, 290]);

% Wait for MATLAB to catch up.
pause(2);

% Save figure as a PDF file
exportgraphics(fig, "Delay Time of Backlogged Orders.pdf");

%% Total backlog amount

BacklogAmountSamples = cell([NumSamples, 1]);

for SampleNum = 1:NumSamples
    inventory = InventorySamples{SampleNum};
    bd = inventory.Log.Backlog > 0;
    BacklogAmountSamples{SampleNum} = inventory.Log.Backlog(bd);

end

BacklogAmounts = vertcat(BacklogAmountSamples{:});

% create figure for daily backlogged amounts
fig = figure();
t = tiledlayout(fig,1,1);
ax = nexttile(t);

% Histogram of the cost per day.
h = histogram(ax, BacklogAmounts, Normalization="probability", ...
    BinWidth=5);

% Add title and axis labels
title(ax, "Total Backlog Amounts");
xlabel(ax, "Units of Cereal");
ylabel(ax, "Probability");

% Fix the axis ranges
% ylim(ax, [0, 0.5]);
% xlim(ax, [240, 290]);

% Wait for MATLAB to catch up.
pause(2);

% Save figure as a PDF file
exportgraphics(fig, "Total Backlog Amounts.pdf");
