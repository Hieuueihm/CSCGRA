"""Strict factor-panel fair comparison; panel images may change, math may not."""
import argparse, hashlib, json
from pathlib import Path

ACTIVE=('MP','GP','IHT','OMP','GOMP','CoSaMP','SP','HTP','FISTA','PDHG')
QR={'OMP','GOMP','CoSaMP','SP','HTP'}
IDENTITY=('rows','columns','requested_sparsity','requested_outer_iterations','outer_iterations',
 'raw_phi_sha256','raw_y_sha256','policy','output_raw_x_sha256','output_raw_r_sha256',
 'status','accepted_support','inner_iterations','fixed_numeric_events','fixed_model_trace','fixed_solver_trace',
 'solver_invocations','solver_solve_count','solver_refinement_count','maximum_ls_support','total_committed_inner_iterations')
class ValidationError(ValueError): pass

def read(path):
 p=Path(path); p=p/'summary.json' if p.is_dir() else p
 if not p.is_file(): raise ValidationError(f'missing summary: {p}')
 try: return p.resolve(),json.loads(p.read_text(encoding='utf-8'))
 except json.JSONDecodeError as e: raise ValidationError(f'invalid JSON {p}: {e}')
def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def clean(s,label):
 if s.get('status')!='PASS': raise ValidationError(f'{label}: status must be PASS')
 if s.get('changed_sources')!=[] or s.get('untracked_imports')!=[]: raise ValidationError(f'{label}: source closure is not clean')
 if not (s.get('source_sha256') or s.get('source_manifests')): raise ValidationError(f'{label}: missing source provenance')
def load_digest(case,label,archive_root=None):
 value=case.get('load_image_sha256',case.get('load_sha256'))
 if archive_root is None:
  if not isinstance(value,str) or len(value)!=64: raise ValidationError(f'{label}: missing load_image_sha256 (package metadata hash is not executable-image evidence)')
  return value
 package_sha=case.get('package_sha256')
 if not isinstance(package_sha,str) or len(package_sha)!=64: raise ValidationError(f'{label}: missing package_sha256 for artifact lookup')
 matches=[]
 for package_path in Path(archive_root).rglob('package.json'):
  if sha(package_path)==package_sha: matches.append(package_path)
 if len(matches)!=1: raise ValidationError(f'{label}: package artifact match count {len(matches)}')
 package=json.loads(matches[0].read_text(encoding='utf-8'))
 if package.get('algorithm')!=case.get('algorithm'): raise ValidationError(f'{label}: package algorithm mismatch')
 load_path=matches[0].with_name('load.txt')
 if not load_path.is_file(): raise ValidationError(f'{label}: package missing load.txt')
 actual=hashlib.sha256(load_path.read_text(encoding='utf-8').replace('\r\n','\n').encode('utf-8')).hexdigest()
 if package.get('load_sha256')!=actual: raise ValidationError(f'{label}: embedded load_sha256 does not match normalized load.txt')
 if value is not None and value!=actual: raise ValidationError(f'{label}: summary load digest disagrees with artifact')
 return actual
def cases(summary,label,rows,archive_root=None):
 clean(summary,label); cfg=summary.get('config',{})
 if cfg.get('rows')!=rows or cfg.get('sparsity')!=8 or cfg.get('outer')!=8: raise ValidationError(f'{label}: expected M{rows}/K8/outer8')
 out={}
 for c in summary.get('cases',[]):
  a=c.get('algorithm')
  if a in out or a not in ACTIVE+('ADMM',): raise ValidationError(f'{label}: invalid algorithm {a!r}')
  missing=[x for x in IDENTITY if x not in c]
  if missing: raise ValidationError(f'{label}/{a}: missing {missing}')
  if c['rows']!=rows or c['columns']!=(64 if rows==32 else 256) or c['requested_sparsity'] not in (8,None) or len(c.get('planted_support',[]))!=8 or c['requested_outer_iterations']!=8 or c['outer_iterations']!=8: raise ValidationError(f'{label}/{a}: geometry/K/outer mismatch')
  if not isinstance(c.get('job_cycles'),int) or c['job_cycles']<=0: raise ValidationError(f'{label}/{a}: invalid cycles')
  if not isinstance(c.get('quality',{}).get('fixed',{}).get('snr_db'),(int,float)): raise ValidationError(f'{label}/{a}: missing fixed SNR')
  load_digest(c,f'{label}/{a}',archive_root); out[a]=c
 if set(ACTIVE)-set(out): raise ValidationError(f'{label}: missing active cases {sorted(set(ACTIVE)-set(out))}')
 return out
def physical(c):
 q=c.get('cycle_profile',{}).get('service_totals',{}).get('KERNEL:13')
 if c['algorithm'] not in QR: return 0
 if not isinstance(q,dict) or not isinstance(q.get('calls'),int) or q['calls']<=0: raise ValidationError(f"{c['algorithm']}: invalid physical KERNEL:13 calls")
 return q['calls']
def compare(old,new,rows,a,old_root=None,new_root=None):
 bad=[x for x in IDENTITY if old[x]!=new[x]]
 if bad: raise ValidationError(f'M{rows}/{a}: changed mathematical evidence {bad}')
 if old['quality']!=new['quality']: raise ValidationError(f'M{rows}/{a}: changed quality')
 if physical(old)!=physical(new): raise ValidationError(f'M{rows}/{a}: changed physical FACTOR_INIT')
 oldload,newload=load_digest(old,f'M{rows}/{a}/old',old_root),load_digest(new,f'M{rows}/{a}/new',new_root)
 panel=a in QR and oldload!=newload
 if a not in {'GOMP','CoSaMP','SP'} and oldload!=newload: raise ValidationError(f'M{rows}/{a}: load image changed outside permitted panel algorithms')
 quality_scope=old['quality'].get('scope','fixed8 diagnostic; no application threshold claim')
 return dict(algorithm=a,old_job_cycles=old['job_cycles'],new_job_cycles=new['job_cycles'],reduction_percent=(old['job_cycles']-new['job_cycles'])*100/old['job_cycles'],actual_outer=8,quality_before=old['quality'],quality_after=new['quality'],quality_scope=quality_scope,quality_threshold='diagnostic_only',factor_calls=physical(old),max_qr_support=old['maximum_ls_support'],ls_solves=old['solver_solve_count'],ls_refinements=old['solver_refinement_count'],inner_iterations=old['total_committed_inner_iterations'],program_length_before=old.get('program_length'),program_length_after=new.get('program_length'),template_count_before=old.get('template_count'),template_count_after=new.get('template_count'),load_record_count_before=old.get('load_record_count'),load_record_count_after=new.get('load_record_count'),retired_before=old.get('retired_instructions'),retired_after=new.get('retired_instructions'),load_image_before=oldload,load_image_after=newload,panel_image_changed=panel)
def geometry_files(old,new,rows,old_root=None,new_root=None):
 before=cases(old,f'baseline M{rows}',rows,old_root); after=cases(new,f'candidate M{rows}',rows,new_root)
 # ADMM is historical baseline evidence only; candidate must not smuggle it into active output.
 if 'ADMM' in after: raise ValidationError(f'M{rows}: candidate ADMM must remain excluded')
 return dict(rows=rows,rows_output=[compare(before[a],after[a],rows,a,old_root,new_root) for a in ACTIVE],baseline_admm_excluded='ADMM' in before)
def geometry(oldp,newp,rows):
 op,old=read(oldp); np,new=read(newp); result=geometry_files(old,new,rows,op.parent,np.parent); result.update(baseline_summary_sha256=sha(op),candidate_summary_sha256=sha(np)); return result
def render(result):
 lines=['# So sánh factor-panel (fixed K=8, outer thực tế=8)','', 'Phạm vi: M=32,N=64,K=8 và M=64,N=256,K=8. Đây là đo chu kỳ, không phải xác nhận chất lượng 20 dB. Mỗi cặp phải cùng Phi/Y thô, precision, policy và outer thực tế=8.', '', 'Các bảng V2/V3 chỉ là neo lịch sử theo [CYCLE_BASELINE_CONTRACT.md](../../../docs/v4/architecture/CYCLE_BASELINE_CONTRACT.md); báo cáo không tạo tỷ lệ speedup chéo phiên bản vì boundary thực thi không đồng nhất. Không có tuyên bố PPA, timing hoặc tài nguyên.','']
 for g in result['geometries']:
  lines += [f"## M={g['rows']}", '', '### Chu kỳ và solver', '', '| Thuật toán | Chu kỳ cũ | Chu kỳ mới | Giảm % | outer | QR max S | LS/refine | FACTOR_INIT |','|---|---:|---:|---:|---:|---:|---:|---:|']
  lines += [f"| {r['algorithm']} | {r['old_job_cycles']} | {r['new_job_cycles']} | {r['reduction_percent']:.2f} | {r['actual_outer']} | {r['max_qr_support']} | {r['ls_solves']}/{r['ls_refinements']} | {r['factor_calls']} |" for r in g['rows_output']]
  lines += ['', '### Chất lượng fixed8', '', 'Giá trị trước/sau bằng nhau được validator kiểm tra trong JSON. Đây là chỉ số diagnostic fixed8, không phải held-out application qualification.', '', '| Thuật toán | Fixed SNR (dB) | Float SNR (dB) | Loss (dB) | NMSE ratio | Threshold |','|---|---:|---:|---:|---:|---|']
  for r in g['rows_output']:
   q=r['quality_after']; fixed=q.get('fixed',{}).get('snr_db'); floating=q.get('floating',{}).get('snr_db'); loss=q.get('snr_loss_db'); ratio=q.get('nmse_ratio')
   threshold='PASS' if isinstance(fixed,(int,float)) and isinstance(floating,(int,float)) and fixed>=20 and floating>=20 and (loss is None or loss<=0.5) and (ratio is None or ratio<=1.1) else 'FAIL'
   fmt=lambda v,n: '—' if v is None else f'{v:.{n}f}'
   lines.append(f"| {r['algorithm']} | {fmt(fixed,3)} | {fmt(floating,3)} | {fmt(loss,3)} | {fmt(ratio,6)} | {threshold} |")
  lines += ['', '### Ảnh chương trình', '', '| Thuật toán | Program cũ→mới | Template cũ→mới | Load records cũ→mới | Retired cũ→mới | Panel image đổi |','|---|---:|---:|---:|---:|---|']
  lines += [f"| {r['algorithm']} | {r['program_length_before']}→{r['program_length_after']} | {r['template_count_before']}→{r['template_count_after']} | {r['load_record_count_before']}→{r['load_record_count_after']} | {r['retired_before']}→{r['retired_after']} | {'có' if r['panel_image_changed'] else 'không'} |" for r in g['rows_output']]
  lines += ['', 'ADMM chỉ xuất hiện trong archive baseline như hàng lịch sử bị loại khỏi phạm vi active; báo cáo không yêu cầu hoặc gán kết quả ADMM mới.','']
 return '\n'.join(lines)+'\n'
def main(argv=None):
 p=argparse.ArgumentParser(description=__doc__); p.add_argument('--baseline-m32',required=True);p.add_argument('--candidate-m32',required=True);p.add_argument('--baseline-m64',required=True);p.add_argument('--candidate-m64',required=True);p.add_argument('--output',required=True);a=p.parse_args(argv)
 out=Path(a.output)
 if out.exists(): raise ValidationError(f'output exists: {out}')
 result=dict(schema=1,status='PASS',scope='active10 fixed K8 outer8; ADMM baseline-only historical exclusion; load image, not package metadata, controls image identity',geometries=[geometry(a.baseline_m32,a.candidate_m32,32),geometry(a.baseline_m64,a.candidate_m64,64)])
 out.mkdir(parents=True)
 (out/'factor_panel_comparison.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8');(out/'factor_panel_comparison_vi.md').write_text(render(result),encoding='utf-8')
if __name__=='__main__': main()
