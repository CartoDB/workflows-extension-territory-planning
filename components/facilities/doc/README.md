# Prepare Facilities

Processes and formats facilities data for use in a Location Allocation analysis.

## Inputs
- **Candidate Facilities input table**: The source table containing candidate facility data. These represent facilities that could be opened or activated based on the allocation strategy.
- **Required Facilities input table**: `optional` The source table containing required facility data. These are pre-selected locations that are always active, regardless of optimization results.
- **Competitor Facilities input table**: `optional` The source table containing competitors data. These are used to model competition and influence demand allocation or market share in the optimization process.

## Settings
- **Candidate facilities ID column**: The column containing the candidate facility unique IDs.
- **Candidate facilities geometry column**: The column containing the candidate facility point locations.
- **Include required facilities**: Whether to consider mandatory or pre-selected facilities. Requires a **Required Facilities input table** to be connected. If enabled:
    - **Required facilities ID column**: The column containing the required facility unique IDs.
    - **Required facilities geometry column**: The column containing the required facility point locations.
- **Include competitor facilities**: Whether to consider competitors. Requires a **Competitor Facilities input table** to be connected. If enabled:
    - **Competitor facilities ID column**: The column containing the competitor facility unique IDs.
    - **Competitor facilities geometry column**: The column containing the competitor facility point locations.
- **Assign groups to facilities**: Whether to assign a group to each facility (i.e. zip codes, brands). 
    - **Candidate facilities group ID column**: The column containing the ID representing the group each candidate facility belongs to.
    - **Required facilities group ID column**: The column containing the ID representing the group each required facility belongs to. Requires a **Required Facilities input table** to be connected. 
- **Assign minimum capacity to facilities**: Whether to include the minimum capacity of a facility. 
    - **Candidate facilities minimum capacity column**: The column containing the minimum capacity of each candidate facility.
    - **Required facilities minimum capacity column**: The column containing the minimum capacity of each required facility. Requires a **Required Facilities input table** to be connected. 
- **Assign maximum capacity to facilities**: Whether to include the maximum capacity of a facility. 
    - **Candidate facilities maximum capacity column**: The column containing the maximum capacity of each candidate facility.
    - **Required facilities maximum capacity column**: The column containing the maximum capacity of each required facility. Requires a **Required Facilities input table** to be connected. 
- **Include cost of opening facilities**: Whether to include the fixed costs of opening a specific facility. 
    - **Candidate facilities cost of open column**: The column containing the cost of opening each candidate facility.
    - **Required facilities cost of open column**: The column containing the cost of opening each required facility. Requires a **Required Facilities input table** to be connected. 

## Outputs
- **Output table**: The table with the prepared facilities data, which contains the following columns: 
    - `facility_id`: The selected **ID column**.
    - `geom`: The selected **Geometry column**.
    - `facility_type`: The type of facility: candidate (0), required (1) or competitor (2).
    - `group_id`: The selected **Group ID column**. If no group ID column is provided, it will be filled up with `NULL` values.
    - `min_capacity`: The selected **Minimum capacity column**. If no minimum capacity column is provided, it will be filled up with `NULL` values.
    - `max_capacity`: The selected **Maximum capacity column**. If no maximum capacity column is provided, it will be filled up with `NULL` values.
    - `cost_of_open`: The selected **Cost of open column**. If no cost of open column is provided, it will be filled up with `NULL` values.

> [!NOTE]  
> Facility IDs must be unique in the sense that the overall set of facilities (candidate + required + competitor) cannot have duplicated IDs.