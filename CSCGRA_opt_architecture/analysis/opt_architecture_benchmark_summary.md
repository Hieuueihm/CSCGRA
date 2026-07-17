# opt_architecture benchmark summary

## Cycle comparison
- Source new: D:\vivado_pj\CSCGRA_opt_architecture\xsim.log
- Source old: D:\vivado_pj\CSCGRA_gp_opt\xsim.log
- Full new test: tb_run1_k_sweep: 348 PASS, 0 FAIL
- Compared entries: 62, improved: 24, regressed: 0, same: 38
- Old total cycles: 3370391
- New total cycles: 3223223
- Total improvement: 4.37%

## By alg

Alg Count OldTotal NewTotal  Delta ImprovementPct
--- ----- -------- --------  ----- --------------
  0     8   399964   399964      0              0
  1     7   625414   625414      0              0
  2     8   329122   280066 -49056          14.91
  3     8   692420   643364 -49056           7.08
  4     7   530919   530919      0              0
  5     8   331202   282146 -49056          14.81
  6     8   217486   217486      0              0
  7     8   243864   243864      0              0




## By case

Case Count OldTotal NewTotal  Delta ImprovementPct
---- ----- -------- --------  ----- --------------
   0     6  1234838  1170326 -64512           5.22
   1     8   950591   918335 -32256           3.39
   2     8   355485   339357 -16128           4.54
   3     8   516448   500320 -16128           3.12
   4     8   147482   139418  -8064           5.47
   5     8    56448    52416  -4032           7.14
   6     8    84185    80153  -4032           4.79
   7     8    24914    22898  -2016           8.09




## Implementation OOC timing
- Routed cgra_top OOC WNS: 0.970 ns, TNS: 0.000, WHS: 0.047, THS: 0.000
- Route status: fully routed nets 90671, routing errors 0
- Reports: D:\vivado_pj\CSCGRA_opt_architecture\runs\impl_ooc_cgra_top
