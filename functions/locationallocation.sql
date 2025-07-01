CREATE OR REPLACE FUNCTION
    @@workflows_temp@@.`LOCATION_ALLOCATION`
(    
    optimization_strategy STRING,
    facility_id ARRAY<STRING>,
    facility_type ARRAY<INT64>,
    facility_group_id ARRAY<STRING>,
    facility_min_capacity ARRAY<FLOAT64>,
    facility_max_capacity ARRAY<FLOAT64>,
    facility_cost_of_open ARRAY<FLOAT64>,
    customer_id ARRAY<STRING>,
    customer_demand ARRAY<FLOAT64>,
    cost_facility_id ARRAY<STRING>,
    cost_customer_id ARRAY<STRING>,
    cost ARRAY<FLOAT64>,
    compatibility_facility_id ARRAY<STRING>,
    compatibility_customer_id ARRAY<STRING>,
    compatibility_type ARRAY<INT64>,
    required BOOLEAN, 
    max_limit INT64,
    max_group_limit INT64,
    min_capacity BOOLEAN,
    max_capacity BOOLEAN,
    compatibility BOOLEAN,
    add_demand BOOLEAN,
    add_fixed_costs BOOLEAN,
    coverage_radius FLOAT64,
    time_limit INT64,
    relative_gap INT64,
    verbose BOOLEAN
)
RETURNS ARRAY<STRUCT<facility_id STRING, customer_id STRING, demand FLOAT64, objective_value FLOAT64, gap FLOAT64, solving_time FLOAT64, termination_reason STRING, stats STRING>>

LANGUAGE python
OPTIONS (
    entry_point='main',
    runtime_version='python-3.11',
    max_batching_rows=1,
    packages=['ortools==9.9.3963','pandas==2.2.3','numpy==1.23.5']
)
AS r"""
import math
from datetime import timedelta
import random
import pandas as pd
import numpy as np
from ortools.math_opt.python import mathopt
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
        self.min_capacity = df['min_capacity'].tolist()
        self.max_capacity = df['max_capacity'].tolist()
        self.cost_of_open = df['cost_of_open'].tolist()

class Customers:
    '''Represent customer data'''
    def __init__(self, df: pd.DataFrame):
        df = df.sort_values('customer_id').reset_index(drop=True).copy()
        self.index = df.index.tolist()
        self.id = df['customer_id'].tolist()
        self.demand = df['demand'].tolist()

class Costs:
    '''Represent cost matrix'''
    def __init__(self, df: pd.DataFrame):
        self.facility_id = df.index.tolist()
        self.customer_id = df.columns.tolist()
        self.c = df.values.tolist()

class Constraints:
    '''Represent constraint-specific data'''
    def __init__(self):
        self.compatibility = None

    def add_compatibility_constraint(self, df: pd.DataFrame, facilities: Facilities, customers: Customers, required: bool = False):
        '''Add compatibility constraints between facilities and customers'''
        if not required:
            df = df[df.facility_id.isin(facilities.id)].copy()
        df['facility_index'] = df.facility_id.apply(lambda x : facilities.id.index(x))
        df['customer_index'] = df.customer_id.apply(lambda x : customers.id.index(x))
        self.compatibility = df[['facility_index','customer_index','compatibility']].values.tolist()

class InputData:
    '''Main input data processing class'''
    def __init__(self, input_data: Dict[str, Dict[str, List]]):
        self.input = input_data
        self.facilities = None
        self.customers = None
        self.costs = None
        self.constraints = None

    def get_facilities(self, required: bool = False, min_capacity: bool = False, max_capacity: bool = False, add_fixed_costs: bool = False) -> Facilities:
        '''Extract and process facility data'''
        items = ['facility_id', 'facility_type', 'group_id', 'min_capacity', 'max_capacity', 'cost_of_open']
        df = extract_data(self.input, items)
        if not required:
            df = df[df.facility_type==0].copy()
        if not min_capacity:
            df['min_capacity'] = np.nan
        if not max_capacity:
            df['max_capacity'] = np.nan
        if not add_fixed_costs:
            df['add_fixed_costs'] = np.nan

        self.facilities = Facilities(df)
        return self.facilities

    def get_customers(self, add_demand: bool = False) -> Customers:
        '''Extract and process customers data'''
        items = ['customer_id', 'demand']
        df = extract_data(self.input, items)
        if not add_demand:
            df['demand'] = 1
        self.customers = Customers(df)
        return self.customers

    def get_costs(self, required: bool = False) -> Costs:
        '''Extract and process costs data'''
        if self.facilities is None:
            raise ValueError('Must call get_facilities() before get_costs()')
            
        items = ['cost_facility_id', 'cost_customer_id', 'cost']
        df = extract_data(self.input, items)
        df = pd.pivot(df, index='facility_id', columns='customer_id', values='cost')
        if not required:
            df = df.loc[self.facilities.id].copy()
        self.costs = Costs(df)
        return self.costs

    def get_constraints(self, constraint_ids: List[str], required: bool = False) -> Constraints:
        '''Extract and process constraint data'''
        if self.facilities is None or self.customers is None:
            raise ValueError('Must call get_facilities() and get_customers() before get_constraints()')
            
        self.constraints = Constraints()
    
        if 'compatibility' in constraint_ids:
            items = ['compatibility_facility_id', 'compatibility_customer_id', 'compatibility']
            df = extract_data(self.input, items)
            self.constraints.add_compatibility_constraint(df, self.facilities, self.customers, required)
        return self.constraints


class LocationAllocation: 
    '''Main optimization class'''
    def __init__(self, facilities: Facilities, customers: Customers, costs: Costs, constraints: Optional[Constraints] = None, optimization_strategy: str = 'minimize_total_cost'):
        self.facilities = facilities
        self.customers = customers
        self.costs = costs
        self.constraints = constraints
        self.optimization_strategy = optimization_strategy

        self.m = len(facilities.index)
        self.n = len(customers.index)

        self.model = None
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
        self.x = [self.model.add_binary_variable() for i in range(self.m)]

        if self.optimization_strategy == 'maximize_coverage':
            # y[i] = 1 if customer i is covered, 0 otherwise
            self.y = [self.model.add_binary_variable() for j in range(self.n)]
            
        else:
            # y[i][j] = 1 if facility i serves customer j, 0 otherwise
            self.y = [[self.model.add_variable(lb=0, ub=1) for j in range(self.n)] for i in range(self.m)]
    
            if self.optimization_strategy == 'minimize_max_cost':
                # z = maximum distance to be minimized
                self.z = self.model.add_variable(lb=0) 

    # ----------------- #
    # --- Objective --- #
    # ----------------- #

    def _minimize_total_cost(self, objective: mathopt.LinearExpression):
        '''Expression to minimize total (average) costs'''
        for i in range(self.m):
            for j in range(self.n):
                objective += self.customers.demand[j] * self.costs.c[i][j] * self.y[i][j]
        return objective

    def _minimize_max_cost(self, objective: mathopt.LinearExpression):
        '''Expression to minimize maximum costs'''
        objective += self.z
        return objective

    def _maximize_coverage(self, objective: mathopt.LinearExpression):
        '''Expression to maximize total coverage'''
        for j in range(self.n):
            objective += self.customers.demand[j] * self.y[j]
        return objective
        
    def _add_fixed_costs(self, objective: mathopt.LinearExpression):
        '''Expression to add costs of opening facilities'''
        for i in range(self.m):
            objective += self.facilities.cost_of_open[i] * self.x[i]
        return objective

    def build_objective_function(self, add_fixed_costs: bool = False) -> mathopt.LinearExpression:
        '''Build objective function based on optimization strategy'''
        objective = mathopt.LinearExpression()
        
        if add_fixed_costs: 
            objective = self._add_fixed_costs(objective)
            
        if self.optimization_strategy == 'minimize_total_cost':
            objective = self._minimize_total_cost(objective)
            self.model.minimize(objective)
            
        elif self.optimization_strategy == 'minimize_max_cost':
            objective = self._minimize_max_cost(objective)
            self.model.minimize(objective)

        elif self.optimization_strategy == 'maximize_coverage':
            objective = self._maximize_coverage(objective)
            self.model.maximize(objective)

        return objective

    # ------------------- #
    # --- Constraints --- #
    # ------------------- #
    
    def add_service_constraints(self):
        '''Add constraints for customer service requirements'''
        if self.optimization_strategy == 'maximize_coverage':
            # Demand point j can only be covered if at least one covering facility is selected
            for j in range(self.n):
                covering_facilities = sum(self.x[i] for i in range(self.m) if self.coverage_matrix[i][j])
                self.model.add_linear_constraint(self.y[j] <= covering_facilities)
                
        else:
            # Each demand point must be assigned to at least one facility: sum_i y_ij >= 1 for all j
            for j in range(self.n):
                assigned = sum(self.y[i][j] for i in range(self.m))
                self.model.add_linear_constraint(assigned == 1)

            # Demand points can only be assigned to open facilities: y_ij <= x_i for all i, j
            for i in range(self.m):
                for j in range(self.n):
                    self.model.add_linear_constraint(self.y[i][j] <= self.x[i])
    
            if self.optimization_strategy == 'minimize_max_cost':
                # Ensure that the (weighted) distance for each demand point is within the maximum distance z: dj * sum c_ij * y_ij <= z for all j 
                for j in range(self.n):
                    dist = sum(self.customers.demand[j] * self.costs.c[i][j] * self.y[i][j] for i in range(self.m))
                    self.model.add_linear_constraint(dist <= self.z)

    def add_facility_limit_constraints(self, l: int):
        '''Add constraints to limit the number of open facilities''' 
        self.model.add_linear_constraint(mathopt.fast_sum(self.x) <= l)

    def add_group_limit_constraints(self, l: int):
        '''Add constraints to limit the number of open facilities per group''' 
        for group in np.unique(self.facilities.group_id):
            grouped_facilities = sum(self.x[i] for i in range(self.m) if self.facilities.group_id[i] == group)
            self.model.add_linear_constraint(grouped_facilities <= l)

    def add_capacity_constraints(self, min_capacity: bool, max_capacity: bool):
        '''Add constraints to limit the capacity of each facility''' 
        for i in range(self.m):
            capacity = sum(self.customers.demand[j] * self.y[i][j] for j in range(self.n))
            if max_capacity:
                self.model.add_linear_constraint(capacity <= self.facilities.max_capacity[i] * self.x[i]) 
            if min_capacity:
                self.model.add_linear_constraint(capacity >= self.facilities.min_capacity[i] * self.x[i]) 

    def add_required_facilities_constraints(self):
        '''Add constraints to force required facilities''' 
        required_indices = [i for i in range(self.m) if self.facilities.type[i] == 1]
        for i in required_indices:
            self.model.add_linear_constraint(self.x[i] == 1)

    def add_compatibility_constraints(self):
        '''Add constraints to force facility-client relationships'''
        for i, j, c in self.constraints.compatibility:
            self.model.add_linear_constraint(self.y[i][j] == c)

    # -------------- #            
    # --- Solver --- #
    # -------------- #
    
    def solve(self, time_limit: Optional[float], relative_gap: Optional[float], enable_output: bool) -> mathopt.SolveResult:
        '''Solve the optimization model'''
        params = mathopt.SolveParameters(
            enable_output = enable_output,
            time_limit = timedelta(seconds=time_limit) if time_limit else None,
            relative_gap_tolerance = relative_gap if relative_gap else None
        )
        try:
            result = mathopt.solve(self.model, mathopt.SolverType.GSCIP, params=params)
            return result
        except Exception as e:
            raise RuntimeError(f"Solver failed: {str(e)}")


    # ---------------------------------- #
    # --- Extract Solution & Metrics --- #
    # ---------------------------------- #

    def _get_opened_facilities(self, var_values: Dict, tol: float = 0.5) -> List[bool]:
        '''Get list of open facilities'''
        facility_is_open = [var_values[self.x[i]] > tol for i in range(self.m)]
        if self.verbose:
            print(facility_is_open)
        return facility_is_open
        
    def _get_assignments(self, var_values: Dict, tol: float) -> pd.DataFrame:
        '''Get list of assigned demands'''
        facility_for_customer = []
        if self.optimization_strategy == 'maximize_coverage':
            for j in range(self.n):
                if var_values[self.y[j]] > 0.5:
                    covering_facility = [i for i in range(self.m) if self.coverage_matrix[i,j] & self.facility_is_open[i]]
                    for c in covering_facility:
                        facility_for_customer.append([self.facilities.id[c], self.customers.id[j], self.customers.demand[j]])
        else:
            for j in range(self.n):
                for i in range(self.m):
                    if var_values[self.y[i][j]] > tol:
                        d = self.customers.demand[j] if tol == 0.5 else var_values[self.y[i][j]] * self.customers.demand[j] 
                        facility_for_customer.append([self.facilities.id[i], self.customers.id[j], d])
        return facility_for_customer

    def extract_solution(self, result: mathopt.SolveResult, tol: float) -> pd.DataFrame:
        '''Extract solution from optimization result'''
        try:
            var_values = result.variable_values()
            self.facility_is_open = self._get_opened_facilities(var_values)
            self.facility_for_customer = self._get_assignments(var_values, tol)
            
            allocations = pd.DataFrame(self.facility_for_customer, columns=['facility_id','customer_id','demand'])
            for col in ['objective_value', 'gap', 'solving_time', 'termination_reason', 'stats']:
                allocations[col] = None
    
            open_facilities = [self.facilities.id[i] for i in range(self.m) if self.facility_is_open[i]]
            total_demand = sum(self.customers.demand)
            total_covered_demand = allocations.groupby(['customer_id'])['demand'].mean().sum() if self.optimization_strategy == 'maximize_coverage' else allocations.demand.sum() 
            total_opened_capacity = sum(self.facilities.max_capacity[i] for i in range(self.m) if self.facility_is_open[i])
            stats = {
                'open_facilities': open_facilities,
                'total_demand': total_demand,
                'total_covered_demand': total_covered_demand,
                'coverage_percentage': (total_covered_demand / total_demand) * 100,
                'total_opened_capacity': total_opened_capacity,
                'capacity_utilization': (total_demand / total_opened_capacity) * 100 
            }
            stats = str({k: v for k, v in stats.items() if k != 'open_facilities' and not np.isnan(v)})
            
            allocations.loc[0,'objective_value'] = result.objective_value()
            allocations.loc[0,'gap'] = np.abs(result.dual_bound() - result.objective_value()) / result.objective_value()
            allocations.loc[0,'solving_time'] = result.solve_stats.solve_time.total_seconds()
            allocations.loc[0,'termination_reason'] = result.termination.reason._name_
            allocations.loc[0,'stats'] = stats

        except Exception as e:
            allocations = pd.DataFrame(columns = ['facility_id','customer_id','demand', 'objective_value', 'gap', 'solving_time', 'termination_reason', 'stats']
            ).astype({
                'facility_id': 'string',
                'customer_id': 'string',
                'demand': 'float64',
                'objective_value': 'float64',
                'gap': 'float64',
                'solving_time': 'float64',
                'termination_reason': 'string',
                'stats': 'string'
            })
            allocations.customer_id = self.customers.id
            allocations.loc[0,'solving_time'] = result.solve_stats.solve_time.total_seconds()
            allocations.loc[0,'termination_reason'] = result.termination.reason._name_

        return allocations

    # --------------------------- #
    # --- Location Allocation --- #
    # --------------------------- #

    def run(self, 
              max_limit,
              max_group_limit,
              min_capacity,
              max_capacity,
              required_facilities,
              compatibility,
              add_fixed_costs,
              coverage_radius,
              time_limit,
              relative_gap,
              verbose
             ):

        self.verbose = verbose

        if self.optimization_strategy == 'maximize_coverage':          
            self.coverage_matrix = self._build_coverage_matrix(coverage_radius)
        
        ## Optimization Model
        self.model = mathopt.Model()
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
        if self.optimization_strategy != 'maximize_coverage':  
            if min_capacity | max_capacity:
                self.add_capacity_constraints(min_capacity, max_capacity)

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
    facility_min_capacity,
    facility_max_capacity,
    facility_cost_of_open,
    customer_id,
    customer_demand,
    cost_facility_id,
    cost_customer_id,
    cost,
    compatibility_facility_id,
    compatibility_customer_id,
    compatibility_type,
    required = False, 
    max_limit = False,
    max_group_limit = False,
    min_capacity = False,
    max_capacity = False,
    compatibility = False,
    add_demand = False,
    add_fixed_costs = False,
    coverage_radius = None,
    time_limit = None,
    relative_gap = None,
    verbose = False
):

    input = dict(
        facility_id = {'facility_id':facility_id},
        facility_type = {'facility_type':facility_type},
        group_id = {'group_id':facility_group_id},
        min_capacity = {'min_capacity':facility_min_capacity},
        max_capacity = {'max_capacity':facility_max_capacity},
        cost_of_open = {'cost_of_open':facility_cost_of_open},
        customer_id = {'customer_id':customer_id},
        demand = {'demand':customer_demand},
        cost_facility_id = {'facility_id':cost_facility_id},
        cost_customer_id = {'customer_id':cost_customer_id},
        cost = {'cost':cost},
        compatibility_facility_id = {'facility_id':compatibility_facility_id},
        compatibility_customer_id = {'customer_id':compatibility_customer_id},
        compatibility = {'compatibility':compatibility_type},
    )

    data = InputData(input)
    
    facilities = data.get_facilities(required, min_capacity, max_capacity, add_fixed_costs)
    customers = data.get_customers(add_demand)
    costs = data.get_costs(required)
    constraints = None

    constraint_id = []
    if compatibility:
        constraint_id.append('compatibility')
    constraints = data.get_constraints(constraint_id, required)

    localoc = LocationAllocation(facilities, customers, costs, constraints, optimization_strategy)
    result = localoc.run(max_limit, max_group_limit, min_capacity, max_capacity, required, compatibility, add_fixed_costs, coverage_radius, time_limit, relative_gap, verbose)
    tol = 1e-6 if add_demand else 0.5
    allocations = localoc.extract_solution(result, tol)

    return allocations.to_dict(orient='records')
""";