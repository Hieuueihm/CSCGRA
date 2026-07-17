import re, pathlib, collections
log=pathlib.Path('synth_peop_opt_cgra_top.log').read_text(errors='ignore')
pat=re.compile(r'WARNING: \[Synth 8-6014\] Unused sequential element (.*?) was removed\.\s+\[(.*?):(\d+)\]')
by=collections.defaultdict(list)
for name,file,line in pat.findall(log):
    by[file].append((int(line),name))
for file,items in sorted(by.items()):
    print('\n'+file)
    for line,name in sorted(set(items))[:120]:
        print(f'  {line}: {name}')
pat2=re.compile(r'WARNING: \[Synth 8-3848\] Net (.*?) .*?\[(.*?):(\d+)\]')
print('\nNO_DRIVER')
for name,file,line in pat2.findall(log): print(f'{file}:{line}: {name}')
