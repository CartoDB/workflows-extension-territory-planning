# Location Allocation

Performs Location Allocation optimization, enabling users to determine the best locations for facilities (e.g., warehouses, stores, hospitals, service centers) and assign demand points to those facilities. The goal is to minimize total/maximum cost or maximize coverage, while respecting a variety of customizable constraints.

This component uses [Google's OR-Tools](https://developers.google.com/optimization) under the hood for solving the optimization problem.

## Inputs
- **Facilities input table**: A table with facilities data, as produced by the [Prepare Facilities](../../facilities/doc/README.md#outputs).
- **Demand points input table**: A table with demand points data, as produced by the [Prepare Demand Points](../../demandpoints/doc/README.md#outputs).
- **Costs input table**: A table with costs data, as produced by the [Prepare Facilities](../../costs/doc/README.md#outputs).
- **Constraints input table**: `optional` A table with additional constraints metadata, as output by [Prepare Constraints](../../constraints/doc/README.md#outputs).

## Settings
- **Optimization strategy**: The strategy of the solver to solve optimization. It can be one of the following:
    - `Minimize total cost`: Minimizes the total sum of costs between assigned demand points and open facilities.
    - `Minimize maximum cost`: Minimizes the highest individual cost between any assigned facility-demand point pairs.
    - `Maximize coverage`: Maximizes the number of demand points within the specified coverage radius of each open facility.
- **Facilities coverage radius**: Maximum distance or time (e.g., in kilometers or minutes) that a facility can cover. Used for the "Maximize coverage" strategy.
- **Include required facilities**: Whether to consider mandatory facilities. If enabled, these facilities are guaranteed to be opened.
- **Include competitor facilities**: Whether to account for competitor locations that may influence demand point assignment.
- **Cost threshold**: The distance under which a demand point is considered fully influenced by a competitor, and thus removed from consideration.
- **Include cost of opening facilities**: If enabled, the fixed cost of opening each facility is added to the objective function.
- **Limit the total number of facilities**: If enabled, restricts the number of facilities that can be opened.
- **Maximum number of facilities**: The maximum number of facilities allowed to open if the above option is enabled.
- **Limit the total number of facilities per group**: If enabled, restricts the number of facilities that can be opened per defined group (e.g., region, brand).
- **Maximum number of facilities per group**: The maximum number of facilities allowed to open per group if the above option is enabled.
- **Satisfy demand points demand**: If enabled, ensures that the full demand of each demand point is met across assigned facilities.
- **Limit the minimum capacity of facilities**: If enabled, restricts facilities from being opened unless they meet a minimum utilization level.
- **Limit the maximum capacity of facilities**: If enabled, restricts the total amount of demand a facility can serve.
- **Force facility-demand point relationships**: Allows enforcing or excluding specific demand point-facility assignments (e.g., a facility must serve a specific demand point). Requires the **Constraints input table** to be connected.
- **Relative Gap Tolerance (%)**: The maximum allowed relative optimality gap between the best known solution and the theoretical optimum.
- **Maximum Solving Time (sec)**: The maximum allowed time taken for the solver to solve the problem (in seconds).




## Outputs
- **Output table**: The table with the optimized assignments: 
    - `facility_id`: The ID of the open facilities.
    - `dpoint_id`: The ID of the demand point.
    - `demand`: The amount of demand allocated from the facility to the demand point.
    - `geom`: The line geometry connecting the facility with the assigned demand point.
- **Metrics table**: The table with solver's metrics and statistics: 
    - `objective_value`: Final value of the objective function (e.g., total cost or coverage).
    - `gap`: The relative optimality gap between the best known solution and the theoretical optimum.
    - `solving_time`: Time taken for the solver to solve the problem (in seconds).
    - `termination_reason`: Reason why the solver stopped (e.g., optimal, infeasible...).
    - `stats`: Additional statistics such as open facilities ID, total demand satisfied or percentage of demand covered.