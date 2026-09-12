"""Optional exact VM acceleration CLI; inputs are normal real matrix/Y arrays."""
import argparse
import json
from pathlib import Path
import numpy as np
from verification.v4.recovery_program_vm import execute

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--package-json',type=Path,required=True)
    parser.add_argument('--matrix-npy',type=Path,required=True)
    parser.add_argument('--measurement-npy',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--limit',type=int,default=1000000)
    parser.add_argument('--accelerate-gemv',action='store_true')
    args=parser.parse_args();stats={}
    result=execute(json.loads(args.package_json.read_text()),np.load(args.matrix_npy,allow_pickle=False),
                   np.load(args.measurement_npy,allow_pickle=False),args.limit,
                   accelerate_gemv=args.accelerate_gemv,gemv_stats=stats)
    result={k:v.tolist() if isinstance(v,np.ndarray) else v for k,v in result.items()}
    args.output.write_text(json.dumps(dict(result=result,accelerate_gemv=args.accelerate_gemv,gemv_stats=stats),indent=2)+'\n')

if __name__=='__main__':main()
