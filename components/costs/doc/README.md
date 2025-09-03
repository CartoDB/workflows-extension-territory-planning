# Cost Matrix Preparation

Processes and formats cost data for use in a Location Allocation analysis.

## Inputs
- **Costs input table**: The source table containing the cost of assigning each facility to each demand point (such as travel distace, travel time...).

## Settings
- **Facilities ID column**: The column containing the facility IDs.
- **Demand points ID column**: The column containing the demand point IDs.
- **Costs column**: The column containing the cost of assigning each facility to each demand point.
- **Apply transformation to cost**: Whether to apply a transformation to the cost. If enabled:
    - **Tranformation function**: The function to apply: `linear`, `power`, `exponential`.
    - **Tranformation parameter**: The parameter value to use. Only applicable for `power` and `exponential` transformations.

## Outputs
- **Output table**: The table with the prepared costs data, which contains the following columns: 
    - `facility_id`: The ID of the facilities.
    - `dpoint_id`: The ID of the demand points.
    - `cost`. The resulting cost.

> [!NOTE]  
> There user can use native workflows components to compute costs based on distance or time, such as [`Distance`](https://docs.carto.com/carto-user-manual/workflows/components/spatial-operations#distance-single-table) or [`Create Routing Matrix`](https://docs.carto.com/carto-user-manual/workflows/components/spatial-constructors#create-routing-matrix).