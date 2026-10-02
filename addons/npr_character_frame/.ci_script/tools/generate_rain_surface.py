"""Rebuild the sample's surface-rain atlas from an authored geometry probe and masks.

The numerical bake retains the reviewed sample calibration; it is not an arbitrary
model adapter. Defaults follow this plugin's location, never a checkout folder name.
"""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
from PIL import Image, __version__ as pillow_version

ADDON = Path(__file__).resolve().parents[2]
ROOT = next(parent for parent in ADDON.parents if (parent / "project.godot").is_file())
BASE = ADDON / "samples/silver_wolf/assets/authoring/silver_wolf/wardrobe"
SIZE = (1536, 1536)
MATERIAL_SIZE = (1024, 512)

def load_inputs(source, material_path, garment_path):
    mesh = json.loads(source.read_text(encoding="utf-8"))["meshes"][0]
    p, uv = np.array(mesh["positions"], dtype=float), np.array(mesh["uv"], dtype=float)
    indices = np.array(mesh["indices"])
    if p.ndim != 2 or p.shape[1] != 3 or len(p) == 0 or not np.isfinite(p).all():
        raise ValueError("positions must be a nonempty array of finite 3D vertices")
    if uv.shape != (len(p), 2) or not np.isfinite(uv).all():
        raise ValueError("uv must contain a finite 2D coordinate per vertex")
    if (indices.ndim != 1 or indices.size == 0 or indices.size % 3
            or not np.issubdtype(indices.dtype, np.integer)
            or indices.min() < 0 or indices.max() >= len(p)):
        raise ValueError("indices must be flat complete triangles with valid integer vertex indices")
    maps = []
    for path in (material_path, garment_path):
        with Image.open(path) as image:
            if image.mode != "RGBA" or image.size != MATERIAL_SIZE:
                raise ValueError(f"{path.name} requires RGBA {MATERIAL_SIZE[0]} x {MATERIAL_SIZE[1]}")
            maps.append(np.array(image))
    return p, uv, indices.reshape(-1, 3), maps[0], maps[1]


def bake(source, material_path, garment_path, output):
    p, uv, ids, material, garment = load_inputs(source, material_path, garment_path)
    # Geometric welding connects duplicated seam vertices, but only manifold edges.
    weld, lookup = [], {}
    for v in p:
        key = tuple(np.round(v, 5))
        if key not in lookup:
            lookup[key] = len(lookup)
        weld.append(lookup[key])
    edges, uv_edges = {}, {}
    for t, face in enumerate(ids):
        for k in range(3):
            a, b = face[(k+1)%3], face[(k+2)%3]
            edges.setdefault(tuple(sorted((weld[a], weld[b]))), []).append((t,k))
            key = tuple(sorted((tuple(np.round(uv[a],6)), tuple(np.round(uv[b],6)))))
            uv_edges.setdefault((tuple(sorted((weld[a], weld[b]))),key), []).append(t)
    adj = np.full((len(ids),3), -1, dtype=int)
    for rows in edges.values():
        if len(rows)==2:
            (a,i),(b,j)=rows
            adj[a,i],adj[b,j]=b,a
    parent = list(range(len(ids)))
    def root(a):
        while parent[a]!=a:
            parent[a]=parent[parent[a]]; a=parent[a]
        return a
    for rows in uv_edges.values():
        if len(rows)==2:
            parent[root(rows[0])]=root(rows[1])
    vertex_owner={}
    for t,face in enumerate(ids):
        for v in face:
            if int(v) in vertex_owner:
                parent[root(t)]=root(vertex_owner[int(v)])
            vertex_owner[int(v)]=t
    roots = {}; charts=[]
    for t in range(len(ids)):
        r=root(t)
        if r not in roots: roots[r]=len(roots)+1
        charts.append(roots[r])
    original_uv = uv.copy()
    atlas_uv = np.zeros_like(uv)
    boxes=[]
    for chart in range(1,len(roots)+1):
        faces=ids[np.array(charts)==chart]
        vertices=np.unique(faces)
        lo=uv[vertices].min(axis=0); hi=uv[vertices].max(axis=0)
        span=np.maximum(hi-lo,1e-5)
        xyz=p[faces]
        physical=np.linalg.norm(np.cross(xyz[:,1]-xyz[:,0],xyz[:,2]-xyz[:,0]),axis=1).sum()*.5
        tex=uv[faces]
        e=tex[:,1]-tex[:,0]; f=tex[:,2]-tex[:,0]
        uv_area=np.abs(e[:,0]*f[:,1]-e[:,1]*f[:,0]).sum()*.5
        scale=min(6000,300*np.sqrt(physical/max(uv_area,1e-10)))
        size=np.maximum(np.ceil(span*scale).astype(int),2)+6
        boxes.append((chart,vertices,lo,span,size))
    # Deterministic shelves. Reduce uniformly until the atlas fits.
    packing=1.0
    for _attempt in range(128):
        x=y=row=0; locations={}
        for chart,vertices,lo,span,size in sorted(boxes,key=lambda b:-b[4][1]):
            w,h=np.maximum(np.ceil(size*packing).astype(int),8)
            if x+w>SIZE[0]: x=0; y+=row; row=0
            locations[chart]=(x,y,w,h); x+=w; row=max(row,h)
        if y+row<=SIZE[1] and all(loc[2]<=SIZE[0] for loc in locations.values()): break
        packing*=.9
    else:
        raise ValueError("Charts cannot fit the fixed sample atlas")
    if len(roots) > 65535:
        raise ValueError("Chart IDs exceed the RG byte encoding")
    assigned={}
    for chart,vertices,lo,span,size in boxes:
        x,y,w,h=locations[chart]
        for vertex in vertices:
            if int(vertex) in assigned and assigned[int(vertex)]!=chart:
                raise RuntimeError("UV chart shares a vertex; split source required")
            assigned[int(vertex)]=chart
        atlas_uv[vertices]=(np.array([x+3,y+3])+(uv[vertices]-lo)/span*np.array([w-6,h-6]))/SIZE
    uv=atlas_uv
    packed=np.zeros((int(np.ceil(len(uv)/256)),256,4),dtype='<f4')
    packed.reshape(-1,4)[:len(uv),:2]=uv
    owner=np.zeros((SIZE[1],SIZE[0]),dtype=np.int32)
    pos=np.zeros((SIZE[1],SIZE[0],3),dtype=np.float32)
    collisions=np.zeros(owner.shape,dtype=bool)
    areas=[]; kinds=[]; candidates=[]
    # Classification uses the authored material map; stockings use reviewed leg geometry.
    for t, face in enumerate(ids):
        xyz=p[face]; tex=uv[face]*SIZE
        area=float(np.linalg.norm(np.cross(xyz[1]-xyz[0],xyz[2]-xyz[0]))*.5)
        areas.append(area)
        center=xyz.mean(axis=0); uvc=original_uv[face].mean(axis=0)
        x,y=np.clip((uvc*MATERIAL_SIZE).astype(int),[0,0],np.array(MATERIAL_SIZE)-1)
        c=material[y,x]; kind=int(np.argmax(c))+1 if max(c)>128 else 0
        if kind==0 and .18<center[1]<1.48 and garment[y,x,3]>128: kind=5
        kinds.append(kind)
        if kind and area>1e-9: candidates.append(t)
        lo=np.maximum(np.floor(tex.min(axis=0)).astype(int),0)
        hi=np.minimum(np.ceil(tex.max(axis=0)).astype(int),np.array(SIZE)-1)
        if np.any(hi<lo): continue
        xx,yy=np.meshgrid(np.arange(lo[0],hi[0]+1)+.5,np.arange(lo[1],hi[1]+1)+.5)
        a,b,cuv=tex; e=b-a; f=cuv-a; det=e[0]*f[1]-e[1]*f[0]
        if abs(det)<1e-9: continue
        qx,qy=xx-a[0], yy-a[1]
        v=(qx*f[1]-qy*f[0])/det; w=(e[0]*qy-e[1]*qx)/det; u=1-v-w
        inside=(u>=-1e-6)&(v>=-1e-6)&(w>=-1e-6)
        sl=(slice(lo[1],hi[1]+1),slice(lo[0],hi[0]+1))
        xyz_at=u[:,:,None]*xyz[0]+v[:,:,None]*xyz[1]+w[:,:,None]*xyz[2]
        old=owner[sl]
        collisions[sl] |= inside & (old!=0) & (np.linalg.norm(pos[sl]-xyz_at,axis=2)>.006)
        old[inside]=charts[t]; pos[sl][inside]=xyz_at[inside]
    owner[collisions]=0
    image=np.zeros((*owner.shape,4),dtype=np.uint8)
    image[:,:,0]=owner%256; image[:,:,1]=owner//256; image[:,:,3]=255
    result={"schema":1,"size":SIZE,"vertex_texture_height":packed.shape[0],"positions":p.tolist(),"uv":uv.tolist(),"indices":ids.tolist(),
            "neighbors":adj.tolist(),"charts":charts,"areas":areas,"kinds":kinds,"candidates":candidates,
            "inputs":{role: {"file":path.name,"sha256":hashlib.sha256(path.read_bytes()).hexdigest()}
                      for role,path in (("geometry_probe",source),("material_map",material_path),("garment_mask",garment_path))},
            "generator_sha256":hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
            "generator_config":{"atlas_size":SIZE,"material_size":MATERIAL_SIZE,"hosiery_height_interval":[0.18,1.48],
                                "numpy":np.__version__,"pillow":pillow_version},
            "overlap_pixels_disabled":int(collisions.sum())}
    output.mkdir(parents=True, exist_ok=True)
    (output/"rain_vertex_uv.bin").write_bytes(packed.tobytes())
    Image.fromarray(image).save(output/"rain_chart.png")
    (output/"rain_chart.bin").write_bytes(image.tobytes())
    (output/"rain_surface.json").write_text(json.dumps(result,separators=(",",":"))+"\n", encoding="utf-8")
    print("RAIN_SURFACE",len(ids),"triangles",len(candidates),"receivers",len(roots),"charts",
          int(collisions.sum()),"overlap pixels excluded")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=ADDON / "samples/silver_wolf/import_sources/soft_tissue_input_probe.json")
    parser.add_argument("--material", type=Path, default=BASE / "material_wetness.png")
    parser.add_argument("--garment", type=Path, default=BASE / "garment_mask.png")
    parser.add_argument("--output", type=Path, default=ROOT / ".temp/rain_bake")
    args = parser.parse_args()
    try:
        bake(args.source, args.material, args.garment, args.output)
    except (OSError, ValueError, KeyError, IndexError) as error:
        parser.exit(1, f"Rain bake failed: {error}\n")


if __name__=="__main__": main()
