from flask import Flask, request, jsonify
import logging
import os
import time

import geopandas as gpd
import pandas as pd
from h3 import h3
import quadbin as qb 

from territory_balancing import get_functions, TerritoryBalancingProblem

app = Flask(__name__)

logger = logging.getLogger()
logging.basicConfig(format='%(asctime)s %(message)s', datefmt='%Y-%m-%d %I:%M:%S %p',
                    level=logging.INFO)

def parse_request_input(request_json):
    # calls will always contain a single element in this case
    print(len(request_json["calls"]))
    call = request_json["calls"][0]

    input = dict(
        geoid = call[0],
        demand = call[1],
        score = call[2],
        nparts = call[3],
        tolerance = call[4],
        grid_type = call[5]
    )
    
    return input

def solve_territory_balancing(input):
    absolute_start = time.time()

    df = {}
    for item in ['geoid', 'demand', 'score']:
        df.update(input[item])
    df = pd.DataFrame(df)
    print(df.shape)

    df['node'] = df['geoid'].rank(method='dense').astype(int) - 1
    df = df.sort_values("node")

    # Obtain edges
    compute_kring, _, compute_weights = get_functions(input['grid_type'])
    wq = compute_weights(df, compute_kring)

    # We setup the territory balancing problem
    tb = TerritoryBalancingProblem(
        df,
        list(wq.itertuples(index=False, name=None)),         
        grid_type = input['grid_type'], 
        grid_index_column = 'geoid',
        nparts = int(input['nparts']),
        balance_tolerance = input['tolerance'],
        verbose = True)

    # We solve the problem
    solution_found = tb.solve()
    if solution_found:
        output = tb.df.copy()
    else:
        raise Exception("No solution found")

    absolute_end = time.time() - absolute_start
    print("Time of execution: {}".format(absolute_end))

    return output


@app.route("/", methods=['POST'])
def territorybalancing():
    try:
        request_json = request.get_json()
        input = parse_request_input(request_json)
        output = solve_territory_balancing(input)
        replies = [{
            'geoid': output['geoid'].tolist(),
            'cluster': output['cluster'].tolist()
        }]
        return_json = jsonify( { "replies" :  replies} )

    except Exception as e:
        return_json = jsonify( { "errorMessage": e } ), 400

    return return_json

if __name__ == "__main__":
    app.run(debug=True, host="0.0.0.0", port=int(os.environ.get("PORT", 8080)))
