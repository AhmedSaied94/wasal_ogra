import json, re, os, sys, glob
OUT=sys.argv[1]; T=json.load(open(sys.argv[2] if len(sys.argv)>2 else os.path.join(OUT,'tokens.json')))
rev={}
def add(name,val):
    if isinstance(val,str) and val.startswith('#'): rev.setdefault(val.upper(),name)
for k,v in T['color'].items(): add(k,v)
for k,v in T['dashboard'].items(): add('dashboard.'+k,v)
for i,s in enumerate(T['station']): add(f'station[{i}]',s['bg'])
for k,v in T['scene'].items(): add('scene.'+k,v)
for k,v in T['money_note'].items(): add(f'money_note.{k}.bg',v['bg']); add(f'money_note.{k}.lip',v['lip'])
for k,v in T['denomination'].items(): add(f'denomination.{k}',v['bg'])
for i,v in enumerate(T['character']['skin']): add(f'character.skin[{i}]',v)
def hx(m):
    r,g,b=int(m.group(1)),int(m.group(2)),int(m.group(3)); a=m.group(4)
    h='#%02X%02X%02X'%(r,g,b)
    if a is not None and float(a)<1: return f'{h}@{float(a):g}'
    return h
rgb=re.compile(r'rgba?\((\d+),\s*(\d+),\s*(\d+)(?:,\s*([\d.]+))?\)')
def conv(v): return rgb.sub(hx,v) if isinstance(v,str) else v
for f in glob.glob(os.path.join(OUT,'boxes','*.json')):
    d=json.load(open(f))
    for b in d['boxes']:
        for k in ('bg','color','shadow','border'):
            if k in b:
                b[k]=conv(b[k])
                if k in('bg','color'):
                    t=rev.get(b[k].split('@')[0]); 
                    if t and '@' not in b[k]: b[k]=f'{b[k]} {t}'
        if 'shadow' in b:
            # "#C7DDEA 0px 5px 0px 0px" -> "0 5 0 #C7DDEA"
            parts=[]
            for sh in re.split(r',\s*(?=#|inset)',b['shadow']):
                m=re.match(r'(inset\s+)?(#[0-9A-F]{6}(?:@[\d.]+)?)\s+(-?[\d.]+)px\s+(-?[\d.]+)px\s+(-?[\d.]+)px\s+(-?[\d.]+)px(\s+inset)?',sh.strip())
                if m:
                    ins='inset ' if (m.group(1) or m.group(7)) else ''
                    parts.append(f"{ins}{m.group(3)} {m.group(4)} {m.group(5)} {m.group(6)} {m.group(2)}")
                else: parts.append(sh)
            b['shadow']=', '.join(parts)
    json.dump(d,open(f,'w'),ensure_ascii=False,separators=(',',':'))
print('post-processed')
