"""Predeclared reduced-budget ADMM training screen; no held-out policy selection."""
from pathlib import Path
import sys,json,time
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT))
from scripts.v4.diagnose_k8_quality import fixture,solve,assess,digest
from scripts.v4.diagnose_k8_quantization_policy import configured
from scripts.v4.k8_exact_integer_acceleration import enabled

def main():
    paths=[Path(__file__).resolve()]+[ROOT/'scripts/v4'/p for p in ('diagnose_k8_quality.py','diagnose_k8_quantization_policy.py','k8_exact_integer_acceleration.py')]+sorted((ROOT/'models/v4').glob('*.py'))
    before={p.relative_to(ROOT).as_posix():digest(p) for p in paths}
    out=ROOT/'reports/v4/k8_quality_policy_20260909/admm_short_training';out.mkdir(parents=True,exist_ok=True)
    rows=[];chosen=None
    for budget in (16,32,64):
        candidates=[]
        for seed in (4101,4102,4103,4104):
            a,y,x,meta=fixture(64,256,seed);p=configured(a,'ADMM',budget)
            q=assess(solve('ADMM',a,y,p),a,y,x,p)
            row=dict(budget=budget,seed=seed,floating=q);rows.append(row);candidates.append((a,y,x,p,row))
            print(json.dumps(row),flush=True)
        if min(row['floating']['snr_db'] for *_,row in candidates)<25:continue
        passing=True
        for a,y,x,p,row in candidates:
            with enabled():q=assess(solve('ADMM',a,y,p,True),a,y,x,p)
            row['fixed']=q;row['nmse_ratio']=q['nmse']/row['floating']['nmse']
            passing &= q['snr_db']>=25 and row['nmse_ratio']<=1.1 and not any(q['events'].values())
            print(json.dumps(row),flush=True)
            (out/'progress.json').write_bytes((json.dumps(rows,indent=2)+'\n').encode())
        if passing:chosen=budget;break
    assert before=={p.relative_to(ROOT).as_posix():digest(p) for p in paths}
    (out/'report.json').write_bytes((json.dumps(dict(rows=rows,chosen_budget=chosen,source_stable=True,source_sha256=before,selection='First16/32/64 budget with all training4101..4104 fixed+float>=25dB and NMSE ratio<=1.1; heldout10001/10002 reserved after selection.'),indent=2)+'\n').encode())
    for p in paths:
        dest=out/'sources'/p.relative_to(ROOT);dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(p.read_bytes())

if __name__=='__main__':main()
