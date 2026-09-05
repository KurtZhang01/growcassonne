"""Generate board-aligned vector elevations from a shared architectural coordinate system."""
import math
from pathlib import Path
from html import escape

OUT = Path(__file__).resolve().parent
YAW, PITCH = math.radians(42), math.radians(42)
SCALE = 180
NAMES = {
    'hongshan': '洪山科创大厦', 'gate': '校园牌坊',
    'campus': '低层创新园区', 'redhall': '红砖山墙楼',
    'arena': '白色拱顶场馆', 'office': '白色框架办公楼',
}


class Drawing:
    def __init__(self, turn):
        self.turn = turn
        self.faces = []

    def rotate(self, p):
        x, y, z = p
        for _ in range(self.turn):
            x, z = -z, x
        return x, y, z

    def point(self, p):
        x, y, z = self.rotate(p)
        return (380 + SCALE * (math.cos(YAW) * x - math.sin(YAW) * z),
                486 + SCALE * (math.sin(PITCH) * (math.sin(YAW) * x + math.cos(YAW) * z) - math.cos(PITCH) * y))

    def depth(self, p):
        x, y, z = self.rotate(p)
        return math.cos(PITCH) * (math.sin(YAW) * x + math.cos(YAW) * z) + math.sin(PITCH) * y

    def poly(self, points, color, stroke='none', width=0):
        coords = ' '.join('%.2f,%.2f' % self.point(p) for p in points)
        return f'<polygon points="{coords}" fill="{color}" stroke="{stroke}" stroke-width="{width}" stroke-linejoin="round"/>'

    def add(self, points, color, extra=''):
        self.faces.append((sum(map(self.depth, points)) / len(points), self.poly(points, color) + extra))

    def face(self, a, b, bottom, height, color, cols=0, rows=0, label=''):
        # Visible wall normals are computed after rotation; hidden elevations never leak through.
        dx, dz = b[0]-a[0], b[1]-a[1]
        normal = self.rotate((dz, 0, -dx))
        if normal[0]*math.sin(YAW) + normal[2]*math.cos(YAW) <= 0:
            return
        def p(u, v):
            return (a[0]+dx*u, bottom+height*v, a[1]+dz*u)
        extra = ''
        # Two flat wall tones match the board's solid-color meshes and directional light.
        if normal[0] > 0:
            rgb = tuple(int(color[i:i+2],16) for i in (1,3,5))
            color = '#%02x%02x%02x' % tuple(int(c*.78) for c in rgb)
        if cols and rows:
            cols, rows = min(cols, 5), min(rows, 8)
            for r in range(rows):
                for c in range(cols):
                    u, v = (c+.17)/cols, (r+.17)/rows
                    w, h = .66/cols, .66/rows
                    extra += self.poly([p(u,v),p(u+w,v),p(u+w,v+h),p(u,v+h)],
                                       '#527c89' if normal[0] > 0 else '#7197a0', 'none', 0)
        if label and math.hypot(dx,dz) > .25:
            # Map readable lettering to the actual wall plane, including its slope.
            l, r = p(.06,.17), p(.94,.17)
            if self.point(l)[0] > self.point(r)[0]:
                l, r = r, l
            x0,y0 = self.point(l); x1,y1 = self.point(r)
            length = x1-x0
            extra += f'<g transform="matrix({length/180:.5f} {(y1-y0)/180:.5f} 0 1 {x0:.2f} {y0:.2f})"><rect y="-18" width="180" height="25" fill="#f4f5fb" stroke="#9aa5bb"/><text x="90" y="0" text-anchor="middle" fill="#4d5c94" font-family="Microsoft YaHei, sans-serif" font-size="17">{escape(label)}</text></g>'
        self.add([p(0,0),p(1,0),p(1,1),p(0,1)], color, extra)

    def box(self, x,z,w,d,y,h, wall='#b8c0b9', roof='#d4d9cf', cols=0,rows=0,label=''):
        pts = [(x,z),(x+w,z),(x+w,z+d),(x,z+d)]
        for i in range(4):
            self.face(pts[i],pts[(i+1)%4],y,h,wall,cols,rows,label)
        self.add([(a,y+h,b) for a,b in pts],roof)

    def gable(self,x,z,w,d,y,rise,color='#b77978',roof=('#dee2ec','#ececf5')):
        a,b,c,e = (x,y,z),(x+w,y,z),(x+w,y,z+d),(x,y,z+d)
        r1,r2 = (x+w/2,y+rise,z),(x+w/2,y+rise,z+d)
        self.add([a,b,r1],color); self.add([e,r2,c],color)
        self.add([a,r1,r2,e],roof[0]); self.add([r1,b,c,r2],roof[1])

    def tree(self,x,z,pink=False):
        self.box(x-.018,z-.018,.036,.036,.06,.21,'#969392','#aaa0a1')
        cx,cy=self.point((x,.34,z))
        colors = ['#f3d7e7','#e4bed5','#f7e4ee'] if pink else ['#a6c799','#84ae85','#c0d7a3']
        parts=''
        for dx,dy,r,c in [(-9,0,12,0),(9,-2,11,1),(0,-12,13,2),(0,5,10,0)]:
            parts+=f'<circle cx="{cx+dx:.2f}" cy="{cy+dy:.2f}" r="{r}" fill="{colors[c]}" stroke="#a6a4b4" stroke-width=".7"/>'
        self.faces.append((self.depth((x,.34,z)),parts))

    def render(self, kind):
        self.box(-1.12,-.64,2.24,1.28,-.07,.12,'#737c70','#a8b29a')
        if kind=='hongshan':
            self.box(-.79,-.36,.69,.69,.06,1.74,cols=10,rows=23)
            self.box(-.81,-.38,.73,.73,1.80,.045)
            self.box(-.74,-.31,.59,.59,1.845,.075,cols=12,rows=1)
            self.box(-.76,-.33,.63,.63,1.92,.024)
            self.box(-.1,-.36,1.0,.60,.06,.43,cols=10,rows=5)
            self.box(-.12,-.38,1.04,.64,.49,.025)
            self.box(-.87,.49,.77,.035,.07,.18,label=NAMES[kind])
        elif kind=='gate':
            for x in [-.88,-.37,.37,.88]:
                self.box(x-.045,-.075,.09,.15,.06,1.0)
                self.box(x-.06,-.09,.12,.18,1.06,.05)
            for x,w,y in [(-.88,.51,.66),(-.37,.74,.86),(.37,.51,.66)]:
                self.box(x,-.075,w,.15,y,.14,label='国立武汉大学' if w>.6 else '')
                self.gable(x-.05,-.12,w+.10,.24,y+.14,.055,'#7b9d91',('#779f94','#98b9a8'))
        elif kind=='campus':
            for x,z,w,d,h in [(-.90,-.45,.54,.45,.59),(-.18,-.46,.47,.43,.74),(.45,-.44,.50,.55,.58),(-.80,.19,.64,.32,.38),(.04,.17,.76,.32,.33)]:
                self.box(x,z,w,d,.06,h,cols=4,rows=3)
                self.box(x-.02,z-.02,w+.04,d+.04,h+.06,.025)
                self.box(x+.07,z+.07,w-.14,d-.14,h+.085,.028,roof='#b1cba6')
        elif kind=='redhall':
            self.box(-.94,-.34,1.88,.70,.06,.58,wall='#c58b88',cols=12,rows=3)
            self.box(-.97,-.37,1.94,.76,.64,.025,roof='#c9cbd9')
            self.box(-.23,-.36,.46,.77,.06,.78,wall='#b86e72',cols=3,rows=4)
            self.gable(-.255,-.385,.51,.82,.84,.22)
            for x in [-.86,-.62,-.38,.34,.58,.82]:
                self.box(x,.37,.035,.04,.06,.67,wall='#b96f76')
            # Circular emblem on the central pediment, projected with its wall.
            circle=[(.083*math.cos(t*math.tau/32),.87+.083*math.sin(t*math.tau/32),.413) for t in range(32)]
            normal=self.rotate((0,0,1))
            if normal[0]*math.sin(YAW)+normal[2]*math.cos(YAW)>0:
                self.add(circle,'#e9edf7')
        elif kind=='arena':
            self.box(-.96,-.44,1.92,.88,.06,.36,cols=14,rows=3)
            # Barrel roof sampled in shared 3D coordinates, with continuous ribs.
            for i in range(24):
                t0,t1=math.pi*i/24,math.pi*(i+1)/24
                a=(-.96,.42+.36*math.sin(t0),.44*math.cos(t0))
                b=(-.96,.42+.36*math.sin(t1),.44*math.cos(t1))
                c=(.96,b[1],b[2]); d=(.96,a[1],a[2])
                self.add([a,b,c,d], '#f5f3fa' if i%3 else '#e4e3ef')
            for x in [-.96,-.64,-.32,0,.32,.64,.96]:
                points=[(x,.425+.36*math.sin(math.pi*i/24),.442*math.cos(math.pi*i/24)) for i in range(25)]
                coords=' '.join('%.2f,%.2f'%self.point(p) for p in points)
                self.faces.append((self.depth((x,.70,0)),f'<polyline points="{coords}" fill="none" stroke="#c7c9d8" stroke-width="2"/>'))
        elif kind=='office':
            self.box(-.85,-.38,1.7,.76,.06,.90,cols=12,rows=7)
            self.box(-.88,-.41,1.76,.82,.96,.04)
            self.box(-.73,-.26,1.46,.52,1.0,.025,roof='#bec8db')
        for x,z in [(-.99,.51),(.98,-.50),(.97,.50)]:
            self.tree(x,z,True)
        body=''.join(s for _,s in sorted(self.faces,key=lambda item:item[0]))
        return f'<svg xmlns="http://www.w3.org/2000/svg" width="760" height="640" viewBox="0 0 760 640"><title>{NAMES[kind]} / rotation {self.turn*90}</title>{body}</svg>'


if __name__=='__main__':
    target=OUT/'isometric'
    target.mkdir(exist_ok=True)
    for kind in NAMES:
        for turn in range(4):
            (target/f'{kind}-{turn}.svg').write_text(Drawing(turn).render(kind),encoding='utf-8')
    # Retain the earlier direct preview links as aliases to properly projected views.
    (OUT/'hongshan-tower-axis-x.svg').write_text(Drawing(0).render('hongshan'),encoding='utf-8')
    (OUT/'hongshan-tower-axis-z.svg').write_text(Drawing(1).render('hongshan'),encoding='utf-8')
    print('Generated 24 vector elevations, fixed 42-degree camera projection, 760 x 640.')
