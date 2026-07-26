import re, pathlib, json
root=pathlib.Path('CSCGRA.srcs/sources_1/new')
rtl_files=sorted(root.glob('*.v')) + sorted(root.glob('*.vh'))
texts={p:p.read_text(errors='ignore') for p in rtl_files}
modules={}
for p,t in texts.items():
    for m in re.finditer(r'(?m)^\s*module\s+([A-Za-z_][A-Za-z0-9_$]*)\b', t):
        modules[m.group(1)]=str(p)
inst=[]
for p,t in texts.items():
    # strip comments roughly
    s=re.sub(r'/\*.*?\*/','',t,flags=re.S)
    s=re.sub(r'//.*','',s)
    for mod in modules:
        # instance: mod #( ... ) name ( OR mod name (
        pat=re.compile(r'(?m)^\s*'+re.escape(mod)+r'\s*(?:#\s*\(|[A-Za-z_][A-Za-z0-9_$]*\s*\()')
        for m in pat.finditer(s):
            if re.search(r'(?m)^\s*module\s+'+re.escape(mod)+r'\b', s[max(0,m.start()-20):m.start()+50]):
                continue
            line=s.count('\n',0,m.start())+1
            inst.append((mod,str(p),line))
used=set(m for m,_,__ in inst)
print('ALL_MODULES')
for mod,path in sorted(modules.items()): print(f'{mod}\t{path}')
print('\nINSTANTIATED')
for mod,p,l in sorted(inst): print(f'{mod}\t{p}:{l}')
print('\nDEFINED_NOT_INSTANTIATED')
for mod,path in sorted(modules.items()):
    if mod not in used and mod not in ('cgra_soc_top','cgra_top'):
        print(f'{mod}\t{path}')
