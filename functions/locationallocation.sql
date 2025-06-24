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
    time_limit INT64,
    relative_gap INT64,
    verbose BOOLEAN
)
RETURNS ARRAY<STRUCT<facility_id STRING, customer_id STRING, demand FLOAT64, objective_value FLOAT64, gap FLOAT64, solving_time FLOAT64, termination_reason STRING>>

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

def extract_data(input, items):
    df = {}
    for item in items:
        df.update(input[item])
    return pd.DataFrame(df)
    
class Facilities:
    def __init__(self, df):
        df = df.sort_values('facility_id').reset_index(drop=True).copy()
        self.index = df.index.tolist()
        self.id = df['facility_id'].tolist()
        self.type = df['facility_type'].tolist()
        self.group_id = df['group_id'].tolist()
        self.min_capacity = df['min_capacity'].tolist()
        self.max_capacity = df['max_capacity'].tolist()
        self.cost_of_open = df['cost_of_open'].tolist()

class Customers:
    def __init__(self, df):
        df = df.sort_values('customer_id').reset_index(drop=True).copy()
        self.index = df.index.tolist()
        self.id = df['customer_id'].tolist()
        self.demand = df['demand'].tolist()

class Costs:
    def __init__(self, df):
        self.facility_id = df.index.tolist()
        self.customer_id = df.columns.tolist()
        self.c = df.values.tolist()

class Constraints:
    def __init__(self):
        pass

    def add_compatibility_constraint(self, df, facilities, customers, required):
        if required:
            pass
        else:
            df = df[df.facility_id.isin(facilities.id)].copy()
        df['facility_index'] = df.facility_id.apply(lambda x : facilities.id.index(x))
        df['customer_index'] = df.customer_id.apply(lambda x : customers.id.index(x))
        self.compatibility = df[['facility_index','customer_index','compatibility']].values.tolist()

class InputData:
    def __init__(self, input):
        self.input = input
        self.facilities = None
        self.customers = None
        self.costs = None
        self.constraints = None

    def get_facilities(self, required=False):
        items = ['facility_id', 'facility_type', 'group_id', 'min_capacity', 'max_capacity', 'cost_of_open']
        df = extract_data(self.input, items)
        if required:
            self.facilities = Facilities(df)
        else:
            self.facilities = Facilities(df[df.facility_type==0])
        return self.facilities

    def get_customers(self):
        items = ['customer_id', 'demand']
        df = extract_data(self.input, items)
        self.customers = Customers(df)
        return self.customers

    # TODO: add run_facilities decorator
    def get_costs(self, required=False):
        items = ['cost_facility_id', 'cost_customer_id', 'cost']
        df = extract_data(self.input, items)
        df = pd.pivot(df, index='facility_id', columns='customer_id', values='cost')
        if required:
            self.costs = Costs(df)    
        else:
            self.costs = Costs(df.loc[self.facilities.id])               
        return self.costs

    # TODO: add run_facilities/run_customers decorator
    def get_constraints(self, constraint_ids, required=False):
        self.constraints = Constraints()
        if 'compatibility' in constraint_ids:
            items = ['compatibility_facility_id', 'compatibility_customer_id', 'compatibility']
            df = extract_data(self.input, items)
            self.constraints.add_compatibility_constraint(df, self.facilities, self.customers, required)
        return self.constraints


class LocationAllocation:    
    def __init__(self, facilities, customers, costs, constraints=None):
        self.facilities = facilities
        self.customers = customers
        self.costs = costs
        self.constraints = constraints

        self.m = len(facilities.index)
        self.n = len(customers.index)

    # --- Decision Variables ---
            
    def decision_variables(self, optimization_strategy, add_demand=False):
        # x[i]: do we open facility i
        self.x = [self.model.add_binary_variable() for i in range(self.m)]
        if add_demand:
            # y[i][j]: how much do we serve customer j from facility i
            self.y = [[self.model.add_variable(lb=0) for j in range(self.n)] for i in range(self.m)]
        else:
            # y[i][j]: do we serve customer j from facility i
            self.y = [[self.model.add_variable(lb=0, ub=1) for j in range(self.n)] for i in range(self.m)]

        if optimization_strategy == 'minimize_max_cost':
            self.z = self.model.add_variable(lb=0) 

    # --- Objective ---

    def _minimize_total_cost(self, total_distance):
        for i in range(self.m):
            for j in range(self.n):
                total_distance += self.costs.c[i][j] * self.y[i][j]
        return total_distance

    def _minimize_max_cost(self, total_distance):
        total_distance += self.z
        return total_distance

    def _add_fixed_costs(self, total_distance):
        for i in range(self.m):
            total_distance += self.facilities.cost_of_open[i] * self.x[i]
        return total_distance

    def objective_function(self, optimization_strategy, add_fixed_costs=False):
        total_distance = mathopt.LinearExpression()
        
        if add_fixed_costs: 
            total_distance = self._add_fixed_costs(total_distance)
            
        if optimization_strategy == 'minimize_total_cost':
            total_distance = self._minimize_total_cost(total_distance)
            self.model.minimize(total_distance)
            
        elif optimization_strategy == 'minimize_max_cost':
            total_distance = self._minimize_max_cost(total_distance)
            self.model.minimize(total_distance)
            
        else:
            pass
            #self.model.maximize(total_distance)
        return total_distance
    
    # --- Constraints ---
    
    def c_served_facilities(self, optimization_strategy, add_demand=False):
        if add_demand:
            #(2) sum_i y_ij >= d_j  for all j    
            for j in range(self.n):
                served_j = mathopt.LinearExpression()
                for i in range(self.m):
                    served_j += self.y[i][j]
                self.model.add_linear_constraint(served_j == self.customers.demand[j])
            #(3) y_ij <= d_j * x_i      for all i, for all j 
            for j in range(self.n):
                for i in range(self.m):
                    self.model.add_linear_constraint(self.y[i][j] <= self.customers.demand[j] * self.x[i]) 
        else:
            #(2) sum_i y_ij >= 1  for all j    
            for j in range(self.n):
                served_j = mathopt.LinearExpression()
                for i in range(self.m):
                    served_j += self.y[i][j]
                self.model.add_linear_constraint(served_j == 1)
            #(3) y_ij <= x_i      for all i, for all j 
            for j in range(self.n):
                for i in range(self.m):
                    self.model.add_linear_constraint(self.y[i][j] <= self.x[i])
                    
        if optimization_strategy == 'minimize_max_cost':
            if add_demand:
                for j in range(self.n):
                    served_j = mathopt.LinearExpression()
                    for i in range(self.m):
                        served_j += self.costs.c[i][j] * self.y[i][j]
                    self.model.add_linear_constraint(served_j * self.customers.demand[j] <= self.z)
            else:
                for j in range(self.n):
                    served_j = mathopt.LinearExpression()
                    for i in range(self.m):
                        served_j += self.costs.c[i][j] * self.y[i][j]
                    self.model.add_linear_constraint(served_j <= self.z)

    def c_limit_num_facilities(self, l):
        self.model.add_linear_constraint(mathopt.fast_sum(self.x) <= l)

    def c_limit_num_facilities_group(self, l, facility_groups):
        for group in np.unique(facility_groups):
            xx = mathopt.LinearExpression()
            for i in range(self.m):
                if facility_groups[i] == group:
                    xx += self.x[i]
            self.model.add_linear_constraint(xx <= l)

    def c_limit_facilities_capacity(self, k, do_max = True):
        for i in range(self.m):
            yy = mathopt.LinearExpression()
            for j in range(self.n):
                yy += self.y[i][j]
            if do_max:
                self.model.add_linear_constraint(yy <= k[i] * self.x[i]) 
            else:
                self.model.add_linear_constraint(yy >= k[i] * self.x[i]) 

    def c_required_facilities(self, required_facilities):
        for i in required_facilities:
            self.model.add_linear_constraint(self.x[i] == 1)

    def c_compatibility(self, compatibility):
        for i, j, c in compatibility:
            self.model.add_linear_constraint(self.y[i][j] == c)

    # --- Solver ---
    
    def solve(self, time_limit, relative_gap, enable_output):
        params = mathopt.SolveParameters(enable_output = enable_output, time_limit = timedelta(seconds=time_limit), relative_gap_tolerance = relative_gap)
        result = mathopt.solve(self.model, mathopt.SolverType.GSCIP, params=params)
        return result

    # --- Extract Solution & Metrics ---

    def extract_solution(self, result, add_demand):
        var_values = result.variable_values()
        facility_is_open = [var_values[self.x[i]] > 0.5 for i in range(self.m)]
        facility_for_customer = []
        if add_demand:
            for j in range(self.n):
                for i in range(self.m):
                    if var_values[self.y[i][j]] > tol:
                        facility_for_customer.append([self.facilities.id[i], self.customers.id[j], var_values[self.y[i][j]]])
        else:
            for j in range(self.n):
                for i in range(self.m):
                    if var_values[self.y[i][j]] > 0.5:
                        facility_for_customer.append([self.facilities.id[i], self.customers.id[j], 1])            
        allocations = pd.DataFrame(facility_for_customer, columns=['facility_id','customer_id','demand'])

        allocations['objective_value'] = None
        allocations['gap'] = None
        allocations['solving_time'] = None
        allocations['termination_reason'] = None
        
        allocations.loc[0,'objective_value'] = result.objective_value()
        allocations.loc[0,'gap'] = np.abs(result.dual_bound() - result.objective_value()) / result.objective_value()
        allocations.loc[0,'solving_time'] = result.solve_stats.solve_time.total_seconds()
        allocations.loc[0,'termination_reason'] = result.termination.reason._name_

        return allocations


    # --- Location Allocation ---
    
    def run(self, 
              optimization_strategy,
              max_limit,
              max_group_limit,
              min_capacity,
              max_capacity,
              required_facilities,
              compatibility,
              add_demand,
              add_fixed_costs,
              time_limit,
              relative_gap,
              verbose
             ):

        ## Define Optimization Model
        self.model = mathopt.Model()
        self.decision_variables(optimization_strategy, add_demand)
        self.objective_function(optimization_strategy, add_fixed_costs)
        self.c_served_facilities(optimization_strategy, add_demand)
        if max_limit:
            self.c_limit_num_facilities(max_limit)
        if max_group_limit:
            self.c_limit_num_facilities_group(max_group_limit, self.facilities.group_id)
        if max_capacity:
            self.c_limit_facilities_capacity(self.facilities.max_capacity, do_max = True)
        if min_capacity:
            self.c_limit_facilities_capacity(self.facilities.min_capacity, do_max = False)
        if required_facilities:
            self.c_required_facilities(np.array(self.facilities.index)[np.array(self.facilities.type) == 1])
        if compatibility:
            self.c_compatibility(self.constraints.compatibility)

        ## Solve
        result = self.solve(time_limit, relative_gap, verbose)
        
        return result


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
    
    facilities = data.get_facilities(required)
    customers = data.get_customers()
    costs = data.get_costs(required)
    constraints = None

    constraint_id = []
    if compatibility:
        constraint_id.append('compatibility')
    constraints = data.get_constraints(constraint_id, required)
    
    localoc = LocationAllocation(facilities, customers, costs, constraints)
    result = localoc.run(optimization_strategy, max_limit, max_group_limit, min_capacity, max_capacity, required, compatibility, add_demand, add_fixed_costs, time_limit, relative_gap, verbose)
    allocations = localoc.extract_solution(result, add_demand)

    return allocations.to_dict(orient='records')


""";