"""Author sliding upper/lower eyelid surfaces; the facial shell and eyes stay fixed.

Used by build_wardrobe_rig.py; build(probe) is pure NumPy authoring.
"""
import json
import hashlib
from collections import Counter
from pathlib import Path
import numpy as np
from wardrobe_blink_domain import build_domain, components
from collections import defaultdict

def relax_lash_strip(rest, target, triangles):
    """ARAP authoring solve: follow the lid while preserving local lash shape."""
    unique={};mapping=[]
    for point in rest:
        key=tuple(np.round(point,5))
        mapping.append(unique.setdefault(key,len(unique)))
    mapping=np.array(mapping);n=len(unique)
    source=np.array(list(unique.keys()))
    goal=np.zeros((n,3));count=np.zeros(n)
    for i,j in enumerate(mapping):goal[j]+=target[i];count[j]+=1
    goal/=count[:,None]
    adjacency=np.zeros((n,n))
    for triangle in triangles:
        row=mapping[triangle]
        for a,b in zip(row,np.roll(row,1)):
            if a!=b:adjacency[a,b]=adjacency[b,a]=1.
    degree=adjacency.sum(axis=1)
    laplacian=np.diag(degree)-adjacency
    strength=np.maximum(degree*.08,.08)
    inverse=np.linalg.inv(laplacian+np.diag(strength))
    edges=source[:,None,:2]-source[None,:,:2]
    result=goal[:,:2].copy()
    for iteration in range(20):
        current=result[:,None,:]-result[None,:,:]
        covariance=np.einsum('ij,ijk,ijl->ikl',adjacency,current,edges)
        u,_,vh=np.linalg.svd(covariance)
        rotation=u@vh
        negative=np.linalg.det(rotation)<0
        u[negative,:,-1]*=-1
        rotation=u@vh
        rotated=np.einsum('ijkl,ijl->ijk',(rotation[:,None,:,:]+rotation[None,:,:,:])*.5,edges)
        rhs=np.sum(adjacency[:,:,None]*rotated,axis=1)+strength[:,None]*goal[:,:2]
        result=inverse@rhs
    answer=goal.copy();answer[:,:2]=result
    return answer[mapping]


def build(probe):
    src=probe['meshes'][1]; p=np.array(src['positions']); uv=np.array(src['uv'])
    tri=np.array(src['indices']).reshape(-1,3)
    domain=build_domain(src)
    graph=defaultdict(set)
    for a,b,c in tri:
        for i,j in [(a,b),(b,c),(c,a)]:graph[int(i)].add(int(j));graph[int(j)].add(int(i))
    groups=components(graph); main=set(max(groups,key=len)); weld={}; ids={}
    for i in sorted(main):ids[i]=weld.setdefault(tuple(np.round(p[i],5)),i)
    edges=Counter(tuple(sorted((ids[int(a)],ids[int(b)]))) for row in tri if int(row[0]) in main for a,b in zip(row,np.roll(row,1)))
    boundaries=[e for e,n in edges.items() if n==1 and e[0]!=e[1]]
    # Imported normal/UV seams split one lash strip into many islands. Weld
    # positional duplicates for ownership only; never change mesh indices.
    lash_ids=set()
    for group in groups:
        center=p[group].mean(0);tex=uv[group]
        if np.all((tex[:,0]>.39)&(tex[:,0]<.80)&(tex[:,1]<.20)) and 2.47<center[1]<2.57 and center[2]>.01:
            lash_ids.update(group)
    lash_graph=defaultdict(set);lash_weld={}
    for i in lash_ids:
        j=lash_weld.setdefault(tuple(np.round(p[i],5)),i)
        lash_graph[i].update(graph[i]&lash_ids);lash_graph[i].add(j);lash_graph[j].add(i)
    lash_components=components(lash_graph)
    surfaces=[]; shapes={}; profiles={}; lash_groups={}
    for side in ['L','R']:
        rim=set(domain['eyes'][side]['rim_vertices'])
        segments=[(a,b) for a,b in boundaries if a in rim and b in rim]
        xmin=min(p[i,0] for i in rim);xmax=max(p[i,0] for i in rim)
        samples=[]
        for x in np.linspace(xmin+1e-7,xmax-1e-7,65):
            hits=[]
            for a,b in segments:
                if min(p[a,0],p[b,0])<=x<=max(p[a,0],p[b,0]) and abs(p[a,0]-p[b,0])>1e-9:
                    t=(x-p[a,0])/(p[b,0]-p[a,0]); hits.append((p[a]*(1-t)+p[b]*t,uv[a]*(1-t)+uv[b]*t))
            if len(hits)<2:
                raise ValueError('Canonical socket must have upper and lower intersections')
            hits.sort(key=lambda q:q[0][1]);lo,hi=hits[0],hits[-1]
            samples.append({'upper':hi[0].tolist(),'lower':lo[0].tolist(),'upper_uv':hi[1].tolist(),'lower_uv':lo[1].tolist()})
        profiles[side]=samples

        def sample(x):
            u=np.clip((x-xmin)/(xmax-xmin),0,1)*64;i=min(63,int(u));f=u-i
            return {k:np.array(samples[i][k])*(1-f)+np.array(samples[i+1][k])*f for k in samples[0]}

        def shell(s,t):
            a=s['upper'];b=s['lower'];q=a*(1-t)+b*t
            # Curved lid skin outside the convex original eye, not a planar cover.
            # Vanishing aperture naturally removes the bulge at both canthi.
            bulge=min(.008,max(0.,a[1]-b[1])*.20)
            q[2]+=.00035+4*bulge*t*(1-t)
            return q

        meeting=.72  # upper lid travels 72% of the opening; lower lid 28%.
        for upper in [True,False]:
            base=[];closed=[];half=[];uvs=[];normals=[];indices=[]
            for col in range(65):
                s={k:np.array(v) for k,v in samples[col].items()}
                start=0. if upper else 1.
                for row in range(9):
                    reach=(meeting-start)*row/8
                    base.append(shell(s,start));closed.append(shell(s,start+reach));half.append(shell(s,start+.5*reach))
                    tex=s['upper_uv']*(1-(start+reach))+s['lower_uv']*(start+reach)
                    uvs.append([float(tex[0]),float(1-tex[1])]);normals.append([0.,0.,1.])
            for col in range(64):
                for row in range(8):
                    a=col*9+row;b=a+9;c=a+1;d=b+1
                    indices.extend([a,b,c,b,d,c] if upper else [a,c,b,b,c,d])
            base=np.array(base);closed=np.array(closed);half=np.array(half)
            surfaces.append({'name':side+('_UpperLid' if upper else '_LowerLid'),'side':side,
                             'vertices':base.round(8).tolist(),'closed':(closed-base).round(8).tolist(),
                             'arc':(half-(base+closed)*.5).round(8).tolist(),'uv':uvs,'normals':normals,'indices':indices})
        rows=[];arc=[];selected=[]
        # Continuous upper/lower attachment at the canthi, followed by an
        # authoring-only ARAP solve. No runtime solver or added frame cost.
        for group in lash_components:
            center=p[group].mean(0);tex=uv[group]
            is_lash=np.all((tex[:,0]>.39)&(tex[:,0]<.80)&(tex[:,1]<.20))
            if not is_lash or not (2.47<center[1]<2.57 and center[2]>.01):continue
            if (center[0]<-.11)!=(side=='L'):continue
            selected.extend(group)
            ends=[];mids=[]
            for i in group:
                s=sample(p[i,0])
                span=s['upper'][1]-s['lower'][1]
                start=1.-np.clip((p[i,1]-s['lower'][1])/max(span,1e-7),0.,1.)
                origin=shell(s,start)
                end=p[i]+shell(s,meeting)-origin
                mid=p[i]+shell(s,(start+meeting)*.5)-origin
                ends.append(end);mids.append(mid)
            local={v:i for i,v in enumerate(group)}
            faces=np.array([[local[int(v)] for v in t] for t in tri if all(int(v) in local for v in t)])
            ends=relax_lash_strip(p[group],np.array(ends),faces)
            mids=relax_lash_strip(p[group],np.array(mids),faces)
            for index,i in enumerate(group):
                end=ends[index];mid=mids[index]
                delta=end-p[i];corrective=mid-(p[i]+end)*.5
                rows.append([int(i),*np.round(delta,7).tolist()]);arc.append([int(i),*np.round(corrective,7).tolist()])
        shapes['blink.'+side]=rows;shapes['blink_mid.'+side]=arc;lash_groups[side]=selected
    return {'schema':2,'name':'sliding_lid_surface_v2',
            'authoring': {'generator':Path(__file__).name,
                          'probe_sha256':hashlib.sha256(json.dumps(probe,sort_keys=True).encode()).hexdigest(),
                          'coordinates':'Godot rest metres; UV is Godot mesh UV',
                          'default_closure':0.0, 'closure_range':[0.0,1.0]},
            'lash_motion': {'method':'welded continuous attachment with XY ARAP',
                            'target_weight':0.08,'iterations':20},
            'profiles':profiles,'surfaces':surfaces,
            'lash_vertices':lash_groups,'skin_vertices':domain['skin_vertices'],'shapes':shapes,
            'closure_contract':'upper 72%, lower 28%, curved depth with half-closure correction; fixed face and eyes'}


def author_blender(data):
    """Persist runtime geometry and keys as editable Blender source."""
    import bpy
    from mathutils import Vector
    def xyz(p):
        return Vector((p[0],-p[2],p[1]))
    face=bpy.data.objects['Face']
    basis=face.data.shape_keys.key_blocks['Basis']
    for name,rows in data['shapes'].items():
        key=face.data.shape_keys.key_blocks.get(name)
        if key is None:key=face.shape_key_add(name=name,from_mix=False)
        key.value=0.
        for i,point in enumerate(basis.data):key.data[i].co=point.co
        for i,x,y,z in rows:key.data[i].co+=xyz((x,y,z))
    rig=next(ob for ob in bpy.data.objects if ob.type=='ARMATURE')
    for surface in data['surfaces']:
        name='SlidingLid_'+surface['name']
        old=bpy.data.objects.get(name)
        if old:bpy.data.objects.remove(old,do_unlink=True)
        mesh=bpy.data.meshes.new(name)
        ids=surface['indices']
        mesh.from_pydata([xyz(v) for v in surface['vertices']],[],
                         [(ids[i],ids[i+2],ids[i+1]) for i in range(0,len(ids),3)])
        mesh.update()
        ob=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(ob)
        layer=mesh.uv_layers.new(name='UVMap')
        for loop in mesh.loops:layer.data[loop.index].uv=surface['uv'][loop.vertex_index]
        ob.vertex_groups.new(name='head').add(list(range(len(mesh.vertices))),1.,'REPLACE')
        ob.modifiers.new('Wardrobe armature','ARMATURE').object=rig
        ob.shape_key_add(name='Basis',from_mix=False)
        for key_name in ['closed','arc']:
            key=ob.shape_key_add(name=key_name,from_mix=False)
            key.value=0.
            for i,delta in enumerate(surface[key_name]):key.data[i].co+=xyz(delta)
        ob['closure_contract']=data['closure_contract']
        ob['runtime_material']='original face skin'


if __name__=='__main__':
    raise SystemExit('Use build_wardrobe_rig.py to bake into a scratch directory')
