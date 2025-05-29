# Territory Balancing

A component that splits a gridified area into a set of optimal, continuous territories, ensuring balance according to a specified metric while maintaining internal similarity within each territory.

If the input grid contains disconnected elements—such as isolated cells or cell clusters—the algorithm applies a proxy mechanism to establish connectivity across all regions. However, the presence of numerous unconnected components may lead to unexpected behavior or suboptimal results.

For more details, refer to the official [METIS](https://metis.readthedocs.io/en/latest/) documentation.

## Inputs
- **Input table**: The table with the gridify-enriched Area of Interest (AOI).

## Settings
- **Index column**: Unique identifier for each spatial cell. Must be an H3 or Quadbin index.
- **Demand column**: The business KPI used for balancing territories. This must be an extensive variable (i.e., one that adds up across space, such as number of points of sale, total population, etc.).
- **Similarity features(s)**: Optional variable(s) used to measure similarity between neighboring cells. The similarity score influences the grouping of the cells by penalizing large differences between them:
  - If multiple variables are selected, their values are normalized and averaged.
  - If a single variable is selected, it is normalized to the [0, 1] range. 
  - If no similarity features are provided, only the demand column is used for partitioning, and similarity is not considered.
- **Number of territories**: The desired number of partitions (i.e., territories) to divide the Area of Interest (AOI) into.
- **Keep input columns**: Whether to include all input columns in the output table.

## Outputs
- **Output table**: The table with the specified territories that will contain the index column, the territory ID (`cluster`) and, if specified, the remaining input columns.
