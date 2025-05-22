from dataclasses import dataclass, field
from typing import Union, Optional

import geopandas as gpd
import pandas as pd
import networkx as nx
import metis
import numpy as np
import random

import h3
import quadbin  

ARTIFICIAL_DEMAND = 0

def quadbin_distance(q1, q2):
    u = quadbin.cell_to_tile(q1)
    v = quadbin.cell_to_tile(q2)
    return max(abs(u[0] - v[0]), abs(u[1] - v[1]))

def points_distance(q1, q2):
    return q1.distance(q2)

def fexp(f):
    return int(np.floor(np.log10(abs(f)))) if f != 0 else 0

def compute_weighted_edges_index(input_data: pd.DataFrame, kring_func) -> pd.DataFrame:
    input_data = input_data.copy()
    grid_map = input_data.set_index('geoid')[['node', 'score']].to_dict('index')
    edges = [
        (
            a_data['node'], 
            grid_map[b_id]['node'],
            int(1000 * (1 + np.exp(-2.0 * abs(a_data['score'] - grid_map[b_id]['score']))))
        )
        for a_id, a_data in grid_map.items()
        for b_id in kring_func(a_id)
        if b_id in grid_map and a_id < b_id
    ]
    return pd.DataFrame(edges, columns=['i', 'j', 'weight']).sort_values(['i', 'j'])

def compute_weighted_edges_geom(input_data: gpd.GeoDataFrame, _) -> pd.DataFrame:
    input_data = input_data.copy()
    joined = gpd.sjoin(input_data, input_data, how='inner', predicate='intersects', lsuffix='a', rsuffix='b')
    joined = joined[joined['node_a'] < joined['node_b']]
    joined['weight'] = (1000 * (1 + np.exp(-2.0 * abs(joined['score_a'] - joined['score_b']))))
    
    return joined[['node_a', 'node_b', 'weight']].rename(columns={'node_a': 'i', 'node_b': 'j'}).sort_values(['i', 'j'])

def get_functions(grid_type):
    if grid_type == 'h3':
        compute_kring = lambda x, k=1: h3.k_ring(x,k) - {x}      # exclude center
        compute_distance = lambda x, y: h3.h3_distance(x,y)
        compute_weights = compute_weighted_edges_index
    elif grid_type == 'quadbin':
        compute_kring = lambda x, k=1: quadbin.k_ring(x,k) - {x} # exclude center
        compute_distance = lambda x, y: quadbin_distance(x, y)
        compute_weights = compute_weighted_edges_index
    else:
        # TODO: GEOMETRY type
        #compute_kring = None
        #compute_distance = lambda x, y: points_distance(x, y)
        #compute_weights = compute_weighted_edges_geom
        pass
    return compute_kring, compute_distance, compute_weights

def connect_components(G, df, grid_index_column, compute_distance, verbose):
    while not nx.is_connected(G):
        if verbose:
            print('...entering while loop...') 
        
        # Get unconnected components and nodes of each
        S = [G.subgraph(c).copy() for c in sorted(nx.connected_components(G), key=len, reverse=True)]
        S_nodes = [s for s in sorted(nx.connected_components(G), key=len, reverse=True)]
        if verbose:
            print('#subgraphs:', len(S), '->', [len(c) for c in S])
        nodes_list = list(G._node.keys())
        new_edges = list()

        # For all components but the largest connected component
        for i in range(1, len(S)):
            # get center node 
            S_center_node = random.choice(nx.algorithms.distance_measures.center(S[i]))
            G_closest_node = 0
            shortest_dist = 99999
            # compute distance from center node to all nodes in remaining components (G-S)
            for n in [n for n in nodes_list if n not in S_nodes[i]]:
                dist = compute_distance(df.loc[S_center_node,grid_index_column], df.loc[n,grid_index_column])
                # select closest node
                if dist < shortest_dist:
                    shortest_dist = dist
                    G_closest_node = n
            S_closest_node = 0
            shortest_dist = 99999
            # compute the distance from closest node to nodes in the actual component (S)
            for n in S_nodes[i]:
                dist = compute_distance(df.loc[G_closest_node,grid_index_column], df.loc[n,grid_index_column])
                # select closest node
                if dist < shortest_dist:
                    shortest_dist = dist
                    S_closest_node = n
            # create new edge
            dist = int(1000 * (1 + np.exp(- 2.0 * np.abs(df.loc[G_closest_node,'score'] - df.loc[S_closest_node,'score']))))
            new_edges.append((G_closest_node, S_closest_node, dist))

        G.add_weighted_edges_from(new_edges)

    return G

@dataclass(repr = False)
class TerritoryBalancingProblem:
    df: gpd.GeoDataFrame
    edges: list
    nparts: int
    balance_tolerance : float = 0.1
    verbose : bool = False
    grid_type : str = field(default = "h3")
    grid_index_column : str = field(default = "h3")
    solver : Optional[str] = field(default = "METIS")

    def __post_init__(self):
        self.solution_found = False

        self.df = self.df.sort_values("node")
        self.df.index = list(range(self.df.shape[0]))
        
        if self.verbose:
            print("Grid type:", self.grid_type, "- grid index column:", self.grid_index_column)

        # Define functions
        _, compute_distance, _ = get_functions(self.grid_type)

        # Reduce overflow
        if self.verbose:
            print('Mean demand:', self.df.demand.mean())
        if (fexp(self.df.demand.std()) < 1) and (fexp(self.df.demand.mean()) < 1):
            self.df.demand = self.df.demand * 1000
            if self.verbose:
                print('New mean demand:', self.df.demand.mean())
        if (fexp(self.df.demand.sum()) >= 9):
            self.df.demand = self.df.demand / 10**(fexp(self.df.demand.sum())-8)
            if self.verbose:
                print('New sum demand:', self.df.demand.sum())

        if self.verbose:
            print(self.df.isna().any())
        
        # Define graph
        G = nx.Graph()
        G.add_nodes_from(self.df.index)
        for i, value in enumerate(self.df.demand.values):
            G.nodes[i]['weight'] = int(value)

        G.add_weighted_edges_from(self.edges, weight='weight')
        
        G.graph['node_weight_attr'] = 'weight' 
        G.graph['edge_weight_attr'] = 'weight'

        # If graph is not connected, connect unconnected components
        random.seed(0)
        G = connect_components(G, self.df, self.grid_index_column, compute_distance, self.verbose)
        if not nx.is_connected(G):
            print("Something has failed") # control test

        self.G = G
        if self.verbose:
            print(f"Graph is ready (#nodes: {self.G.number_of_nodes()})")
            
    
    def solve(self):
        if self.solver == 'KAHIP': 
            import subprocess
            adj = []
            for i in list(self.G.adjacency()):
                adj.append(np.array([x for x in list(i[1].keys())]))
            summ = int(np.ceil(sum([len(ia) for ia in adj])/2))
            pop = self.df.demand.values
            with open('test.graph','w') as g:
                g.write(str(len(adj))+" "+str(summ)+" 11\n")
                cnt = 0
                for ix in adj:
                    tow = str(int(pop[cnt] + 1))+" "
                    for ixi in ix:
                        if ixi>-10:
                            tow = tow+str(int(ixi+1))+" "+str(1)+" "
                    cnt+=1
                    tow+="\n"
                    g.write(tow)
            
            subprocess.Popen(['kaffpa', 'test.graph', f'--k={self.nparts}', f'--imbalance={self.balance_tolerance * 100}','--preconfiguration=strong', f'--output_filename=test.graph.kahip.parts{self.nparts}'])
            print('Kahip solved!')
            parts = []
            with open(f'test.graph.kahip.parts{self.nparts}', 'r') as reader:
                line = reader.readline()
                parts.append(int(line[:-1]))
                while line:
                    line = reader.readline()
                    if line !='':
                        parts.append(int(line[:-1]))
            
        elif self.solver == 'METIS':
            (cut, parts) = metis.part_graph(self.G, self.nparts, ufactor=int(self.balance_tolerance * 1000), niter=10000, objtype='vol', contig = True)
            
        if self.verbose:
            print("Partition is ready.")      
        self.df['cluster'] = parts
        self.solution_found = True
            
        return self.solution_found
        