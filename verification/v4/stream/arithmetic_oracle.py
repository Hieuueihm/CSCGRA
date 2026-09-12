"""Independent arithmetic expectations for the proposed bounded stream PE subset."""
S_MIN=-(1<<26)
S_MAX=(1<<26)-1
A_MIN=-(1<<63)
A_MAX=(1<<63)-1

def round_away(value,shift):
    magnitude=abs(value)
    if shift:magnitude=(magnitude+(1<<(shift-1)))>>shift
    return -magnitude if value<0 else magnitude

def arithmetic(op,mode,a,b,acc,enabled=True):
    if not enabled:return 0,acc,0
    if op not in range(5):return 0,acc,1
    if op in (3,4) and not mode and not -(1<<17)<=b<(1<<17):return 0,acc,2
    if op==0:value=a
    elif op==1:value=a+b
    elif op==2:value=a-b
    elif op==3:value=round_away(a*b,22 if mode else 16)
    else:
        total=acc+a*b
        if not A_MIN<=total<=A_MAX:return 0,acc,4
        return 0,total,0
    if not S_MIN<=value<=S_MAX:return 0,acc,3
    return value,acc,0
