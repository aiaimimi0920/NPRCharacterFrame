"""Extract the canonical skin and socket boundaries used by sliding lids.

The earlier facial-shell blink displacement is not used by this generator.
Ownership welds positional seams without changing canonical vertex indices.
"""

from collections import Counter, defaultdict


def components(adjacency):
    seen = set(); result = []
    for seed in adjacency:
        if seed in seen:
            continue
        seen.add(seed); group = [seed]; pending = [seed]
        while pending:
            for node in adjacency[pending.pop()] - seen:
                seen.add(node); group.append(node); pending.append(node)
        result.append(group)
    return result


def build_domain(source):
    points = source['positions']; indices = source['indices']
    triangles = [indices[i:i+3] for i in range(0, len(indices), 3)]
    adjacency = defaultdict(set)
    for a, b, c in triangles:
        for i, j in [(a, b), (b, c), (c, a)]:
            adjacency[i].add(j); adjacency[j].add(i)
    groups = components(adjacency)
    skin_groups = sorted([g for g in groups if len(g) > 100], key=len, reverse=True)
    if [len(g) for g in skin_groups] != [1292, 107, 107]:
        raise ValueError('Canonical skin topology changed')
    skin = set(sum(skin_groups, [])); main_skin = set(skin_groups[0])
    weld = {}; representative = {}
    for i in main_skin:
        representative[i] = weld.setdefault(tuple(round(x, 5) for x in points[i]), i)
    edges = Counter()
    for tri in triangles:
        if tri[0] not in main_skin:
            continue
        for a, b in zip(tri, tri[1:]+tri[:1]):
            edges[tuple(sorted([representative[a], representative[b]]))] += 1
    boundary = defaultdict(set)
    for (a, b), count in edges.items():
        if count == 1 and a != b:
            boundary[a].add(b); boundary[b].add(a)
    loops = components(boundary)
    metadata = {'skin_vertices': sorted(skin), 'eyes': {}}
    for side, cx in [('L', -.186), ('R', -.039)]:
        candidates = [g for g in loops if len(g) == 33 and abs(sum(points[i][0] for i in g)/len(g)-cx) < .02]
        if len(candidates) != 1:
            raise ValueError('Canonical eye socket boundary changed')
        metadata['eyes'][side] = {'rim_vertices': sorted(candidates[0])}
    return metadata
