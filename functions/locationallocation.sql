CREATE OR REPLACE FUNCTION @@workflows_temp@@.`LOCATION_ALLOCATION`(    
    optimization_strategy STRING,
    facility_id ARRAY<STRING>,
    facility_type ARRAY<INT64>,
    facility_group_id ARRAY<STRING>,
    facility_min_usage ARRAY<FLOAT64>,
    facility_max_capacity ARRAY<FLOAT64>,
    facility_cost_of_open ARRAY<FLOAT64>,
    dpoint_id ARRAY<STRING>,
    dpoint_demand ARRAY<FLOAT64>,
    cost_facility_id ARRAY<STRING>,
    cost_dpoint_id ARRAY<STRING>,
    cost ARRAY<FLOAT64>,
    compatibility_facility_id ARRAY<STRING>,
    compatibility_dpoint_id ARRAY<STRING>,
    compatibility_type ARRAY<INT64>,
    required BOOLEAN, 
    max_limit INT64,
    max_group_limit INT64,
    min_usage BOOLEAN,
    max_capacity BOOLEAN,
    compatibility BOOLEAN,
    add_demand BOOLEAN,
    add_fixed_costs BOOLEAN,
    coverage_radius FLOAT64,
    budget_constraint FLOAT64,
    time_limit INT64,
    relative_gap INT64,
    verbose BOOLEAN
)
RETURNS ARRAY<STRUCT<facility_id STRING, dpoint_id STRING, demand FLOAT64, objective_value FLOAT64, gap FLOAT64, solving_time FLOAT64, termination_reason STRING, stats STRING>>

LANGUAGE python
OPTIONS (
    entry_point='main',
    runtime_version='python-3.11',
    max_batching_rows=1,
    container_memory='8Gi', container_cpu=2,
    packages=['ortools==9.9.3963','pandas==2.2.3','numpy==1.23.5']
)
AS r"""
import math
import random
import pandas as pd
import numpy as np
from ortools.linear_solver import pywraplp
import sys
from typing import Dict, List, Optional

def extract_data(input_data, items):
    '''Extract data from input dictionary'''
    df = {}
    for item in items:
        df.update(input_data[item])
    return pd.DataFrame(df)
    
class Facilities:
    '''Represent facility data'''
    def __init__(self, df: pd.DataFrame):
        df = df.sort_values('facility_id').reset_index(drop=True).copy()
        self.index = df.index.tolist()
        self.id = df['facility_id'].tolist()
        self.type = df['facility_type'].tolist()
        self.group_id = df['group_id'].tolist()
        self.min_usage = df['min_usage'].tolist()
        self.max_capacity = df['max_capacity'].tolist()
        self.cost_of_open = df['cost_of_open'].tolist()

class DemandPoints:
    '''Represent dpoint data'''
    def __init__(self, df: pd.DataFrame):
        df = df.sort_values('dpoint_id').reset_index(drop=True).copy()
        self.index = df.index.tolist()
        self.id = df['dpoint_id'].tolist()
        self.demand = df['demand'].tolist()

class Costs:
    '''Represent cost matrix'''
    def __init__(self, df: pd.DataFrame):
        self.facility_id = df.index.tolist()
        self.dpoint_id = df.columns.tolist()
        self.c = df.values.tolist()

class Constraints:
    '''Represent constraint-specific data'''
    def __init__(self):
        self.compatibility = None

    def add_compatibility_constraint(self, df: pd.DataFrame, facilities: Facilities, dpoints: DemandPoints, required: bool = False):
        '''Add compatibility constraints between facilities and dpoints'''
        if not required:
            df = df[df.facility_id.isin(facilities.id)].copy()
        df['facility_index'] = df.facility_id.apply(lambda x : facilities.id.index(x))
        df['dpoint_index'] = df.dpoint_id.apply(lambda x : dpoints.id.index(x))
        self.compatibility = df[['facility_index','dpoint_index','compatibility']].values.tolist()

class InputData:
    '''Main input data processing class'''
    def __init__(self, input_data: Dict[str, Dict[str, List]]):
        self.input = input_data
        self.facilities = None
        self.dpoints = None
        self.costs = None
        self.constraints = None

    def get_facilities(self, required: bool = False, min_usage: bool = False, max_capacity: bool = False, fixed_costs: bool = False) -> Facilities:
        '''Extract and process facility data'''
        items = ['facility_id', 'facility_type', 'group_id', 'min_usage', 'max_capacity', 'cost_of_open']
        df = extract_data(self.input, items)
        if not required:
            df = df[df.facility_type==0].copy()
        if not min_usage:
            df['min_usage'] = np.nan
        if not max_capacity:
            df['max_capacity'] = np.nan
        if not fixed_costs:
            df['cost_of_open'] = np.nan

        self.facilities = Facilities(df)
        return self.facilities

    def get_dpoints(self, add_demand: bool = False) -> DemandPoints:
        '''Extract and process dpoints data'''
        items = ['dpoint_id', 'demand']
        df = extract_data(self.input, items)
        if not add_demand:
            df['demand'] = 1
        self.dpoints = DemandPoints(df)
        return self.dpoints

    def get_costs(self, required: bool = False) -> Costs:
        '''Extract and process costs data'''
        if self.facilities is None:
            raise ValueError('Must call get_facilities() before get_costs()')
            
        items = ['cost_facility_id', 'cost_dpoint_id', 'cost']
        df = extract_data(self.input, items)
        df = pd.pivot(df, index='facility_id', columns='dpoint_id', values='cost')
        if not required:
            df = df.loc[self.facilities.id].copy()
        self.costs = Costs(df)
        return self.costs

    def get_constraints(self, constraint_ids: List[str], required: bool = False) -> Constraints:
        '''Extract and process constraint data'''
        if self.facilities is None or self.dpoints is None:
            raise ValueError('Must call get_facilities() and get_dpoints() before get_constraints()')
            
        self.constraints = Constraints()
    
        if 'compatibility' in constraint_ids:
            items = ['compatibility_facility_id', 'compatibility_dpoint_id', 'compatibility']
            df = extract_data(self.input, items)
            self.constraints.add_compatibility_constraint(df, self.facilities, self.dpoints, required)
        return self.constraints


class LocationAllocation: 
    '''Main optimization class'''
    def __init__(self, facilities: Facilities, dpoints: DemandPoints, costs: Costs, constraints: Optional[Constraints] = None, optimization_strategy: str = 'minimize_total_cost'):
        self.facilities = facilities
        self.dpoints = dpoints
        self.costs = costs
        self.constraints = constraints
        self.optimization_strategy = optimization_strategy

        self.m = len(facilities.index)
        self.n = len(dpoints.index)

        self.solver = None
        self.x = None
        self.y = None
        self.z = None
        self.coverage_matrix = None
        self.result = None
        self.verbose = False

    def _build_coverage_matrix(self, coverage_radius):
        '''Build binary matrix indicating which facilities can cover which demand points'''
        coverage = np.zeros((self.m, self.n), dtype=bool)
        for i in range(self.m):
            for j in range(self.n):
                if self.costs.c[i][j] <= coverage_radius:
                    coverage[i][j] = True
        return coverage

    # -------------------------- #
    # --- Decision Variables --- #
    # -------------------------- #

    def create_decision_variables(self):
        '''Create decision variables based on optimization strategy'''

        # x[i] = 1 if facility i is open, 0 otherwise
        self.x = [self.solver.BoolVar(f'x_{i}') for i in range(self.m)]

        if self.optimization_strategy == 'maximize_coverage':
            # y[i] = 1 if dpoint i is covered, 0 otherwise
            self.y = [self.solver.BoolVar(f'y_{j}') for j in range(self.n)]
            
        else:
            # y[i][j] = 1 if facility i serves dpoint j, 0 otherwise
            self.y = [[self.solver.NumVar(0, 1, f'y_{i}_{j}') for j in range(self.n)] for i in range(self.m)]
    
            if self.optimization_strategy == 'minimize_max_cost':
                # z = maximum distance to be minimized
                self.z = self.solver.NumVar(0, self.solver.infinity(), 'z') 

    # ----------------- #
    # --- Objective --- #
    # ----------------- #

    def build_objective_function(self, add_fixed_costs: bool = False):
        '''Build objective function based on optimization strategy'''
        objective = self.solver.Objective()
        
        if self.optimization_strategy == 'minimize_total_cost':
            # Minimize total (average) costs
            for i in range(self.m):
                for j in range(self.n):
                    objective.SetCoefficient(self.y[i][j], self.dpoints.demand[j] * self.costs.c[i][j])
            
            if add_fixed_costs:
                # Add costs of opening facilities
                for i in range(self.m):
                    objective.SetCoefficient(self.x[i], self.facilities.cost_of_open[i])
            
            objective.SetMinimization()
            
        elif self.optimization_strategy == 'minimize_max_cost':
            # Minimize maximum costs
            objective.SetCoefficient(self.z, 1)
            
            if add_fixed_costs:
                # Add costs of opening facilities
                for i in range(self.m):
                    objective.SetCoefficient(self.x[i], self.facilities.cost_of_open[i])
            
            objective.SetMinimization()

        elif self.optimization_strategy == 'maximize_coverage':
            # Maximize total coverage
            for j in range(self.n):
                objective.SetCoefficient(self.y[j], self.dpoints.demand[j])
            
            if add_fixed_costs:
                # Subtract costs of opening facilities
                for i in range(self.m):
                    objective.SetCoefficient(self.x[i], -self.facilities.cost_of_open[i])
            
            objective.SetMaximization()

        else:
            raise ValueError(f"Invalid optimization strategy: {self.optimization_strategy}")

    # ------------------- #
    # --- Constraints --- #
    # ------------------- #
    
    def add_service_constraints(self):
        '''Add constraints for dpoint service requirements'''
        if self.optimization_strategy == 'maximize_coverage':
            # Demand point j can only be covered if at least one covering facility is selected
            for j in range(self.n):
                covering_facilities = [self.x[i] for i in range(self.m) if self.coverage_matrix[i][j]]
                constraint = self.solver.Constraint(-self.solver.infinity(), 0)
                constraint.SetCoefficient(self.y[j], 1)
                for var in covering_facilities:
                    constraint.SetCoefficient(var, -1)
                
        else:
            # Each demand point must be assigned to at least one facility: sum_i y_ij == 1 for all j
            for j in range(self.n):
                constraint = self.solver.Constraint(1, 1)
                for i in range(self.m):
                    constraint.SetCoefficient(self.y[i][j], 1)

            # Demand points can only be assigned to open facilities: y_ij <= x_i for all i, j
            for i in range(self.m):
                for j in range(self.n):
                    constraint = self.solver.Constraint(-self.solver.infinity(), 0)
                    constraint.SetCoefficient(self.y[i][j], 1)
                    constraint.SetCoefficient(self.x[i], -1)
    
            if self.optimization_strategy == 'minimize_max_cost':
                # Ensure that the (weighted) distance for each demand point is within the maximum distance z
                for j in range(self.n):
                    constraint = self.solver.Constraint(-self.solver.infinity(), 0)
                    for i in range(self.m):
                        constraint.SetCoefficient(self.y[i][j], self.dpoints.demand[j] * self.costs.c[i][j])
                    constraint.SetCoefficient(self.z, -1)

    def add_facility_limit_constraints(self, l: int):
        '''Add constraints to limit the number of open facilities''' 
        constraint = self.solver.Constraint(-self.solver.infinity(), l)
        for i in range(self.m):
            constraint.SetCoefficient(self.x[i], 1)

    def add_group_limit_constraints(self, l: int):
        '''Add constraints to limit the number of open facilities per group''' 
        for group in np.unique(self.facilities.group_id):
            constraint = self.solver.Constraint(-self.solver.infinity(), l)
            for i in range(self.m):
                if self.facilities.group_id[i] == group:
                    constraint.SetCoefficient(self.x[i], 1)

    def add_capacity_constraints(self, min_usage: bool, max_capacity: bool):
        '''Add constraints to limit the capacity of each facility''' 
        for i in range(self.m):
            if max_capacity and not np.isnan(self.facilities.max_capacity[i]):
                # capacity <= max_capacity[i] * x[i]
                constraint = self.solver.Constraint(-self.solver.infinity(), 0)
                for j in range(self.n):
                    constraint.SetCoefficient(self.y[i][j], self.dpoints.demand[j])
                constraint.SetCoefficient(self.x[i], -self.facilities.max_capacity[i])
                
            if min_usage and not np.isnan(self.facilities.min_usage[i]):
                # capacity >= min_usage[i] * x[i]
                constraint = self.solver.Constraint(0, self.solver.infinity())
                for j in range(self.n):
                    constraint.SetCoefficient(self.y[i][j], self.dpoints.demand[j])
                constraint.SetCoefficient(self.x[i], -self.facilities.min_usage[i]) 

    def add_required_facilities_constraints(self):
        '''Fix variable values to force required facilities''' 
        required_indices = [i for i in range(self.m) if self.facilities.type[i] == 1]
        for i in required_indices:
            self.x[i].SetLb(1)

    def add_compatibility_constraints(self):
        '''Fix variable values to force facility-client relationships'''
        for i, j, c in self.constraints.compatibility:
            if c >= 0.5:
                self.y[i][j].SetLb(1)  # Required assignment
            else:
                self.y[i][j].SetUb(0)  # Forbidden assignment
    
    def add_budget_constraint(self, budget_limit: float):
        '''Add budget constraint to limit total cost of opening facilities'''
        constraint = self.solver.Constraint(-self.solver.infinity(), budget_limit)
        for i in range(self.m):
            constraint.SetCoefficient(self.x[i], self.facilities.cost_of_open[i])


    # -------------- #            
    # --- Solver --- #
    # -------------- #
    
    def solve(self, time_limit: float, relative_gap: float, enable_output: bool) -> int:
        '''Solve the optimization model'''
        self.solver.SetTimeLimit(int(time_limit * 1000))  # Convert to milliseconds
        solverParams = pywraplp.MPSolverParameters()
        solverParams.SetDoubleParam(solverParams.RELATIVE_MIP_GAP, relative_gap)

        if enable_output:
            self.solver.EnableOutput()

        try:
            status = self.solver.Solve(solverParams)
            return status
        except Exception as e:
            raise RuntimeError(f"Solver failed: {str(e)}")


    # ---------------------------------- #
    # --- Extract Solution & Metrics --- #
    # ---------------------------------- #

    def _calculate_gap(self, status: int) -> float:
        '''Calculate optimality gap'''
        try:
            if status == pywraplp.Solver.OPTIMAL:
                return 0.0
            elif status == pywraplp.Solver.FEASIBLE:
                objective_value = self.solver.Objective().Value()
                if hasattr(self.solver, 'BestObjectiveBound'):
                    best_bound = self.solver.BestObjectiveBound()
                    if objective_value != 0:
                        return abs(objective_value - best_bound) / abs(objective_value)
                    else:
                        return abs(objective_value - best_bound) 
                else:
                    return np.nan
            else:
                return float('inf')  # No feasible solution
        except Exception:
            return np.nan

    def _get_opened_facilities(self, tol: float = 0.5) -> List[bool]:
        '''Get list of open facilities'''
        facility_is_open = [self.x[i].solution_value() > tol for i in range(self.m)]

        if self.verbose:
            print(facility_is_open)
        return facility_is_open
        
    def _get_assignments(self, tol: float) -> pd.DataFrame:
        '''Get list of assigned demands'''
        facility_for_dpoint = []
        if self.optimization_strategy == 'maximize_coverage':
            for j in range(self.n):
                if self.y[j].solution_value() > 0.5:
                    covering_facility = [i for i in range(self.m) if self.coverage_matrix[i,j] & self.facility_is_open[i]]
                    for c in covering_facility:
                        facility_for_dpoint.append([self.facilities.id[c], self.dpoints.id[j], self.dpoints.demand[j]])
        else:
            for j in range(self.n):
                for i in range(self.m):
                    if self.y[i][j].solution_value() > tol:
                        d = self.dpoints.demand[j] if tol == 0.5 else self.y[i][j].solution_value() * self.dpoints.demand[j] 
                        facility_for_dpoint.append([self.facilities.id[i], self.dpoints.id[j], d])
        return facility_for_dpoint

    def _get_status_string(self, status: int) -> str:
        '''Convert solver status to string'''
        if status == pywraplp.Solver.OPTIMAL:
            return "OPTIMAL"
        elif status == pywraplp.Solver.FEASIBLE:
            return "FEASIBLE"
        elif status == pywraplp.Solver.INFEASIBLE:
            return "INFEASIBLE"
        elif status == pywraplp.Solver.UNBOUNDED:
            return "UNBOUNDED"
        elif status == pywraplp.Solver.ABNORMAL:
            return "ABNORMAL"
        elif status == pywraplp.Solver.NOT_SOLVED:
            return "NOT_SOLVED"
        else:
            return "UNKNOWN"

    def extract_solution(self, status: int, tol: float) -> pd.DataFrame:
        '''Extract solution from optimization result'''
        try:
            if status == pywraplp.Solver.OPTIMAL or status == pywraplp.Solver.FEASIBLE:
                self.facility_is_open = self._get_opened_facilities(tol)
                self.facility_for_dpoint = self._get_assignments(tol)
                
                allocations = pd.DataFrame(self.facility_for_dpoint, columns=['facility_id','dpoint_id','demand'])
                for col in ['objective_value', 'gap', 'solving_time', 'termination_reason', 'stats']:
                    allocations[col] = None
        
                open_facilities = [self.facilities.id[i] for i in range(self.m) if self.facility_is_open[i]]
                total_demand = sum(self.dpoints.demand)
                total_covered_demand = allocations.groupby(['dpoint_id'])['demand'].mean().sum() if self.optimization_strategy == 'maximize_coverage' else allocations.demand.sum() 
                total_opened_capacity = sum(self.facilities.max_capacity[i] for i in range(self.m) if self.facility_is_open[i])

                stats = {
                    'open_facilities': open_facilities,
                    'total_demand': total_demand,
                    'total_covered_demand': np.round(total_covered_demand, 3),
                    'coverage_percentage': np.round((total_covered_demand / total_demand) * 100, 3),
                    'total_opened_capacity': total_opened_capacity,
                    'capacity_utilization': np.round((total_demand / total_opened_capacity) * 100, 3) if total_opened_capacity > 0 else np.nan
                }
                stats = str({k: v for k, v in stats.items() if k != 'open_facilities' and not np.isnan(v)})
                
                if len(allocations) > 0:
                    allocations.loc[0,'objective_value'] = self.solver.Objective().Value()
                    allocations.loc[0,'gap'] = self._calculate_gap(status)
                    allocations.loc[0,'solving_time'] = self.solver.wall_time() / 1000.0  
                    allocations.loc[0,'termination_reason'] = self._get_status_string(status)
                    allocations.loc[0,'stats'] = stats
            else:
                # No feasible solution found
                allocations = pd.DataFrame(columns = ['facility_id','dpoint_id','demand', 'objective_value', 'gap', 'solving_time', 'termination_reason', 'stats'])
                if len(self.dpoints.id) > 0:
                    allocations = pd.DataFrame({'dpoint_id': self.dpoints.id})
                    for col in ['facility_id', 'demand', 'objective_value', 'gap', 'solving_time', 'termination_reason', 'stats']:
                        allocations[col] = None
                allocations.loc[0,'gap'] = self._calculate_gap(status)
                allocations.loc[0,'solving_time'] = self.solver.wall_time() / 1000.0  
                allocations.loc[0,'termination_reason'] = self._get_status_string(status)

        except Exception as e:
            allocations = pd.DataFrame(columns = ['facility_id','dpoint_id','demand', 'objective_value', 'gap', 'solving_time', 'termination_reason', 'stats']
            ).astype({
                'facility_id': 'string',
                'dpoint_id': 'string',
                'demand': 'float64',
                'objective_value': 'float64',
                'gap': 'float64',
                'solving_time': 'float64',
                'termination_reason': 'string',
                'stats': 'string'
            })
            allocations.dpoint_id = self.dpoints.id
            allocations.loc[0,'solving_time'] = np.nan
            allocations.loc[0,'termination_reason'] = f"ERROR: {str(e)}"

        return allocations


    # --------------------------- #
    # --- Location Allocation --- #
    # --------------------------- #

    def run(self, 
              max_limit,
              max_group_limit,
              min_usage,
              max_capacity,
              required_facilities,
              compatibility,
              add_fixed_costs,
              coverage_radius,
              budget_constraint,
              time_limit,
              relative_gap,
              verbose
             ):

        self.verbose = verbose

        if self.optimization_strategy == 'maximize_coverage':          
            self.coverage_matrix = self._build_coverage_matrix(coverage_radius)
            if not self.coverage_matrix.any():
                raise ValueError(f'Facilities cannot cover any demand point under the specified coverage radius: {coverage_radius}. Please, increase the radius accordingly.')
        
        ## Optimization Model
        self.solver = pywraplp.Solver('LocationAllocation', pywraplp.Solver.CBC_MIXED_INTEGER_PROGRAMMING)
        if not self.solver:
            raise RuntimeError('CBC_MIXED_INTEGER_PROGRAMMING solver not available.')
            
        self.create_decision_variables()
        self.build_objective_function(add_fixed_costs)
        self.add_service_constraints()
        if required_facilities:
            self.add_required_facilities_constraints()
        if compatibility:
            self.add_compatibility_constraints()
        if max_limit:
            self.add_facility_limit_constraints(max_limit)
        if max_group_limit:
            self.add_group_limit_constraints(max_group_limit)
        if budget_constraint:
            self.add_budget_constraint(budget_constraint)
        if self.optimization_strategy != 'maximize_coverage':  
            if min_usage | max_capacity:
                self.add_capacity_constraints(min_usage, max_capacity)

        ## Solve
        self.result = self.solve(time_limit, relative_gap, verbose)

        return self.result


# ------------ #
# --- Main --- #
# ------------ #

def main(
    optimization_strategy,
    facility_id,
    facility_type,
    facility_group_id,
    facility_min_usage,
    facility_max_capacity,
    facility_cost_of_open,
    dpoint_id,
    dpoint_demand,
    cost_facility_id,
    cost_dpoint_id,
    cost,
    compatibility_facility_id,
    compatibility_dpoint_id,
    compatibility_type,
    required = False, 
    max_limit = None,
    max_group_limit = None,
    min_usage = False,
    max_capacity = False,
    compatibility = False,
    add_demand = False,
    add_fixed_costs = False,
    coverage_radius = None,
    budget_constraint = None,
    time_limit = None,
    relative_gap = None,
    verbose = False
):

    try:

        input = dict(
            facility_id = {'facility_id':facility_id},
            facility_type = {'facility_type':facility_type},
            group_id = {'group_id':facility_group_id},
            min_usage = {'min_usage':facility_min_usage},
            max_capacity = {'max_capacity':facility_max_capacity},
            cost_of_open = {'cost_of_open':facility_cost_of_open},
            dpoint_id = {'dpoint_id':dpoint_id},
            demand = {'demand':dpoint_demand},
            cost_facility_id = {'facility_id':cost_facility_id},
            cost_dpoint_id = {'dpoint_id':cost_dpoint_id},
            cost = {'cost':cost},
            compatibility_facility_id = {'facility_id':compatibility_facility_id},
            compatibility_dpoint_id = {'dpoint_id':compatibility_dpoint_id},
            compatibility = {'compatibility':compatibility_type},
        )

        data = InputData(input)
        
        fixed_costs = True if (budget_constraint is not None or add_fixed_costs) else False

        facilities = data.get_facilities(required, min_usage, max_capacity, fixed_costs)
        dpoints = data.get_dpoints(add_demand)
        costs = data.get_costs(required)
        constraints = None

        constraint_id = []
        if compatibility:
            constraint_id.append('compatibility')
        if constraint_id:
            constraints = data.get_constraints(constraint_id, required)

        localoc = LocationAllocation(facilities, dpoints, costs, constraints, optimization_strategy)
        result = localoc.run(max_limit, max_group_limit, min_usage, max_capacity, required, compatibility, add_fixed_costs, coverage_radius, budget_constraint, time_limit, relative_gap, verbose)
        tol = 1e-6 if add_demand else 0.5
        allocations = localoc.extract_solution(result, tol)

        return allocations.to_dict(orient='records')

    except Exception as e:
        allocations = pd.DataFrame(columns = ['facility_id','dpoint_id','demand', 'objective_value', 'gap', 'solving_time', 'termination_reason', 'stats']
        ).astype({
            'facility_id': 'string',
            'dpoint_id': 'string',
            'demand': 'float64',
            'objective_value': 'float64',
            'gap': 'float64',
            'solving_time': 'float64',
            'termination_reason': 'string',
            'stats': 'string'
        })
        allocations.dpoint_id = self.dpoints.id
        allocations.loc[0,'solving_time'] = np.nan
        allocations.loc[0,'termination_reason'] = f"ERROR: {str(e)}"
        return allocations.to_dict(orient='records')

""";