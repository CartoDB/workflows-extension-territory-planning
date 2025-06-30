# Prepare Constraints

Processes and formats constraint-specific additional data for use in a Location Allocation analysis.

## Inputs
- **Compatibility input table**: `optional` The source table containing required facility-demand point pairs (for every row k, facility k must serve demand point k).
- **Uncompatibility input table**: `optional` The source table containing banned facility-demand point pairs (for every row k, facility k cannot serve demand point k).

## Settings
- **Include required facility-demand point pairs**: Whether to consider mandatory relationships between facilities and demand points. Requires a **Compatibility input table** to be connected. If enabled:
    - **Facility ID column**: The column containing the facility IDs.
    - **Customer ID column**: The column containing the demand point IDs.
- **Include banned facility-demand point pairs**: Whether to consider prohibited relationships between facilities and demand points. Requires an **Unompatibility input table** to be connected. If enabled:
    - **Facility ID column**: The column containing the facility IDs.
    - **Customer ID column**: The column containing the demand point IDs.

## Outputs
- **Output table**: The table with the metadata of the prepared contraints data, which contains the following columns: 
    - `constraint_id`: The ID of the prepared data.
    - `constraint_description`: The description of the prepared data.
    - `table_name`. The name of the prepared table containning the necessary data to include `constraint_id` in the Location Allocation problem.

> [!NOTE]  
> As of now, this component is used to prepare data for the following constraint:
> - `compatibility`: Force facility-demand point relationships. It contains the following columns:
>   - `facility_id`: The column containing the facility IDs.
>   - `dpoint_id`: The column containing the demand point IDs.
>   - `compatibility`: The column containing the status of the relationship between each specified facility and demand point: required (1) or banned (0). If the facility-demand point pair is not specified in this table, the Locatioon Allocation algorithm will find the optimal assignment itself.