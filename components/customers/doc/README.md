# Prepare Customers

Processes and formats customer data for use in a Location Allocation analysis.

## Inputs
- **Customers input table**: The source table containing customer data.

## Settings
- **ID column**: The unique identifier for each customer.
- **Geometry column**: The point location of each customer. 
- **Assign demand to customers**: whether each customer should have an associated demand value. If enabled:
    - **Demand column**: The column containing demand values for each customer.

## Outputs
- **Output table**: The table with the prepared customers data, which contains the following columns: 
    - `customer_id`: The selected **ID column**.
    - `geom`: The selected **Geometry column**.
    - `demand`: The selected **Demand column**. If no demand column is provided, it will be filled with `NULL` values.

> [!NOTE]  
> When no demand is set, the optimization determines which facility serves each customer. Otherwise, the optimization determines how much demand is served by each facility for each customer.