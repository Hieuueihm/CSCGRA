import copy,tempfile,unittest
from pathlib import Path
from scripts.v4 import report_factor_panel_comparison as report
class ReportFactorPanelTests(unittest.TestCase):
 def case(self,a,rows,load):
  return dict(algorithm=a,rows=rows,columns=64 if rows==32 else 256,requested_sparsity=8,requested_outer_iterations=8,outer_iterations=8,raw_phi_sha256='a'*64,raw_y_sha256='b'*64,policy={'x':1},output_raw_x_sha256='c'*64,output_raw_r_sha256='d'*64,status='MAX_ITERATIONS',accepted_support=[1],inner_iterations=3,fixed_numeric_events={},fixed_model_trace=['x'],fixed_solver_trace=['y'],solver_invocations=1,solver_solve_count=1,solver_refinement_count=0,maximum_ls_support=8,total_committed_inner_iterations=3,planted_support=list(range(8)),job_cycles=100,quality={'fixed':{'snr_db':1.0}},load_image_sha256=load,cycle_profile={'service_totals':{'KERNEL:13':{'calls':1}}} if a in report.QR else {'service_totals':{}})
 def summary(self,rows,admm=False):
  cs=[self.case(a,rows,('%064x'%i)) for i,a in enumerate(report.ACTIVE)]
  if admm: cs.append(self.case('ADMM',rows,'f'*64))
  return dict(status='PASS',changed_sources=[],untracked_imports=[],source_sha256={'s':'x'},config={'rows':rows,'sparsity':8,'outer':8},cases=cs)
 def test_baseline_only_admm_and_panel_image_are_allowed(self):
  old=self.summary(32,True);new=self.summary(32);new['cases'][4]['load_image_sha256']='e'*64
  g=report.geometry_files(old,new,32);self.assertTrue(g['baseline_admm_excluded']);self.assertTrue(g['rows_output'][4]['panel_image_changed'])
 def test_nonqr_load_change_is_rejected(self):
  old=self.summary(32);new=self.summary(32);new['cases'][0]['load_image_sha256']='e'*64
  with self.assertRaisesRegex(report.ValidationError,'outside permitted'): report.compare(old['cases'][0],new['cases'][0],32,'MP')
 def test_package_hash_cannot_substitute_for_load_image(self):
  case=self.case('OMP',32,'1'*64);case.pop('load_image_sha256');case['package_sha256']='2'*64
  with self.assertRaisesRegex(report.ValidationError,'load_image_sha256'): report.load_digest(case,'case')
 def test_changed_outer_raw_x_and_quality_are_rejected(self):
  old=self.summary(32);new=self.summary(32)
  for key,value in [('outer_iterations',7),('output_raw_x_sha256','e'*64),('quality',{'fixed':{'snr_db':2.0}})]:
   changed=copy.deepcopy(new);changed['cases'][4][key]=value
   with self.assertRaises(report.ValidationError): report.compare(old['cases'][4],changed['cases'][4],32,'GOMP')
 def test_real_baseline_artifact_preflight(self):
  root=Path('D:/vivado_pj/reports/v4/cycle_round2_final_fixed8_m32_20260909')
  if not root.is_dir(): self.skipTest('archived baseline unavailable')
  path,summary=report.read(root)
  self.assertEqual(len(report.cases(summary,'baseline M32',32,path.parent)),11)
 def test_tampered_package_digest_cannot_resolve_artifact(self):
  root=Path('D:/vivado_pj/reports/v4/cycle_round2_final_fixed8_m32_20260909')
  if not root.is_dir(): self.skipTest('archived baseline unavailable')
  path,summary=report.read(root); case=copy.deepcopy(summary['cases'][0]);case['package_sha256']='0'*64
  with self.assertRaisesRegex(report.ValidationError,'match count 0'): report.load_digest(case,'tampered',path.parent)
if __name__=='__main__':unittest.main()
