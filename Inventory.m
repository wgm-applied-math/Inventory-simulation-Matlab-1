classdef Inventory < handle
    % Inventory Simulation of an inventory system.
    %   Simulation object that keeps track of orders, incoming material,
    %   outoing material, material on hand, and costs.
    %
    %   Some jargon: A _request_ for material means that the entity modeled
    %   by this object orders a batch of material from a supplier, and it
    %   will replenish this inventory. An _order_ for material means that a
    %   customer orders material, and that order will be filled out of this
    %   inventory.
    %
    %   Each time step represents one day during which orders arrive and
    %   are filled.  When the on-hand amount drops below ReorderPoint, a
    %   request is placed for RequestBatchSize (continuous review). The
    %   requested material arrives on at the beginning of the day, at time
    %   floor(now + RequestLeadTime).

    properties (SetAccess = public)
        % OnHand - Amount of material on hand
        OnHand = 200;

        % RequestCostPerBatch - Fixed cost to request a batch of material,
        % independent of the size of the batch.
        RequestCostPerBatch = 25.0;

        % RequestCostPerUnit - Variable cost factor; cost of each unit
        % requested in a batch.
        RequestCostPerUnit = 3.0;

        % HoldingCostPerUnitPerDay - Cost to hold one unit of material
        % on hand for one day.
        HoldingCostPerUnitPerDay = 0.05/7;

        % ShortageCostPerUnitPerDay - Cost factor for a backlogged
        % order; how much it costs to be one unit short for one day.
        ShortageCostPerUnitPerDay = 2.00/7;

        % RequestBatchSize - When requesting a batch of material, how many
        % units to request in a batch.
        RequestBatchSize = 200;

        % ReorderPoint - When the amount of material on hand drops to this
        % many units, request another batch.
        ReorderPoint = 50;

        % RequestLeadTime - When a batch is requested, it will be this
        % many time step before the batch arrives.
        RequestLeadTime = 2.0;

        % OutgoingSizeDist - Distribution sampled to determine the size of
        % random outgoing orders placed to this inventory.
        OutgoingSizeDist = makedist("Gamma", a=10, b=2);

        % DailyOrderCountDist - Distribution sampled to determine the
        % number of random outgoing orders placed to this inventory per
        % day.
        DailyOrderCountDist = makedist("Poisson", lambda=4);
    end
    properties (SetAccess = private)
        % Time - Current time
        Time = 0.0;

        % RequestPlaced - True if a request has been made for a batch of
        % material to replenish this inventory, but has not yet arrived.
        % False if the inventory is not waiting for a request to be
        % fulfilled. If a request has been placed, no additional request
        % will be placed until it has been fulfilled.
        RequestPlaced = false;

        % Events - PriorityQueue of events ordered by time.
        Events;

        % Log - Table of log entries.  Each row is an entry that includes
        % part of the current state of the inventory and the totals of
        % various costs incurred up to the time of the entry.  The columns
        % are:
        % * Time - Time of the entry
        % * OnHand - Amount of material on hand
        % * Backlog - Total amount of all backlogged orders
        % * RunningPerBatchCost - Total of per-batch costs
        % * RunningPerUnitCost - Total of per-unit costs
        % * RunningHoldingCost - Total of holding costs
        % * RunningShortageCost - Total of shortage costs
        % * RunningInventoryVariableCost - Total of per-batch, holding, and
        % shortage costs, that is, everything except the per-unit costs,
        % which are determined by demand rather than inventory management
        % * RunningCost - Total of all costs
        Log = table( ...
            Size=[0, 9], ...
            VariableNames={'Time', 'OnHand', 'Backlog', ...
            'RunningPerBatchCost', 'RunningPerUnitCost', 'RunningHoldingCost', ...
            'RunningShortageCost', 'RunningInventoryVariableCost', ...
            'RunningCost'}, ...
            VariableTypes={'double', 'double', 'double', ...
            'double', 'double', 'double', ...
            'double', 'double', ...
            'double'});

        % RunningPerBatchCost - Total per-batch request costs incurred so
        % far.
        RunningPerBatchCost = 0.0;

        % RunningPerUnitCost - Total per-unit request costs so far.  This
        % cost is unavoidable if we are to meed demand.  It is often
        % excluded from EOQ calculations.
        RunningPerUnitCost = 0.0;

        % RunningHoldingCost - Total holding costs inucrred so far.
        RunningHoldingCost = 0.0;

        % RunningShortageCost - Total shortage costs incurred so far.
        RunningShortageCost = 0.0;

        % RunningInventoryVariableCost - Total of per-batch costs, holding
        % costs, and shortage costs incurred so far.  Excludes per-unit
        % request cost, since that is determined by demand and cannot be
        % changed by inventory policy.
        RunningInventoryVariableCost = 0.0;

        % RunningCost - Total cost of all kinds incurred so far.
        RunningCost = 0.0;

        % Backlog - List of currently backlogged orders.  These are
        % OrderReceived objects.  They are removed from this list and
        % rescheduled when requested material arrives and replenishes the
        % amount on hand.
        Backlog = {};

        % Fulfilled - List of fulfilled orders.
        Fulfilled = {};
    end
    methods
        function obj = Inventory(KWArgs)
            % Inventory Constructor.
            % Public properties can be specified as named arguments.
            arguments
                KWArgs.?Inventory;
            end
            fnames = fieldnames(KWArgs);
            for ifield=1:length(fnames)
                s = fnames{ifield};
                obj.(s) = KWArgs.(s);
            end
            % Events has to be initialized in the constructor.
            obj.Events = PriorityQueue({}, @(x) x.Time);

            % The first event is to begin the first day.
            schedule_event(obj, BeginDay(Time=0));
        end

        function obj = run_until(obj, MaxTime)
            % run_until Event loop.
            %
            % obj = run_until(obj, MaxTime) Repeatedly handle the next
            % event until the current time is at least MaxTime.

            while obj.Time <= MaxTime
                handle_next_event(obj)
            end
        end

        function schedule_event(obj, event)
            % schedule_event Add an event object to the event queue.

            assert(event.Time >= obj.Time, ...
                "Event happens in the past");
            push(obj.Events, event);
        end

        function handle_next_event(obj)
            % handle_next_event Pop the next event and use the visitor
            % mechanism on it to do something interesting.

            assert(~is_empty(obj.Events), ...
                "No unhandled events");
            event = pop_first(obj.Events);
            assert(event.Time >= obj.Time, ...
                "Event happens in the past");
            obj.Time = event.Time;
            visit(event, obj);
        end

        function handle_begin_day(obj, ~)
            % handle_begin_day Generate random orders that come in today.
            %
            % handle_begin_day(obj, begin_day_event) - Handle a BeginDay
            % event.  Generate a random number of orders of random sizes
            % that arrive at uniformly spaced times during the day.  Each
            % is represented by an OrderReceived event and added to the
            % event queue.  Also schedule the EndDay event for the end of
            % today, and the BeginDay event for the beginning of tomorrow.
            n_orders = random(obj.DailyOrderCountDist);
            for j=1:n_orders
                amount = random(obj.OutgoingSizeDist);
                order_received_time = obj.Time+j/(1+n_orders);
                event = OrderReceived( ...
                    Time=order_received_time, ...
                    Amount=amount, ...
                    OriginalTime=order_received_time);
                schedule_event(obj, event);
            end
            % Schedule the end of the day
            schedule_event(obj, EndDay(Time=obj.Time+0.99));
        end

        function handle_shipment_arrival(obj, arrival)
            % handle_shipment_arrival A shipment has arrived in response to
            % a request.
            %
            % handle_shipment_arrival(obj, arrival_event) - Handle a
            % ShipmentArrival event.  Add the amount of material in this
            % shipment to the on-hand amount.  Reschedule all backlogged
            % orders to run immediately.  Set RequestPlaced to false.

            % Add received amount to on-hand amount.
            obj.OnHand = obj.OnHand + arrival.Amount;

            % Reschedule all the backlogged orders for right now.
            for j=1:length(obj.Backlog)
                order = obj.Backlog{j};
                order.Time = obj.Time;
                schedule_event(obj, order);
            end
            obj.Backlog = {};
            obj.RequestPlaced = false;
        end

        function maybe_request_more(obj)
            % maybe_request_more If the amount of material on-hand is below
            % the ReorderPoint, place a request for more.
            %
            % If a request has been placed but not yet fulfilled, no
            % additional request is placed.

            if ~obj.RequestPlaced && obj.OnHand <= obj.ReorderPoint
                obj.RunningInventoryVariableCost = ...
                    obj.RunningInventoryVariableCost ...
                    + obj.RequestCostPerBatch;
                obj.RunningPerBatchCost = obj.RunningPerBatchCost ...
                    + obj.RequestCostPerBatch;
                obj.RunningPerUnitCost = obj.RunningPerUnitCost ...
                    + obj.RequestBatchSize * obj.RequestCostPerUnit;
                ThisRequestCost = obj.RequestCostPerBatch ...
                    + obj.RequestBatchSize * obj.RequestCostPerUnit;
                obj.RunningCost = obj.RunningCost + ThisRequestCost;
                arrival = ShipmentArrival( ...
                    Time=floor(obj.Time+obj.RequestLeadTime), ...
                    Amount=obj.RequestBatchSize);
                schedule_event(obj, arrival);
                obj.RequestPlaced = true;
            end
        end

        function handle_order_received(obj, order)
            % handle_order_received Handle an OrderReceived event.
            %
            % handle_order_received(obj, order) - If there is enough
            % material on hand to fulfill the order, deduct the Amount of
            % the order from OnHand, and append the order to the Fulfilled
            % list.  Otherwise, append the order to the Backlog list. Then
            % call maybe_request_more.  There is no attempt to partially
            % fill an order.
            if obj.OnHand >= order.Amount
                obj.OnHand = obj.OnHand - order.Amount;
                obj.Fulfilled{end+1} = order;
            else
                obj.Backlog{end+1} = order;
            end
            maybe_request_more(obj);
        end

        function handle_end_day(obj, ~)
            % handle_end_day Handle an EndDay event.
            %
            % handle_end_day(obj, end_day) - Record holding cost for the
            % amount of material on hand.  Record shortage cost for the
            % total amount of all backlogged orders.  Record an entry to
            % the Log table.  Schedule the beginning of the next day to
            % happen immediately.
            %
            % *Note:* There is no separate RecordToLog event in this
            % simulation like there is in ServiceQueue.
            TodayHoldingCost = obj.OnHand * obj.HoldingCostPerUnitPerDay;
            obj.RunningHoldingCost = obj.RunningHoldingCost + TodayHoldingCost;
            TodayShortageCost = total_backlog(obj) * obj.ShortageCostPerUnitPerDay;
            obj.RunningShortageCost = obj.RunningShortageCost ...
                + TodayShortageCost;
            obj.RunningInventoryVariableCost = ...
                obj.RunningInventoryVariableCost ...
                + TodayHoldingCost + TodayShortageCost;
            obj.RunningCost = obj.RunningCost ...
                + TodayHoldingCost + TodayShortageCost;
            record_log(obj);
            % Schedule the beginning of the next day to happen immediately.
            schedule_event(obj, BeginDay(Time=obj.Time));
        end

        function tb = total_backlog(obj)
            % total_backlog Compute the total amount of all backlogged
            % orders.
            tb = 0;
            for j = 1:length(obj.Backlog)
                tb = tb + obj.Backlog{j}.Amount;
            end
        end

        function record_log(obj)
            % record_log Add an entry to the Log table.
            tb = total_backlog(obj);
            obj.Log(end+1, :) = {obj.Time, obj.OnHand, tb, ...
                obj.RunningPerBatchCost, obj.RunningPerUnitCost, ...
                obj.RunningHoldingCost, obj.RunningShortageCost, ...
                obj.RunningInventoryVariableCost, ...
                obj.RunningCost};
        end

        function frac = fraction_orders_backlogged(obj)
            % fraction_orders_backlogged Compute the fraction of all
            % fulfilled orders that were backlogged.
            NFulfilled = length(obj.Fulfilled);
            NBacklogged = 0;
            for j = 1:NFulfilled
                x = obj.Fulfilled{j};
                if x.Time > x.OriginalTime
                    NBacklogged = NBacklogged + 1;
                end
            end
            frac = NBacklogged / NFulfilled;
        end

        function DelayTimes = fulfilled_order_delay_times(obj)
            % iterate over obj.Fulfilled:
            NumFulfilled = length(obj.Fulfilled);
            DelayTimes = zeros([NumFulfilled, 1]);
            for j = 1:NumFulfilled
                x = obj.Fulfilled{j};
                DelayTimes(j) = x.Time - x.OriginalTime;
            end

        end
    end
end
