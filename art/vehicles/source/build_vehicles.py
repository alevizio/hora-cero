"""Original, parametric retro vehicle meshes. Python 3 + numpy; no downloaded geometry.

Internal coordinates: X forward, Y left, Z up. Export: Godot/glTF Y up, -Z forward.
"""
from pathlib import Path
import json, math, struct, shutil
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
MODELS = ROOT / 'models'
MODELS.mkdir(parents=True, exist_ok=True)
T = np.array([[0,-1,0],[0,0,1],[-1,0,0]], dtype=float)

def vec(v): return np.asarray(v, dtype=float)
def unit(v):
    v = vec(v); n = np.linalg.norm(v)
    return v / max(n, 1e-10)

class Model:
    def __init__(self, name, color):
        self.name=name; self.nodes=[]; self.materials=[]; self.groups={}; self.meta={}
        self.root=self.node(name)
        self.mat('Paint',color,.13,.53)
        self.mat('Paint_dark',tuple(c*.75 for c in color),.1,.6)
        self.mat('Rubber',(0.035,.041,.045),0,.9)
        self.mat('Trim',(0.065,.075,.078),.05,.66)
        self.mat('Glass',(.12,.22,.25),.28,.24)
        self.mat('Chrome',(.57,.61,.59),.7,.28)
        self.mat('Wheel_steel',(.31,.34,.33),.65,.43)
        self.mat('Headlamp',(.88,.84,.66),.12,.27)
        self.mat('Indicator',(.91,.31,.055),.05,.37)
        self.mat('Tail_light',(.52,.035,.025),.08,.32)
        self.mat('Plate',(.82,.79,.65),.05,.85)
        self.mat('Interior',(.115,.13,.12),0,.96)
        self.mat('Seat_fabric',(.26,.23,.18),0,1)
        self.mat('Reflector',(.56,.65,.67),.65,.2)
    def mat(self,name,color,metal=0,rough=.6):
        self.materials.append({'name':name,'pbrMetallicRoughness':{'baseColorFactor':list(color)+[1], 'metallicFactor':metal,'roughnessFactor':rough}})
    def node(self,name,parent=None,pivot=(0,0,0)):
        if parent is None and self.nodes: parent=0
        idx=len(self.nodes)
        self.nodes.append({'name':name,'pivot':vec(pivot),'parent':parent})
        return idx
    def polygon(self,points,mat='Paint',node=None,normal=None):
        node=self.root if node is None else node
        pts=np.asarray(points,dtype=float)
        if len(pts)<3: return
        n=sum((np.cross(pts[i],pts[(i+1)%len(pts)]) for i in range(len(pts))),np.zeros(3))
        if np.linalg.norm(n)<1e-9: return
        if normal is not None and np.dot(n,normal)<0: pts=pts[::-1]
        n=unit(sum((np.cross(pts[i],pts[(i+1)%len(pts)]) for i in range(len(pts))),np.zeros(3)))
        mi=next(i for i,m in enumerate(self.materials) if m['name']==mat)
        data=self.groups.setdefault((node,mi),[[],[]])
        for i in range(1,len(pts)-1):
            if np.linalg.norm(np.cross(pts[i]-pts[0],pts[i+1]-pts[0]))<1e-10: continue
            for p in (pts[0],pts[i],pts[i+1]):
                data[0].append(p); data[1].append(n)
    def box(self,c,size,mat='Paint',node=None,rot=None):
        c=vec(c); h=vec(size)/2
        pts=np.array([[x,y,z] for x in [-h[0],h[0]] for y in [-h[1],h[1]] for z in [-h[2],h[2]]])
        if rot is not None: pts=pts @ rot.T
        pts+=c
        for inds in [(0,1,3,2),(4,6,7,5),(0,4,5,1),(2,3,7,6),(0,2,6,4),(1,5,7,3)]:
            p=pts[list(inds)]
            self.polygon(p,mat,node,normal=np.mean(p,axis=0)-c)
    def rod(self,a,b,r,mat='Trim',node=None,n=6,r2=None):
        a=vec(a); b=vec(b); d=unit(b-a)
        u=unit(np.cross(d,[0,0,1] if abs(d[2])<.9 else [1,0,0])); v=np.cross(d,u)
        r2=r if r2 is None else r2
        ra=[a+r*(u*math.cos(t)+v*math.sin(t)) for t in np.arange(n)*2*math.pi/n]
        rb=[b+r2*(u*math.cos(t)+v*math.sin(t)) for t in np.arange(n)*2*math.pi/n]
        self.polygon(ra,mat,node,-d); self.polygon(rb,mat,node,d)
        for i in range(n):
            j=(i+1)%n
            self.polygon([ra[i],ra[j],rb[j],rb[i]],mat,node,(ra[i]+ra[j])/2-a)
    def line(self,points,r=.008,mat='Trim',node=None):
        for a,b in zip(points[:-1],points[1:]): self.rod(a,b,r,mat,node,4)
    def bevel_box(self,c,size,b=.035,mat='Paint',node=None):
        # A chamfered prism, rather than a bevel modifier dependency.
        x,y,z=c; lx,ly,lz=vec(size)/2; b=min(b,lx*.5,ly*.5,lz*.5)
        ring=[(-lx+b,-ly), (lx-b,-ly),(lx,-ly+b),(lx,ly-b),(lx-b,ly),(-lx+b,ly),(-lx,ly-b),(-lx,-ly+b)]
        layers=[]
        for zz,shrink in [(z-lz,b),(z-lz+b,0),(z+lz-b,0),(z+lz,b)]:
            layers.append([vec((x+xx*(1-shrink/lx),y+yy*(1-shrink/ly),zz)) for xx,yy in ring])
        self.polygon(layers[0],mat,node,[0,0,-1]); self.polygon(layers[-1],mat,node,[0,0,1])
        for a,bb in zip(layers[:-1],layers[1:]):
            for i in range(8):
                j=(i+1)%8
                self.polygon([a[i],a[j],bb[j],bb[i]],mat,node,vec((a[i]+a[j])/2)-vec(c))
    def surface(self,pts,mat,node=None):
        p=np.array(pts); self.polygon(p,mat,node,normal=np.mean(p,axis=0)-vec([0,0,.7]))
    def export(self,path):
        binary=bytearray(); views=[]; access=[]; meshes=[]; nodes=[]
        def accessor(arr,typ):
            arr=np.asarray(arr,dtype='<f4'); start=len(binary)
            binary.extend(arr.tobytes())
            views.append({'buffer':0,'byteOffset':start,'byteLength':arr.nbytes,'target':34962})
            ac={'bufferView':len(views)-1,'componentType':5126,'count':len(arr),'type':typ}
            if typ=='VEC3': ac.update(min=arr.min(0).tolist(),max=arr.max(0).tolist())
            access.append(ac); return len(access)-1
        for i,nd in enumerate(self.nodes):
            out={'name':nd['name']}
            parent_pivot=self.nodes[nd['parent']]['pivot'] if nd['parent'] is not None else vec([0,0,0])
            out['translation']=(T@(nd['pivot']-parent_pivot)).tolist()
            children=[j for j,n in enumerate(self.nodes) if n['parent']==i]
            if children: out['children']=children
            prims=[]
            for (ni,mi),(ps,ns) in self.groups.items():
                if ni!=i: continue
                pos=(np.array(ps)-nd['pivot'])@T.T
                norm=np.array(ns)@T.T
                pa=accessor(pos,'VEC3'); na=accessor(norm,'VEC3')
                prims.append({'attributes':{'POSITION':pa,'NORMAL':na},'material':mi,'mode':4})
            if prims:
                out['mesh']=len(meshes); meshes.append({'name':nd['name'],'primitives':prims})
            nodes.append(out)
        tris=sum(len(d[0])//3 for d in self.groups.values())
        all_positions=np.concatenate([np.asarray(d[0])@T.T for d in self.groups.values()])
        minimum=all_positions.min(0); maximum=all_positions.max(0)
        self.meta.update(triangles=tris,mesh_nodes=len(meshes),material_surfaces=sum(len(m['primitives']) for m in meshes),bounds_m={'min':minimum.round(5).tolist(),'max':maximum.round(5).tolist()},dimensions_m={'width':round(float(maximum[0]-minimum[0]),4),'height':round(float(maximum[1]-minimum[1]),4),'length':round(float(maximum[2]-minimum[2]),4)})
        gltf={'asset':{'version':'2.0','generator':'Retro Vehicle Pack - original parametric meshes'},'scene':0,'scenes':[{'nodes':[0]}], 'nodes':nodes,'meshes':meshes,'materials':self.materials,'buffers':[{'byteLength':len(binary)}],'bufferViews':views,'accessors':access,'extras':self.meta}
        j=json.dumps(gltf,separators=(',',':')).encode(); j+=b' '*((-len(j))%4); binary+=b'\0'*((-len(binary))%4)
        blob=struct.pack('<III',0x46546c67,2,12+8+len(j)+8+len(binary))+struct.pack('<II',len(j),0x4e4f534a)+j+struct.pack('<II',len(binary),0x004e4942)+binary
        path.write_bytes(blob)
        return gltf

SPECS=[
dict(id='01_panel_van',name='Panel Van 90',kind='van',color=(.68,.65,.51),L=4.55,W=1.85,H=2.02,wb=2.75,r=.345,belt=1.13,ab=1.56,at=1.14,rt=-2.18,rb=-2.21,doors=2,chrome=False),
dict(id='02_classic_sedan',name='Classic Sedan 78',kind='sedan',color=(.22,.43,.43),L=4.34,W=1.64,H=1.43,wb=2.48,r=.30,belt=.94,ab=.77,at=.24,rt=-.83,rb=-1.35,doors=4,chrome=True),
dict(id='03_sport_coupe',name='Sport Coupe 88',kind='coupe',color=(.58,.16,.12),L=4.37,W=1.72,H=1.33,wb=2.47,r=.315,belt=.86,ab=.83,at=.12,rt=-.76,rb=-1.83,doors=2,chrome=False),
dict(id='04_family_wagon',name='Family Wagon 78',kind='wagon',color=(.65,.52,.23),L=4.43,W=1.66,H=1.48,wb=2.48,r=.305,belt=.96,ab=.80,at=.25,rt=-1.68,rb=-1.91,doors=4,chrome=True),
dict(id='05_delivery_van',name='Delivery Van 92',kind='delivery',color=(.72,.72,.64),L=4.02,W=1.60,H=1.82,wb=2.39,r=.29,belt=.99,ab=.80,at=.35,rt=-.50,rb=-.62,doors=2,chrome=False),
dict(id='06_city_hatch',name='City Hatch 90',kind='hatch',color=(.24,.43,.58),L=3.57,W=1.56,H=1.42,wb=2.22,r=.28,belt=.93,ab=.64,at=.21,rt=-.92,rb=-1.38,doors=2,chrome=False),
dict(id='07_microcar',name='Microcar 70',kind='micro',color=(.68,.70,.50),L=3.20,W=1.40,H=1.40,wb=2.0,r=.27,belt=.87,ab=.62,at=.25,rt=-.53,rb=-1.06,doors=2,chrome=True),
dict(id='08_work_pickup',name='Work Pickup 79',kind='pickup',color=(.27,.37,.28),L=4.65,W=1.77,H=1.69,wb=2.86,r=.35,belt=1.10,ab=1.02,at=.57,rt=-.30,rb=-.42,doors=2,chrome=True),
]

def build(s):
    m=Model(s['id'],s['color'])
    L,W,H,wb,r,belt=[s[k] for k in ['L','W','H','wb','r','belt']]
    w=W/2; front=L/2; rear=-L/2; wheelx=[wb/2,-wb/2]
    kind=s['kind']; ab,at,rt,rb=[s[k] for k in ['ab','at','rt','rb']]
    cabH=1.45 if kind=='delivery' else H
    roofw=w*(.88 if kind=='van' else .82 if kind=='micro' else .84)
    sill=.34 if r<.32 else .41
    arch=r+.075
    shell=m.node('Body'); trim=m.node('Exterior_Details'); inside=m.node('Interior')
    hood=m.node('Hood',pivot=(ab,0,belt))
    backpanel=m.node('Tailgate' if kind in ('van','delivery','wagon','hatch','pickup') else 'Trunk',pivot=(rb,0,belt))
    def width(x):
        if kind=='micro': return w*(1-.23*(abs(x)/(L/2))**4)
        return w*(1-.08*(max(0,abs(x)-(L/2-.35))/.35))
    def top(x):
        # A gentle drop towards the nose and tail makes distinct shoulders.
        if kind=='micro': return belt-.13*(max(0,abs(x)-1.05)/.55)
        return belt-.075*(max(0,abs(x)-(L/2-.45))/.45)
    def bottom(x):
        z=sill
        for a in wheelx:
            if abs(x-a)<=arch: z=max(z,r+math.sqrt(max(0,arch**2-(x-a)**2)))
        return z
    # Front and rear doors get their own complete panel and window meshes.
    mid=(ab+rb)*.5+.02
    door_ranges=[]
    for side in [1,-1]:
        sn='L' if side==1 else 'R'
        if s['doors']==4:
            pairs=[('Front',mid,ab-.035),('Rear',rb+.08,mid-.025)]
        else:
            end=rt+.12 if kind in ('hatch','coupe') else rb+.08
            if kind=='van': end=.16
            pairs=[('Front',end,ab-.035)]
        for label,lo,hi in pairs:
            nd=m.node('Door_'+label+'_'+sn,pivot=(hi,side*w,belt-.1))
            door_ranges.append((side,lo,hi,nd))
    def node_at(x,side):
        for ss,lo,hi,nd in door_ranges:
            if ss==side and lo<=x<=hi: return nd
        return shell
    xs=set(np.linspace(rear,front,23).tolist()+[rear,front,ab,rb])
    for axle in wheelx:
        for t in np.linspace(0,math.pi,17): xs.add(axle+arch*math.cos(t))
    for side,lo,hi,nd in door_ranges: xs.update([lo,hi])
    xs=sorted(x for x in xs if rear<=x<=front)
    for a,b in zip(xs[:-1],xs[1:]):
        for side in [1,-1]:
            nd=node_at((a+b)/2,side)
            # Three bands and wheel-arch cuts in the body itself.
            points=[]
            for x in (a,b):
                bo=bottom(x); to=top(x); wz=width(x)
                points.append([(x,side*wz*.955,bo),(x,side*wz,max(bo,to-.10)),(x,side*wz*.98,to)])
            for j in range(2):
                m.polygon([points[0][j],points[1][j],points[1][j+1],points[0][j+1]],'Paint',nd,[0,side,0])
        if (a+b)/2>ab or (a+b)/2<rb:
            nd=hood if (a+b)/2>ab else backpanel
            if kind=='pickup' and (a+b)/2<rb: continue
            for side in [1,-1]:
                m.polygon([(a,side*width(a)*.98,top(a)),(b,side*width(b)*.98,top(b)),(b,0,top(b)+.018),(a,0,top(a)+.018)],'Paint',nd,[0,0,1])
    # End panels, bumper slabs, and corner detail.
    for sign in [1,-1]:
        x=front if sign==1 else rear
        nd=shell if sign==1 else backpanel
        m.polygon([(x,-width(x)*.955,sill),(x,width(x)*.955,sill),(x,width(x)*.98,top(x)),(x,-width(x)*.98,top(x))],'Paint',nd,[sign,0,0])
        bumMat='Chrome' if s['chrome'] else 'Trim'
        z=.53 if kind in ('van','pickup') else .43
        m.bevel_box((x+sign*.035,0,z),(.13,W*(.84 if kind=='micro' else .98),.13),.025,bumMat,trim)
        if s['chrome']:
            for yy in [-w*.66,w*.66]: m.bevel_box((x+sign*.10,yy,z+.015),(.055,.075,.18),.014,'Rubber',trim)
        else:
            m.box((x+sign*.09,0,z+.025),(.008,W*.94,.023),'Rubber',trim)
        # License plate, frame and suggestive stamped characters.
        pz=z+.02 if sign==-1 else z+.21
        m.box((x+sign*.11,0,pz),(.022,.34,.12),'Trim',trim)
        m.box((x+sign*.124,0,pz),(.008,.30,.085),'Plate',trim)
        for j in range(6):
            m.box((x+sign*.13,-.109+j*.043,pz),(.003,.018,.045),'Trim',trim)
    # Wheel wells are actual openings; visible lips run over the cut edges.
    for axle in wheelx:
        for side in [1,-1]:
            lip=[]; inner=[]
            for t in np.linspace(0,math.pi,17):
                x=axle+arch*math.cos(t); z=r+arch*math.sin(t)
                lip.append((x,side*width(x)*.963,z+.003))
                inner.append((x,side*(width(x)-.095),z-.006))
            m.line(lip,.014,'Paint_dark',shell)
            for i in range(16): m.polygon([lip[i],lip[i+1],inner[i+1],inner[i]],'Interior',shell,[0,side,0])
    # Lower chassis / floor; narrow enough to keep arches empty.
    m.bevel_box((0,0,.37),(L-.40,W-.42,.13),.035,'Trim',shell)
    m.box(((ab+rb)/2,0,.49),(ab-rb,W-.24,.07),'Interior',inside)
    # Cabin has framed inset glazing, solid roof, and an open inside.
    def side_y(z): return w*.98+(roofw-w*.98)*max(0,min(1,(z-belt)/(cabH-belt)))
    def sidept(x,z,side,extra=0): return (x,side*(side_y(z)+extra),z)
    # Sloped windshield and backlight. Inset polygons preserve wide paint pillars.
    def glass_face(corners,nd,normal,glass=True):
        p=np.array(corners); ctr=p.mean(0); innerpts=ctr+(p-ctr)*.90
        for j in range(4): m.polygon([p[j],p[(j+1)%4],innerpts[(j+1)%4],innerpts[j]],'Paint',nd,normal)
        m.polygon(innerpts+vec(normal)*.004,'Glass' if glass else 'Paint',nd,normal)
        m.line(list(innerpts)+[innerpts[0]],.012,'Rubber',nd)
        return innerpts
    wind=glass_face([(ab,-w*.98,belt),(ab,w*.98,belt),(at,roofw,cabH-.055),(at,-roofw,cabH-.055)],shell,[1,0,.4])
    if kind not in ('van','delivery','pickup'):
        glass_face([(rb,w*.98,belt),(rb,-w*.98,belt),(rt,-roofw,cabH-.055),(rt,roofw,cabH-.055)],backpanel,[-1,0,.4])
    elif kind=='pickup':
        glass_face([(rb,w*.98,belt),(rb,-w*.98,belt),(rt,-roofw,cabH-.055),(rt,roofw,cabH-.055)],shell,[-1,0,0])
    elif kind=='van':
        # Two rear cargo doors, their high windows and hinge straps.
        for side in [1,-1]:
            glass_face([(rb,side*.04,belt),(rb,side*w*.98,belt),(rt,side*roofw,cabH-.055),(rt,side*.04,cabH-.055)],backpanel,[-1,0,0])
            for z in [belt+.18,cabH-.18]:
                hinge_x=rb+(rt-rb)*(z-belt)/(cabH-.055-belt)-.014
                m.box((hinge_x,side*side_y(z)*.94,z),(.04,.065,.13),'Chrome',trim)
        m.line([(rear-.025,0,sill),(rb-.015,0,belt),(rt-.02,0,cabH-.055)],.009,'Trim',backpanel)
    # Curved roof cross section, longitudinal curvature.
    roofxs=[rt,rt+.07,(rt+at)/2,at-.07,at]
    roofys=[-1,-.92,-.68,0,.68,.92,1]
    for xi,(a,b) in enumerate(zip(roofxs[:-1],roofxs[1:])):
        for u,v in zip(roofys[:-1],roofys[1:]):
            def roofpt(x,t):
                edge=.055*abs(t)**4
                longitudinal=.022*(abs((x-(rt+at)/2)/((at-rt)/2)))**4*(1-t*t)
                return (x,t*roofw,cabH-edge-longitudinal)
            m.polygon([roofpt(a,u),roofpt(b,u),roofpt(b,v),roofpt(a,v)],'Paint',shell,[0,0,1])
    # Close the narrow bands between the crowned roof and flat glazing tops.
    for x,normal in [(at,[1,0,0]),(rt,[-1,0,0])]:
        for u,v in zip(roofys[:-1],roofys[1:]):
            m.polygon([(x,u*roofw,cabH-.055),(x,v*roofw,cabH-.055),roofpt(x,v),roofpt(x,u)],'Paint',shell,normal)
    # Cabin side windows partitioned with period-correct pillars.
    for side in [1,-1]:
        outline=np.array([sidept(ab,belt,side),sidept(at,cabH-.055,side),sidept(rt,cabH-.055,side),sidept(rb,belt,side)])
        # Fill at the outer edges, then glazing cells split at the B/C pillars.
        if kind=='van': breaks=[rb,.16,ab]
        elif s['doors']==4: breaks=[rb,mid,ab]
        elif kind in ('coupe','hatch'): breaks=[rb,rt+.12,ab]
        else: breaks=[rb,ab]
        def upper(x):
            if x>at: return belt+(cabH-.055-belt)*(ab-x)/(ab-at)
            if x<rt: return belt+(cabH-.055-belt)*(x-rb)/(rt-rb)
            return cabH-.055
        for lo,hi in zip(breaks[:-1],breaks[1:]):
            pts=[sidept(lo,belt,side),sidept(hi,belt,side)]
            if hi>at>lo: pts.append(sidept(at,cabH-.055,side))
            else: pts.append(sidept(hi,upper(hi),side))
            if lo<rt<hi: pts.append(sidept(rt,cabH-.055,side))
            else: pts.append(sidept(lo,upper(lo),side))
            # Remove coincident triangle corners.
            clean=[]
            for p in pts:
                if not clean or np.linalg.norm(vec(p)-vec(clean[-1]))>.001: clean.append(p)
            if np.linalg.norm(vec(clean[-1])-vec(clean[0]))<.001: clean.pop()
            p=np.array(clean); ctr=p.mean(0); inset=ctr+(p-ctr)*.87
            nd=node_at((lo+hi)/2,side)
            for i in range(len(p)):
                j=(i+1)%len(p)
                m.polygon([p[i],p[j],inset[j],inset[i]],'Paint',nd,[0,side,0])
            # Panel van has unglazed cargo sides.
            cargo=kind=='van' and hi<=.16
            m.polygon(inset+vec([0,side*.004,0]),'Paint' if cargo else 'Glass',nd,[0,side,0])
            m.line(list(inset)+[inset[0]],.010,'Paint_dark' if cargo else 'Rubber',nd)
            if cargo:
                m.line([(rb+.15,side*(w*.98+.01),belt+.12),(.05,side*(w*.98+.01),belt+.12)],.008,'Paint_dark',shell)
        # Rain gutter / brightwork follows roof edge.
        m.line([sidept(ab,belt+.01,side,.012),sidept(at,cabH-.045,side,.008),sidept(rt,cabH-.045,side,.008),sidept(rb,belt+.01,side,.012)],.011,'Chrome' if s['chrome'] else 'Paint_dark',trim)
    # Scribed door gaps and metal handles. Door nodes include lower shell and glass.
    for side,lo,hi,nd in door_ranges:
        gapz=max(sill+.07,bottom(lo)+.018)
        m.line([(lo,side*width(lo)*1.003,belt-.03),(lo,side*width(lo)*1.003,gapz),((lo+hi)/2,side*w*.965,sill+.045),(hi,side*width(hi)*1.003,max(sill+.07,bottom(hi)+.018)),(hi,side*width(hi)*1.003,belt-.025)],.006,'Trim',nd)
        hx=lo+.17; hy=side*(width(hx)+.014)
        m.bevel_box((hx,hy,belt-.15),(.18,.026,.052),.009,'Trim',nd)
        m.box((hx,hy+side*.018,belt-.14),(.13,.020,.018),'Chrome' if s['chrome'] else 'Wheel_steel',nd)
    # Side rubbing strips, small side markers, mirrors and windshield wipers.
    for side in [1,-1]:
        if kind!='micro':
            z=belt-.20
            intervals=sorted(set([rear+.10,front-.10]+[x for x in xs if rear+.10<x<front-.10]))
            for a,b in zip(intervals[:-1],intervals[1:]):
                if bottom((a+b)/2)>z: continue
                m.rod((a,side*(width(a)*.988+.008),z),(b,side*(width(b)*.988+.008),z),.013 if s['chrome'] else .024,'Chrome' if s['chrome'] else 'Trim',node_at((a+b)/2,side),4)
        mx=ab-.09; mz=belt+.13
        mirror_node=node_at(mx,side)
        m.rod((mx,side*w,mz-.05),(mx+.035,side*(w+.14),mz),.018,'Trim',mirror_node)
        m.bevel_box((mx+.015,side*(w+.18),mz+.025),(.16,.095,.11),.02,'Chrome' if s['chrome'] else 'Trim',mirror_node)
        m.box((mx-.069,side*(w+.18),mz+.025),(.006,.072,.078),'Reflector',mirror_node)
        m.box((front-.55,side*(width(front-.55)+.008),belt-.18),(.08,.015,.04),'Indicator',trim)
    for yy in [-w*.48,w*.34]:
        start=vec([ab+.013,yy,belt+.04]); end=vec([ab-(ab-at)*.30+.025,yy-.18,belt+(cabH-belt)*.30])
        m.rod(start,end,.009,'Trim',trim,5)
        m.rod(end+vec([-.06,-.17,.035]),end+vec([.06,.17,-.035]),.012,'Trim',trim,4)
    # Distinct front fascias: classic round lamps versus rectangular 80s units.
    lamp_z=belt-.18
    grille_width=W*.47 if kind=='micro' else W*.48
    if kind=='micro':
        m.bevel_box((front+.022,0,lamp_z-.08),(.035,.38,.10),.01,'Chrome',trim)
        m.rod((front+.02,0,lamp_z),(front+.04,0,lamp_z),.038,'Chrome',trim,12)
    else:
        m.bevel_box((front+.017,0,lamp_z),(.045,grille_width,.205),.015,'Trim',trim)
        for zz in np.linspace(lamp_z-.07,lamp_z+.07,5):
            m.box((front+.047,0,zz),(.012,grille_width-.05,.011),'Chrome' if s['chrome'] else 'Wheel_steel',trim)
        for yy in [-grille_width*.33,0,grille_width*.33]:
            m.box((front+.053,yy,lamp_z),(.013,.012,.15),'Trim',trim)
    for side in [1,-1]:
        ly=side*w*(.58 if kind=='micro' else .70)
        if kind in ('micro','pickup','sedan','wagon'):
            rad=.105 if kind=='micro' else .112
            m.rod((front+.008,ly,lamp_z),(front+.056,ly,lamp_z),rad+.021,'Chrome',trim,20)
            m.rod((front+.057,ly,lamp_z),(front+.069,ly,lamp_z),rad,'Headlamp',trim,20)
            for d in [-.045,0,.045]:
                half=math.sqrt(max(0,rad**2-d*d))*.83
                m.rod((front+.073,ly+d,lamp_z-half),(front+.073,ly+d,lamp_z+half),.003,'Plate',trim,4)
            m.bevel_box((front+.053,ly,lamp_z-.19),(.025,.18,.055),.009,'Indicator',trim)
        else:
            m.bevel_box((front+.03,ly,lamp_z),(.065,.29,.19),.02,'Chrome',trim)
            m.bevel_box((front+.067,ly,lamp_z),(.015,.25,.155),.01,'Headlamp',trim)
            for yy in np.linspace(ly-.09,ly+.09,5): m.box((front+.077,yy,lamp_z),(.004,.006,.13),'Plate',trim)
            m.box((front+.04,side*w*.91,lamp_z),(.05,.065,.15),'Indicator',trim)
        # Rear clusters, correct small period lamps.
        tz=belt-.20; tw=.18 if kind in ('van','delivery','pickup') else .27; th=.22 if kind in ('van','delivery') else .13
        tail_y=w*(.58 if kind=='micro' else .76)
        m.bevel_box((rear-.02,side*tail_y,tz),(.055,tw+.035,th+.035),.01,'Trim',trim)
        m.box((rear-.052,side*tail_y,tz),(.014,tw,th),'Tail_light',trim)
        m.box((rear-.062,side*(tail_y+tw*.25),tz+th*.23),(.009,tw*.42,th*.44),'Indicator',trim)
        m.box((rear-.063,side*(tail_y-tw*.27),tz-th*.20),(.009,tw*.32,th*.35),'Plate',trim)
    # Realistic tyres with chamfered shoulder and inset steel dish.
    for axle_i,axle in enumerate(wheelx):
        for side in [1,-1]:
            nd=m.node(('Wheel_FL' if side==1 else 'Wheel_FR') if axle_i==0 else ('Wheel_RL' if side==1 else 'Wheel_RR'),pivot=(axle,side*(w-.08),r))
            centre=vec([axle,side*(w-.08),r]); tireW=.19 if r<.32 else .225
            rings=[(-tireW/2,r*.89),(-tireW*.33,r),(tireW*.33,r),(tireW/2,r*.89)]
            N=24
            rr=[]
            for off,rad in rings:
                rr.append([centre+vec([rad*math.sin(t),off,rad*math.cos(t)]) for t in np.arange(N)*2*math.pi/N])
            for a,b in zip(rr[:-1],rr[1:]):
                for i in range(N):
                    j=(i+1)%N; normal=(a[i]+a[j]+b[j]+b[i])/4-centre; normal[1]=0
                    m.polygon([a[i],a[j],b[j],b[i]],'Rubber',nd,normal)
            # Tyre sidewall annulus on both faces.
            rimrad=r*.57
            for ts in [1,-1]:
                y=centre[1]+ts*tireW/2
                out=[vec([axle+r*.89*math.sin(t),y,r+r*.89*math.cos(t)]) for t in np.arange(N)*2*math.pi/N]
                inn=[vec([axle+rimrad*math.sin(t),y,r+rimrad*math.cos(t)]) for t in np.arange(N)*2*math.pi/N]
                for i in range(N):
                    j=(i+1)%N; m.polygon([out[i],out[j],inn[j],inn[i]],'Rubber',nd,[0,ts,0])
                m.rod((axle,y-ts*.023,r),(axle,y+ts*.005,r),rimrad,'Wheel_steel',nd,24)
                m.rod((axle,y+ts*.006,r),(axle,y+ts*.014,r),rimrad*.84,'Chrome' if s['chrome'] else 'Wheel_steel',nd,24)
                m.rod((axle,y+ts*.015,r),(axle,y+ts*.035,r),rimrad*.43,'Chrome' if s['chrome'] else 'Trim',nd,16)
                for t in np.arange(8)*2*math.pi/8:
                    hx=axle+rimrad*.65*math.sin(t); hz=r+rimrad*.65*math.cos(t)
                    m.rod((hx,y+ts*.016,hz),(hx,y+ts*.018,hz),.017,'Trim',nd,7)
                for t in np.arange(4)*2*math.pi/4:
                    hx=axle+rimrad*.28*math.sin(t); hz=r+rimrad*.28*math.cos(t)
                    m.rod((hx,y+ts*.036,hz),(hx,y+ts*.045,hz),.009,'Wheel_steel',nd,6)
    # Simple usable cabin interior (glazing deliberately opaque for cheap rendering).
    seatx=ab-.63
    for yy in [-w*.46,w*.46]:
        m.bevel_box((seatx,yy,.62),(.50,W*.36,.16),.055,'Seat_fabric',inside)
        m.bevel_box((seatx-.24,yy,.88),(.13,W*.36,.48),.055,'Seat_fabric',inside)
        if kind not in ('micro','pickup'):
            m.bevel_box((seatx-.24,yy,1.14),(.12,.24,.16),.04,'Seat_fabric',inside)
        for yy2 in [-.10,0,.10]: m.rod((seatx-.31,yy+yy2,.75),(seatx-.31,yy+yy2,1.05),.006,'Interior',inside,4)
    if kind in ('sedan','wagon','coupe','hatch','micro'):
        m.bevel_box((rb+.50,0,.60),(.43,W-.28,.17),.04,'Seat_fabric',inside)
        m.bevel_box((rb+.32,0,.81),(.12,W-.28,.38),.04,'Seat_fabric',inside)
    m.bevel_box((ab-.06,0,belt-.08),(.28,W-.17,.18),.03,'Interior',inside)
    # Left-hand steering wheel, visible when doors are opened.
    sc=vec([ab-.37,w*.44,belt+.015])
    points=[sc+vec([0,.145*math.cos(t),.145*math.sin(t)]) for t in np.linspace(0,2*math.pi,21)]
    m.line(points,.015,'Trim',inside)
    for t in [0,2.1,4.2]: m.rod(sc,sc+vec([0,.13*math.cos(t),.13*math.sin(t)]),.012,'Chrome',inside)
    m.rod(sc,sc+vec([.24,0,-.10]),.022,'Trim',inside)
    m.rod((ab-.5,0,.52),(ab-.57,0,.80),.012,'Trim',inside)
    m.bevel_box((ab-.57,0,.80),(.045,.045,.045),.01,'Trim',inside)
    # Characteristic body-specific additions.
    if kind=='pickup':
        # Open bed with separate tailgate, inner walls and stamped steel floor.
        bedfront=rb-.07; bedback=rear+.09; bedz=.68
        m.box(((bedfront+bedback)/2,0,bedz),(bedfront-bedback,W-.28,.075),'Paint_dark',shell)
        for side in [1,-1]:
            m.box(((bedfront+bedback)/2,side*(w-.095),.91),(bedfront-bedback,.11,.38),'Paint',shell)
            m.bevel_box(((bedfront+bedback)/2,side*(w-.08),1.115),(bedfront-bedback,.14,.065),.015,'Paint',shell)
        m.box((bedfront,0,.91),(.075,W-.18,.43),'Paint',shell)
        for yy in np.linspace(-w+.22,w-.22,9): m.box(((bedfront+bedback)/2,yy,bedz+.045),(bedfront-bedback-.08,.025,.018),'Paint',shell)
        m.box((rear+.035,0,.91),(.07,W-.13,.40),'Paint',backpanel)
        for yy in np.linspace(-w+.22,w-.22,5): m.box((rear-.006,yy,.91),(.022,.045,.25),'Paint_dark',backpanel)
        m.box((rear-.026,0,1.06),(.03,.18,.04),'Chrome',backpanel)
    if kind=='delivery':
        # Tall rectangular cargo pod, clearly taller/wider than the small front cabin.
        start=rb+.04; end=rear+.025; cw=w*.99
        m.bevel_box(((start+end)/2,0,(H+belt)/2),(start-end,W*.98,H-belt),.07,'Paint',shell)
        for side in [1,-1]:
            yy=side*(cw+.002)
            m.line([(end+.16,yy,belt+.10),(start-.12,yy,belt+.10),(start-.12,yy,H-.18),(end+.16,yy,H-.18),(end+.16,yy,belt+.10)],.009,'Paint_dark',shell)
            for zz in [belt+.09,H-.12]: m.line([(end+.10,yy,zz),(start-.08,yy,zz)],.01,'Paint_dark',shell)
        m.line([(rear-.014,0,belt),(rear-.014,0,H-.10)],.01,'Trim',backpanel)
        for side in [1,-1]:
            m.box((rear-.03,side*.07,1.27),(.035,.035,.15),'Trim',backpanel)
            for zz in [1.13,1.62]: m.box((end-.012,side*w*.86,zz),(.035,.07,.12),'Chrome',trim)
    if kind=='van':
        # Roof pressed ribs, long sliding-door reveal, lower rear vents.
        for yy in [-.52,-.26,0,.26,.52]: m.bevel_box(((at+rt)/2,yy,H-.007),(at-rt-.38,.035,.025),.008,'Paint_dark',shell)
        for side in [1,-1]:
            m.line([(-1.67,side*(w+.01),belt-.10),(.09,side*(w+.01),belt-.10),(.09,side*(w+.01),H-.22)],.009,'Paint_dark',shell)
            m.box((-.10,side*(w+.025),belt+.13),(.035,.026,.16),'Trim',trim)
        for i in range(5): m.box((front-.18+i*.032,0,belt+.004),(.011,.20,.008),'Trim',hood)
    if kind=='wagon':
        for side in [1,-1]:
            # Two low longitudinal luggage rails with short feet.
            for x in [-1.45,.02]: m.rod((x,side*.48,H),(x,side*.48,H+.08),.017,'Chrome',trim)
            m.rod((-1.55,side*.48,H+.08),(.14,side*.48,H+.08),.021,'Chrome',trim)
    if kind=='coupe':
        m.bevel_box((rear+.22,0,belt+.14),(.22,W*.92,.06),.015,'Trim',backpanel)
        for side in [1,-1]:
            m.box((rear+.22,side*.49,belt+.09),(.07,.055,.09),'Trim',backpanel)
            m.line([(rear+.15,side*(w+.006),belt-.055),(front-.18,side*(w+.006),belt-.055)],.02,'Trim',trim)
    if kind=='micro':
        for j in range(8): m.box((rear+.19+j*.07,0,top(rear+.19+j*.07)+.024),(.014,.48,.012),'Trim',backpanel)
        m.rod((front+.04,-.22,lamp_z-.07),(front+.04,.22,lamp_z-.07),.013,'Chrome',trim)
    # Exhaust; towing eye; suspension axle detail.
    m.rod((rear+.35,-w*.61,.27),(rear-.09,-w*.61,.26),.028,'Wheel_steel',shell,10)
    for axle in wheelx: m.rod((axle,-w+.14,r),(axle,w-.14,r),.035,'Trim',shell,8)
    # Inner door faces remain visible when the hinged doors are opened.
    for _,_,_,nd in door_ranges:
        for material_index in [0,4]:
            data=m.groups.get((nd,material_index))
            if not data: continue
            points,normals=np.array(data[0]),np.array(data[1])
            for i in range(0,len(points),3):
                p=points[i:i+3]-normals[i]*.008
                m.polygon(p[::-1],'Interior' if material_index==0 else 'Glass',nd,-normals[i])
    m.meta.update(id=s['id'],display_name=s['name'],dimensions_m={'length':L+.25,'width':W+.46,'height':H+(.10 if kind=='wagon' else 0)},wheel_radius_m=r,wheelbase_m=wb,forward_axis='-Z',up_axis='+Y',units='meters',reference_style=kind,collision_box_m=[W-.08,H-.32,L-.1],door_nodes=[m.nodes[n]['name'] for _,_,_,n in door_ranges],notes='Original stylized geometry; opaque glass; no UV textures or driving controller.')
    m.export(MODELS/(s['id']+'.glb'))
    return m.meta

if __name__=='__main__':
    manifest=[build(s) for s in SPECS]
    (ROOT/'manifest.json').write_text(json.dumps(manifest,indent=2))
    print(json.dumps(manifest,indent=2))
