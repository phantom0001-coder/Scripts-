import re, struct
from dataclasses import dataclass
class IB3Error(Exception): pass
@dataclass
class Instruction: opcode:int; jump:int; extra:list; b:int; a:int; c:int
@dataclass
class Prototype: params:int; instructions:list
@dataclass
class ParsedIB3: profile:str; constants:list; prototypes:list; payload:bytes
HEX_RE=re.compile(r'["\']([0-9A-Fa-f]{256,})["\']')
def vi(b,p):
    v=s=0
    for _ in range(10):
        if p>=len(b): raise IB3Error("Unexpected EOF varint")
        x=b[p]; p+=1; v|=(x&127)<<s
        if x<128: return v,p
        s+=7
    raise IB3Error("Invalid varint")
def u8(b,p):
    if p>=len(b): raise IB3Error("EOF"); return None
    return b[p],p+1
def u32(b,p):
    if p+4>len(b): raise IB3Error("EOF")
    return struct.unpack_from("<I",b,p)[0],p+4
def dbl(b,p):
    if p+8>len(b): raise IB3Error("EOF")
    return struct.unpack_from("<d",b,p)[0],p+8
def payloads(src):
    out=[]
    for m in HEX_RE.finditer(src):
        s=m.group(1)
        if len(s)%2: continue
        try: out.append(bytes.fromhex(s))
        except ValueError: pass
    out.sort(key=len,reverse=True)
    if not out: raise IB3Error("No IB3 serialized hexadecimal payload found.")
    return out
def c_v0248(b,p=0):
    n,p=vi(b,p); K=[]
    if n>1000000: raise IB3Error("Bad constant count")
    for _ in range(n):
        t,p=u8(b,p)
        if t==7:
            ln,p=vi(b,p)
            if ln>len(b)-p: raise IB3Error("Bad string length")
            K.append(b[p:p+ln].decode("utf-8","replace")); p+=ln
        elif t==2:
            x,p=dbl(b,p); K.append(x)
        elif t in (33,16): K.append(True)
        elif t in (11,17): K.append(False)
        elif t in (20,43): K.append(None)
        else: raise IB3Error(f"Unknown v0.248 tag {t}")
    return K,p
def c_legacy(b,p=0):
    n,p=vi(b,p); K=[]
    for _ in range(n):
        t,p=u8(b,p)
        if t<16:
            ln,p=vi(b,p)
            if ln>len(b)-p: raise IB3Error("Bad string length")
            K.append(bytes(x^0x2e for x in b[p:p+ln]).decode("utf-8","replace")); p+=ln
        elif t==16: K.append(True)
        elif t<29: K.append(False)
        elif t<43:
            x,p=dbl(b,p); K.append(x)
        else: K.append(None)
    return K,p
def protos(b,p):
    n,p=vi(b,p)
    if not 0<n<=100000: raise IB3Error(f"Invalid prototype count {n}")
    fs=[]
    for i in range(n):
        params,p=u8(b,p); cnt,p=vi(b,p)
        if cnt>10000000: raise IB3Error("Bad instruction count")
        ins=[]
        for _ in range(cnt):
            op,p=u32(b,p); j,p=u32(b,p); ec,p=u8(b,p)
            if ec>64: raise IB3Error("Bad extra count")
            extra=[]
            for _ in range(ec):
                x,p=vi(b,p); extra.append(x)
            bb,p=u32(b,p); a,p=u32(b,p); c,p=u32(b,p)
            ins.append(Instruction(op,j,extra,bb,a,c))
        fs.append(Prototype(params,ins))
    return fs,p
def parse_ib3(src):
    ok=[]
    for raw in payloads(src):
        for name,dec in (("ib3-v0.248",c_v0248),("ib3-legacy-xor2e",c_legacy)):
            try:
                K,p=dec(raw,0); fs,p=protos(raw,p)
                if p==len(raw): ok.append((len(fs),len(K),len(raw),name,K,fs,raw))
            except Exception: pass
    if not ok: raise IB3Error("IB3 payload found, but no supported serialization profile decoded it.")
    _,_,_,name,K,fs,raw=max(ok)
    return ParsedIB3(name,K,fs,raw)
def find_root(fs):
    if not fs: raise IB3Error("No prototypes recovered")
    return len(fs)-1
