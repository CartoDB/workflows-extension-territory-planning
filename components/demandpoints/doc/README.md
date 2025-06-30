# Prepare Customers

Processes and formats demand points (customers, delivery addresses, clinics...) data for use in a Location Allocation analysis.

## Inputs
- **Customers input table**: The source table containing demand points data.

## Settings
- **ID column**: The column containing the unique identifier for each demand point.
- **Geometry column**: The column containing each demand point location.
- **Assign specific demand**: Whether each demand point should have an associated demand value. If enabled:
    - **Demand column**: The column containing demand values for each demand point.

## Outputs
- **Output table**: The table with the prepared demand points data, which contains the following columns: 
    - `dpoint_id`: The selected **ID column**.
    - `geom`: The selected **Geometry column**.
    - `demand`: The selected **Demand column**. If no demand column is provided, it will be filled up with `NULL` values.

> [!NOTE]  
> When no demand is set, the optimization determines which facility serves each demand point. Otherwise, the optimization determines how much demand is served by each facility for each demand point.