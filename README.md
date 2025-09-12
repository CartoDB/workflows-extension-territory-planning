# Territory Planning Extension Package

## Description

An extension package for CARTO Workflows that provides comprehensive territory planning and location allocation optimization capabilities. This package enables users to solve complex spatial optimization problems by creating balanced territorial boundaries, or finding optimal facility locations, allocating demand points to facilities, and managing territorial constraints while minimizing costs or maximizing coverage. 

## Components

### 1. **Facilities Preparation**
Prepares facility data for location allocation optimization. Handles three types of facilities:
- **Candidate facilities**: Potential locations that could be opened based on optimization strategy
- **Required facilities**: Mandatory locations that are always activated regardless of strategy  
- **Competitor facilities**: Existing competitor locations that influence demand allocation

Supports advanced features like facility grouping, capacity constraints (min/max), and opening costs.

[📖 Documentation](components/facilities/doc/)

### 2. **Demand Points Preparation**
Prepares customer or demand point data for the optimization process. Processes locations that require service allocation such as customers, delivery addresses, or service points and optionally handles demand values for capacity-based optimization.

[📖 Documentation](components/demandpoints/doc/)

### 3. **Cost Matrix Preparation**
Prepares cost data (such as travel distance, travel time, or transportation costs) that define the assignment cost between each facility and demand point. Includes optional cost transformations (linear, power, exponential) to model different cost relationships and validates data integrity to ensure complete cost coverage.

[📖 Documentation](components/costs/doc/)

### 4. **Constraints Definition**
Adds constraint definitions for location allocation that control facility-demand point relationships:
- **Required relationships**: Required facility-demand point assignments that must be maintained
- **Forbidden relationships**: Prohibited facility-demand point assignments that must be avoided

Helps enforce business rules and regulatory requirements in the optimization process.

[📖 Documentation](components/constraints/doc/)

### 5. **Location-Allocation**
The main optimization component that performs territory planning using advanced location allocation algorithms. Supports multiple optimization strategies:
- **Minimize total cost**: Reduces overall system costs
- **Minimize maximum cost**: Reduces worst-case assignment costs  
- **Maximize coverage**: Maximizes demand point coverage within distance limits

Includes comprehensive parameter controls for facilities limits, capacity constraints, competitor influence, demand satisfaction, and solver performance tuning.

[📖 Documentation](components/locationallocation/doc/)

> [!IMPORTANT]  
It is mandatory to use the `Prepare` components in advance, to ensure correct formatting of input sources.

### 6. **Territory Balancing**
An advanced spatial optimization component that splits a gridified area (H3 or Quadbin cells only) into a set of optimal, continuous territories. This component ensures balance according to a specified business metric while maintaining internal similarity within each territory.

[📖 Documentation](components/territorybalancing/doc/) | [🚀 CloudRun Deployment](cloudrun/territorybalancing/)


## Building the extension

To build the extension, follow these steps:

1. Install the required dependencies:
   ```
   pip install -r requirements.txt
   ```

2. Package the extension:
   ```
   python carto_extension.py package
   ```

This will create a packaged version of the extension that can be installed in your CARTO Workflows.

## Deploying the Cloud Run service
**Territory Balancing** is deployed as a scalable microservice for handling large spatial datasets. Follow the steps in [here](cloudrun/territorybalancing/) to deploy.

## Running the tests

To run the extension tests, follow these steps:

1. **Set up environment configuration**: Create a `.env` file from the template and configure your database connection settings.

2. Install the required dependencies:
   ```
   pip install -r requirements.txt
   ```

3. Run the test suite:
   ```
   python carto_extension.py pytest
   ```

> [!WARNING]  
> **Special setup required for Location-Allocation tests**: Due to component dependencies, you may encounter errors when testing the [`locationallocation`](components/locationallocation/) component. 
>
> **Recommended workflow**:
> 1. First, run the [`constraints`](components/constraints/test/test.json) component tests in normal mode
> 2. Copy the output table name into [`constraints.ndjson`](components/locationallocation/test/constraints.ndjson)  
> 3. Switch the [`constraints`](components/constraints/test/test.json) test to `skip` mode in its configuration
> 4. Run the complete test suite together
>
> This ensures the required constraint tables exist before testing the location allocation optimization.