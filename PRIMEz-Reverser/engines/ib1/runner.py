#!/usr/bin/env python3
from __future__ import annotations

import argparse, base64, json, os, re, shutil, subprocess, sys, urllib.request, tempfile
from pathlib import Path
from typing import Any

CAP_BEGIN='__IB1P_BEGIN__'
CAP_END='__IB1P_END__'

CAPTURE_LUA = r'''
local __ib1_pid = 0
local function __ib1_hex(s)
    local t = {}
    for i=1,#s do t[#t+1]=string.format("%02x", string.byte(s,i)) end
    return table.concat(t)
end
local function __ib1_dump(root, ...)
    __ib1_pid += 1
    local pid=__ib1_pid
    local ids, q, nxt = {}, {}, 1
    local function ref(v)
        local tv=type(v)
        if tv=="nil" then return "N" end
        if tv=="boolean" then return v and "B1" or "B0" end
        if tv=="number" then return "D"..string.format("%.17g",v) end
        if tv=="string" then return "S"..__ib1_hex(v) end
        if tv=="table" then
            local id=ids[v]
            if not id then id=nxt;nxt+=1;ids[v]=id;q[#q+1]=v end
            return "T"..tostring(id)
        end
        return "X"..__ib1_hex(tv)
    end
    local vals={...}
    print("'''+CAP_BEGIN+r'''\t"..pid)
    print("ROOT\t"..ref(root))
    print("VALS\t"..ref(vals))
    local qi=1
    while qi<=#q do
        local tab=q[qi]; local id=ids[tab]
        print("TABLE\t"..id)
        for k,v in pairs(tab) do
            print("ENTRY\t"..id.."\t"..ref(k).."\t"..ref(v))
        end
        qi+=1
    end
    print("'''+CAP_END+r'''\t"..pid)
end
'''


def detect(src:str)->bool:
    return 'ironbrew1' in src.lower() and 'while true do' in src


def find_vm_tuple(src:str):
    rx=re.compile(
        r"local\s+([A-Za-z_]\w*(?:\s*,\s*[A-Za-z_]\w*){13})\s*=\s*"
        r"([A-Za-z_]\w*)\(\s*([A-Za-z_]\w*)\s*,\s*([A-Za-z_]\w*)\s*\)\s*;"
        r"\s*local\s+([A-Za-z_]\w*)\s*=\s*([A-Za-z_]\w*)\[([A-Za-z_]\w*)\[6\]\]"
    )
    for m in rx.finditer(src):
        names=[x.strip() for x in m.group(1).split(',')]
        if m.group(6)==names[5] and m.group(7)==names[13]:
            return m,names
    raise RuntimeError('could not locate IronBrew1 decoded VM tuple')


def enclosing_builder(src:str, pos:int):
    matches=list(re.finditer(r'([A-Za-z_]\w*)\s*=\s*function\s*\(([^)]*)\)', src[:pos]))
    if not matches: raise RuntimeError('could not locate VM closure builder')
    m=matches[-1]
    args=[x.strip() for x in m.group(2).split(',') if x.strip() and x.strip()!='...']
    return m,args


def _matching_function_end(src: str, assign_match) -> tuple[int,int]:
    """Return (start,end) offsets of the `end` closing `name=function(...)`.

    We need this because a Lua/Luau `return` must be the final statement in its
    block.  The old instrumenter injected a return and left the original VM body
    after it, which made the instrumented source fail to parse.
    """
    fpos=src.find('function',assign_match.start(),assign_match.end()+16)
    if fpos < 0:
        raise RuntimeError('could not locate VM builder function token')
    toks=control_tokens(src[fpos:])
    stack=[]
    for v,a,b in toks:
        a+=fpos; b+=fpos
        if v=='function':
            stack.append('function')
        elif v=='if':
            stack.append('if')
        elif v=='do':
            stack.append('do')
        elif v=='repeat':
            stack.append('repeat')
        elif v=='until':
            if stack and stack[-1]=='repeat':
                stack.pop()
        elif v=='end':
            if not stack:
                raise RuntimeError('unbalanced VM builder while instrumenting')
            stack.pop()
            if not stack:
                return a,b
    raise RuntimeError('unterminated VM closure builder')


def instrument(src:str)->str:
    m,names=find_vm_tuple(src)
    builder_match,args=enclosing_builder(src,m.start())
    builder=builder_match.group(1)
    root=m.group(3)
    childtab=names[10] # 11th decoded value; IronBrew prototype table in this family
    envarg=args[2] if len(args)>=3 else 'nil'

    # Replace the *rest* of the builder body after the decoder tuple.  Do not
    # merely inject a return before the old body: Lua/Luau requires return to be
    # the final statement of a block.
    fend_start,_fend_end=_matching_function_end(src,builder_match)
    if fend_start <= m.end():
        raise RuntimeError('VM builder end was found before decoded tuple')

    injected=(
        ';__ib1_dump('+root+','+','.join(names)+');'
        'if type('+childtab+')=="table" then '
        'for _,__ib1_ch in pairs('+childtab+') do '
        'if type(__ib1_ch)=="table" then pcall('+builder+',__ib1_ch,{},'+envarg+') end '
        'end end;'
        'return function(...) return nil end;'
    )
    return CAPTURE_LUA+'\n'+src[:m.end()]+injected+src[fend_start:_fend_end]+';'+src[_fend_end:]


def atom(s:str):
    tag,body=s[:1],s[1:]
    if tag=='N': return None
    if tag=='B': return body=='1'
    if tag=='D':
        try: return int(body) if re.fullmatch(r'[-+]?\d+',body) else float(body)
        except: return body
    if tag=='S': return bytes.fromhex(body).decode('utf-8','surrogateescape')
    if tag=='T': return ('REF',int(body))
    if tag=='X': return {'opaque':bytes.fromhex(body).decode('utf-8','replace')}
    raise ValueError(s)


class LuaTable(dict):
    """Decoded Lua table with identity semantics.

    IronBrew deliberately uses table objects as keys in a few selector maps.
    Python's normal dict is unhashable, while a Lua table is a valid identity
    key.  Keep the table id from the capture stream and hash by identity so
    expressions such as cj[cr[6]] survive decoding exactly.
    """
    __slots__ = ("table_id",)

    def __init__(self, table_id:int):
        super().__init__()
        self.table_id=table_id

    __hash__ = object.__hash__
    __eq__ = object.__eq__

    def __repr__(self):
        return f"<LuaTable T{self.table_id} {dict.__repr__(self)}>"


def parse_capture(text:str):
    blocks=[]; cur=None
    for line in text.splitlines():
        if line.startswith(CAP_BEGIN+'\t'):
            cur={'pid':int(line.split('\t')[1]),'tables':{},'root':None,'vals':None}; continue
        if cur is None: continue
        if line.startswith(CAP_END+'\t'):
            blocks.append(cur);cur=None;continue
        p=line.split('\t')
        if p[0]=='ROOT': cur['root']=atom(p[1])
        elif p[0]=='VALS': cur['vals']=atom(p[1])
        elif p[0]=='TABLE': cur['tables'].setdefault(int(p[1]),[])
        elif p[0]=='ENTRY': cur['tables'].setdefault(int(p[1]),[]).append((atom(p[2]),atom(p[3])))

    out=[]
    for b in blocks:
        # Allocate every table first. This is important: references used as Lua
        # table keys must point at the exact same Python object as references
        # used as values.
        memo={tid:LuaTable(tid) for tid in b['tables']}

        def resolve(v):
            if isinstance(v,tuple) and len(v)==2 and v[0]=='REF':
                tid=v[1]
                if tid not in memo:
                    memo[tid]=LuaTable(tid)
                return memo[tid]
            return v

        # Fill after allocation, which also supports cyclic/self-referential
        # tables without recursion.
        for tid,entries in b['tables'].items():
            tab=memo[tid]
            for k,x in entries:
                tab[resolve(k)]=resolve(x)

        out.append({'pid':b['pid'],'root':resolve(b['root']),'vals':resolve(b['vals'])})
    return out


def get(t,k,d=None):
    if isinstance(t,dict):
        try:
            return t.get(k,d)
        except TypeError:
            return d
    return d

def json_safe(v, seen=None):
    """Convert identity-keyed Lua tables to JSON-safe diagnostic data."""
    if seen is None: seen=set()
    if isinstance(v,LuaTable):
        oid=id(v)
        if oid in seen: return {'$ref':v.table_id}
        seen.add(oid)
        items=[]
        for k,x in v.items():
            items.append([json_safe(k,seen),json_safe(x,seen)])
        seen.remove(oid)
        return {'$table':v.table_id,'entries':items}
    if isinstance(v,dict):
        return {str(k):json_safe(x,seen) for k,x in v.items()}
    if isinstance(v,list): return [json_safe(x,seen) for x in v]
    if isinstance(v,tuple): return [json_safe(x,seen) for x in v]
    return v

def seqlen(t):
    if not isinstance(t,dict): return 0
    i=1
    while i in t:i+=1
    return i-1


def extract_proto(block):
    vals=block['vals']; V=[None]+[get(vals,i) for i in range(1,15)]
    if any(x is None for x in V[1:]):
        pass
    ce,cf,cg,ch,ci,cj,ck,cl,cm,cn,co,cp,cq,cr=V[1:15]
    if not isinstance(cj,dict) or not isinstance(cr,dict):
        raise RuntimeError(f"prototype {block['pid']} does not contain expected dispatcher tables")
    slots={}
    for idx,name in [(0,'ct'),(1,'opcode'),(2,'cy'),(3,'cz'),(4,'cu'),(5,'cv'),(6,'cs'),(7,'cw'),(8,'cx')]:
        sel=get(cr,idx); slots[name]=get(cj,sel) if sel is not None else None
    n=max([seqlen(slots.get(x)) for x in ('opcode','cy','cz','cu','cv')]+[0])
    inst=[]
    for pc in range(1,n+1):
        r={'pc':pc}
        for x in ('opcode','cy','cz','cu','cv'):
            r[x]=get(slots.get(x),pc)
        inst.append(r)
    return {'pid':block['pid'],'decoded':V,'meta':{'params':ci,'vararg':ck,'registers':cq},'instructions':inst}


# --- lightweight Lua block parser used only to partially evaluate the opcode dispatcher ---
TOKEN_RE=re.compile(r'''(?sx)
    --\[(=*)\[.*?\]\1\] | --[^\n]* |
    \[(=*)\[.*?\]\2\] |
    "(?:\\.|[^"\\])*" | '(?:\\.|[^'\\])*' |
    \b(?:if|then|elseif|else|end|function|do|repeat|until|while|for)\b
''')

def control_tokens(s):
    out=[]
    for m in TOKEN_RE.finditer(s):
        v=m.group(0)
        if v.startswith('--') or v.startswith('"') or v.startswith("'") or v.startswith('['): continue
        out.append((v,m.start(),m.end()))
    return out


def parse_if(s, if_pos):
    toks=control_tokens(s[if_pos:]);
    if not toks or toks[0][0]!='if': raise ValueError('not if')
    # absolute positions
    toks=[(v,a+if_pos,b+if_pos) for v,a,b in toks]
    # first then at depth zero
    then_i=next(i for i,t in enumerate(toks) if t[0]=='then')
    clauses=[]; cond_start=toks[0][2]; cond_end=toks[then_i][1]; body_start=toks[then_i][2]
    stack=['if']; i=then_i+1
    while i<len(toks):
        v,a,b=toks[i]
        if v=='if': stack.append('if')
        elif v=='function': stack.append('function')
        elif v=='do': stack.append('do')
        elif v=='repeat': stack.append('repeat')
        elif v=='until':
            if stack and stack[-1]=='repeat': stack.pop()
        elif v=='end':
            if len(stack)==1:
                clauses.append((s[cond_start:cond_end],body_start,a))
                return {'clauses':clauses,'else':None,'end_start':a,'end_end':b}
            if stack: stack.pop()
        elif len(stack)==1 and v in ('elseif','else'):
            clauses.append((s[cond_start:cond_end],body_start,a))
            if v=='else':
                eb=b; j=i+1; sub=['if']
                while j<len(toks):
                    vv,aa,bb=toks[j]
                    if vv=='if': sub.append('if')
                    elif vv=='function': sub.append('function')
                    elif vv=='do': sub.append('do')
                    elif vv=='repeat': sub.append('repeat')
                    elif vv=='until':
                        if sub and sub[-1]=='repeat':sub.pop()
                    elif vv=='end':
                        if len(sub)==1:
                            return {'clauses':clauses,'else':(eb,aa),'end_start':aa,'end_end':bb}
                        sub.pop()
                    j+=1
                raise ValueError('unterminated else')
            # elseif condition runs until next then at same outer level (there should be immediate then token)
            j=i+1; nested=0
            while j<len(toks):
                vv,aa,bb=toks[j]
                if vv=='then' and nested==0:
                    cond_start=b; cond_end=aa; body_start=bb; i=j; break
                j+=1
        i+=1
    raise ValueError('unterminated if')


def eval_dh(cond, op):
    c=' '.join(cond.strip().split())
    # dispatcher predicates in this IronBrew family are simple numeric comparisons on dh
    m=re.fullmatch(r'\(?\s*dh\s*(==|~=|<=|>=|<|>)\s*(-?\d+)\s*\)?',c)
    if not m:return None
    n=int(m.group(2)); q=m.group(1)
    return {'==':op==n,'~=':op!=n,'<=':op<=n,'>=':op>=n,'<':op<n,'>':op>n}[q]


def prune_dispatch(s, op, depth=0):
    if depth>80:return s
    toks=control_tokens(s)
    pos=None
    for v,a,b in toks:
        if v=='if': pos=a; break
    if pos is None:return s
    try: node=parse_if(s,pos)
    except Exception:return s
    first_eval=eval_dh(node['clauses'][0][0],op)
    before=s[:pos]; after=s[node['end_end']:]
    if first_eval is not None:
        chosen=None
        for cond,a,b in node['clauses']:
            ev=eval_dh(cond,op)
            if ev is None: return s
            if ev: chosen=s[a:b]; break
        if chosen is None and node['else'] is not None: chosen=s[node['else'][0]:node['else'][1]]
        if chosen is None: chosen=''
        return prune_dispatch(before+chosen+after,op,depth+1)
    # dynamic if: keep it and only prune inside its bodies conservatively
    return s


def dispatcher_region(src):
    m,names=find_vm_tuple(src)
    opcode_name=names[5] # cj? actual fetched table selected later, fetch variable is dh in sample
    # Find first assignment of a local scalar from table indexed by dq followed by if tree.
    # Strong family anchor: "while true do <enum>=<table>[<pc>];if <enum>..."
    pat=re.compile(r'while\s+true\s+do\s+([A-Za-z_]\w*)\s*=\s*([A-Za-z_]\w*)\[([A-Za-z_]\w*)\]\s*;\s*if\s+\1')
    mm=pat.search(src,m.end())
    if not mm: raise RuntimeError('could not locate VM dispatcher loop')
    enum,insttab,pc=mm.group(1),mm.group(2),mm.group(3)
    ifpos=src.find('if',mm.start())
    node=parse_if(src,ifpos)
    return {'enum':enum,'insttab':insttab,'pc':pc,'if_source':src[ifpos:node['end_end']]}

def analyze_symbols(src):
    m,names=find_vm_tuple(src)
    tab=names[5]; sel=names[13]
    win=src[m.end():m.end()+2500]
    slotvars={}
    for lm in re.finditer(r'local\s+([A-Za-z_][A-Za-z0-9_]*(?:\s*,\s*[A-Za-z_][A-Za-z0-9_]*)*)\s*=\s*([^;]+);',win):
        lhs=[x.strip() for x in lm.group(1).split(',')]
        rhs=[x.strip() for x in lm.group(2).split(',')]
        if len(lhs)!=len(rhs): continue
        for lv,rv in zip(lhs,rhs):
            rm=re.fullmatch(re.escape(tab)+r'\['+re.escape(sel)+r'\[(\d+)\]\]',rv)
            if rm: slotvars[int(rm.group(1))]=lv
    # stack/pc initialization: local STACK,PC,... = allocator(regcount),1,...
    regcount=names[12]
    sm=re.search(r'local\s+([A-Za-z_]\w*)\s*,\s*([A-Za-z_]\w*)[^=]*=\s*[A-Za-z_]\w*\(\s*'+re.escape(regcount)+r'\s*\)\s*,\s*1\b',win)
    stack,pc=(sm.group(1),sm.group(2)) if sm else ('dp','dq')
    helpers={}
    for opname,nums in [('band','98,97,110,100'),('bor','98,111,114'),('bxor','98,120,111,114'),('lshift','108,115,104,105,102,116'),('rshift','114,115,104,105,102,116')]:
        hm=re.search(r'([A-Za-z_]\w*)\s*=\s*[A-Za-z_]\w*\s+and\s+[A-Za-z_]\w*\[\s*[A-Za-z_]\w*\('+nums+r'\)\]',src)
        if hm: helpers[opname]=hm.group(1)
    return {'tuple':names,'slotvars':slotvars,'stack':stack,'pc':pc,'const':names[0],'helpers':helpers}


def lua_lit(v,depth=0):
    if depth>5:return 'nil'
    if v is None:return 'nil'
    if v is True:return 'true'
    if v is False:return 'false'
    if isinstance(v,(int,float)):return repr(v)
    if isinstance(v,str):return json.dumps(v.encode('utf-8','surrogateescape').decode('utf-8','replace'))
    if isinstance(v,dict):
        if 'opaque' in v:return 'nil --[[opaque '+str(v['opaque'])+']]'
        items=[]
        for k,x in list(v.items())[:10000]:
            items.append('['+lua_lit(k,depth+1)+']='+lua_lit(x,depth+1))
        return '{'+','.join(items)+'}'
    return 'nil'


def specialize(body,row, symbols, pcname, enumname):
    out=body
    # selector index -> decoded operand stream: 2=cy,3=cz,4=cu,5=cv in this family
    vals={2:row.get('cy'),3:row.get('cz'),4:row.get('cu'),5:row.get('cv')}
    for idx,val in vals.items():
        name=symbols['slotvars'].get(idx)
        if name:
            out=re.sub(r'\b'+re.escape(name)+r'\s*\[\s*'+re.escape(pcname)+r'\s*\]', '('+lua_lit(val)+')', out)
    out=re.sub(r'\b'+re.escape(enumname)+r'\b', str(row.get('opcode')), out)
    out=re.sub(r'\b'+re.escape(symbols['stack'])+r'\b','R',out)
    out=re.sub(r'\b'+re.escape(symbols['const'])+r'\b','K',out)
    out=re.sub(r'\b'+re.escape(pcname)+r'\b','pc',out)
    for canonical,orig in symbols['helpers'].items():
        out=re.sub(r'\b'+re.escape(orig)+r'\b', canonical, out)
    return out.strip()


def generate_devirt(src,proto):
    d=dispatcher_region(src); enum=d['enum']; pcname=d['pc']; tree=d['if_source']; symbols=analyze_symbols(src)
    lines=[]
    pid=proto['pid']; V=proto['decoded']; meta=proto['meta']
    lines.append(f'-- IronBrew1 lifted prototype {pid}')
    lines.append('-- Opcode dispatcher and encoded instruction arrays have been removed.')
    lines.append('local band,bor,bxor,lshift,rshift = bit32.band,bit32.bor,bit32.bxor,bit32.lshift,bit32.rshift')
    lines.append('local K = '+lua_lit(V[1]))
    lines.append('local function proto_'+str(pid)+'(...)')
    lines.append('  local R = {}')
    lines.append('  local pc = 1')
    lines.append('  local di,dj,dk,dl,dm,dn,_do,dr,ds,dg = 0,nil,0,0,0,nil,nil,-1,0,nil')
    lines.append('  while true do')
    for idx,row in enumerate(proto['instructions']):
        op=row.get('opcode')
        if not isinstance(op,(int,float)): continue
        pr=prune_dispatch(tree,int(op))
        # strip any residual outer opcode tests; if pruning failed, emit explicit warning comment instead of lying
        if re.search(r'\b(?:if|elseif)\s+'+re.escape(enum)+r'\s*(?:[<>=~])',pr):
            body='--[[ unresolved opcode handler '+str(op)+' ]]'
        else:
            body=specialize(pr,row,symbols,pcname,enum)
        kw='if' if idx==0 else 'elseif'
        lines.append(f'    {kw} pc == {row["pc"]} then')
        for ln in re.sub(r';', ';\n', body).splitlines():
            if ln.strip(): lines.append('      '+ln.strip())
    lines.append('    else')
    lines.append('      return')
    lines.append('    end')
    lines.append('    pc += 1')
    lines.append('  end')
    lines.append('end')
    lines.append('return proto_'+str(pid))
    return '\n'.join(lines)+'\n'


def lua_expert(source:Path, compiler:str, output:Path, timeout=90):
    cp=subprocess.run([compiler,'binary',str(source)],stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=timeout)
    if cp.returncode!=0: raise RuntimeError('luau-compile failed:\n'+cp.stderr.decode(errors='replace'))
    req=urllib.request.Request('https://api.lua.expert/decompile',data=json.dumps({'script':base64.b64encode(cp.stdout).decode()}).encode(),headers={'content-type':'application/json'},method='POST')
    with urllib.request.urlopen(req,timeout=timeout) as r: data=r.read().decode('utf-8','replace')
    output.write_text(data,encoding='utf-8')



# ---------------------------------------------------------------------------
# Combined output / readability pass
# ---------------------------------------------------------------------------

def compile_dispatch_tree(source: str):
    """Parse the randomized dh decision tree once.

    The old implementation called prune_dispatch() independently for every
    opcode, repeatedly tokenizing the same very large nested if-tree.  This
    compiler turns only dh-based dispatcher branches into a reusable tree;
    dynamic program logic inside an opcode handler remains untouched.
    """
    def compile_segment(seg: str, depth=0):
        if depth > 128:
            return ('leaf', seg)
        toks=control_tokens(seg)
        pos=None
        for v,a,b in toks:
            if v=='if':
                pos=a; break
        if pos is None:
            return ('leaf', seg)
        try:
            node=parse_if(seg,pos)
        except Exception:
            return ('leaf', seg)
        clauses=node['clauses']
        # Only compile an if when every conditional clause is a numeric test
        # on the randomized opcode variable dh. Otherwise it is real program
        # logic and must be preserved verbatim.
        tests=[]
        for cond,a,b in clauses:
            if eval_dh(cond,0) is None:
                return ('leaf', seg)
            tests.append((cond, compile_segment(seg[a:b], depth+1)))
        else_node=None
        if node['else'] is not None:
            a,b=node['else']
            else_node=compile_segment(seg[a:b], depth+1)
        prefix=seg[:pos]
        suffix=seg[node['end_end']:]
        return ('dispatch', prefix, tests, else_node, suffix)
    return compile_segment(source)


def resolve_dispatch_tree(node, op: int) -> str:
    kind=node[0]
    if kind=='leaf':
        return node[1]
    _,prefix,tests,else_node,suffix=node
    chosen=''
    for cond,child in tests:
        ev=eval_dh(cond,op)
        if ev:
            chosen=resolve_dispatch_tree(child,op)
            break
    else:
        if else_node is not None:
            chosen=resolve_dispatch_tree(else_node,op)
    return prefix+chosen+suffix


def build_vm_context(src: str, protos: list[dict[str, Any]]):
    d=dispatcher_region(src)
    enum=d["enum"]; pcname=d["pc"]; symbols=analyze_symbols(src)
    compiled=compile_dispatch_tree(d["if_source"])
    return {"enum":enum,"pcname":pcname,"symbols":symbols,"compiled":compiled,"handlers":{}}


def semantic_inline(body: str, proto: dict[str, Any], src: str, symbols: dict[str, Any]) -> str:
    """Inline the decoded constant pool and the builder's semantic inputs.

    This is what turns low-level VM expressions such as cb[K[308]] into
    ENV["Instance"], and K[323] into "Path2D".  It is intentionally a cheap
    textual pass and does not re-analyze the opcode dispatcher.
    """
    V=proto['decoded']
    consts=V[1] if len(V)>1 else None

    # Builder arguments are (chunk, upvalues, environment, ...).  Discover the
    # randomized names instead of assuming ca/cb.
    try:
        m,_=find_vm_tuple(src)
        bm,bargs=enclosing_builder(src,m.start())
        if len(bargs)>=2:
            body=re.sub(r'\b'+re.escape(bargs[1])+r'\b','UPVALUES',body)
        if len(bargs)>=3:
            body=re.sub(r'\b'+re.escape(bargs[2])+r'\b','ENV',body)
    except Exception:
        pass

    # Decoded tuple roles used by this IronBrew1 family.
    names=symbols.get('tuple') or []
    if len(names)>=11:
        # cm: per-closure metadata value exposed by several handlers.
        body=re.sub(r'\b'+re.escape(names[8])+r'\b','META',body)
        # co: child prototype table.
        body=re.sub(r'\b'+re.escape(names[10])+r'\b','CHILDREN',body)

    # Inline constant-pool indexes.  Keep doing it a few times because a
    # replacement can expose another simple expression such as ENV[K[n]].
    if isinstance(consts,dict):
        krx=re.compile(r'\bK\s*\[\s*\(?\s*(-?\d+)\s*\)?\s*\]')
        def krepl(m):
            idx=int(m.group(1))
            if idx in consts:
                return lua_lit(consts[idx])
            return m.group(0)
        for _ in range(3):
            nb=krx.sub(krepl,body)
            if nb==body: break
            body=nb

    # Make common environment accesses readable before the generic cleaner.
    body=re.sub(r'ENV\s*\[\s*"([A-Za-z_][A-Za-z0-9_]*)"\s*\]',r'ENV["\1"]',body)
    return body



# ---------------------------------------------------------------------------
# Real devirtualization backend: VM handlers -> canonical IR -> CFG -> Lua
# ---------------------------------------------------------------------------

_REG = r'R\[(\d+)\]'


def _strip_parens_num(s: str) -> str:
    return re.sub(r'\(\s*(-?\d+)\s*\)', r'\1', s)


def resolve_handler_temps(body: str) -> str:
    """Constant-propagate IronBrew interpreter temporaries inside one handler.

    The randomized dispatcher frequently stores decoded operands in locals such
    as dj/dk/dm before touching R[].  These locals belong to the *virtual
    interpreter*, not the protected program, so resolve them before lifting.
    """
    s = body.replace('\r', ' ')
    s = _strip_parens_num(s)
    env: dict[str, str] = {}

    # Multi-local literal declarations first: local a,b=12,34
    for m in re.finditer(
        r'\blocal\s+([A-Za-z_]\w*)\s*,\s*([A-Za-z_]\w*)\s*=\s*'
        r'(-?\d+)\s*,\s*(-?\d+)', s
    ):
        env[m.group(1)] = m.group(3)
        env[m.group(2)] = m.group(4)

    # Iterate because one temporary often aliases another.
    simple = re.compile(
        r'(?:\blocal\s+)?([A-Za-z_]\w*)\s*=\s*'
        r'(R\[\d+\]|K\[\d+\]|-?\d+(?:\.\d+)?|'
        r'"(?:\\.|[^"\\])*"|nil|true|false|META|ENV|UPVALUES|CHILDREN)'
    )
    for _ in range(8):
        changed = False
        for m in simple.finditer(s):
            name, val = m.group(1), m.group(2)
            if name in {'R','K','ENV','UPVALUES','META','CHILDREN','pc'}:
                continue
            old = env.get(name)
            if old != val:
                env[name] = val
                changed = True
        ns = s
        for name, val in sorted(env.items(), key=lambda kv: -len(kv[0])):
            # Substitute reads, never assignment LHS.
            ns = re.sub(r'\b'+re.escape(name)+r'\b(?!\s*=)', val, ns)
        if ns == s and not changed:
            break
        s = ns

    # Remove now-dead scalar temp declarations/assignments.  Do not remove
    # assignments to VM state that are still referenced by unresolved handlers.
    for name in sorted(env, key=len, reverse=True):
        s = re.sub(
            r'\blocal\s+'+re.escape(name)+r'\s*=\s*[^;\n]+;?', '', s
        )
    s = re.sub(r';\s*;', ';', s)
    return _strip_parens_num(s).strip(' ;\n')


def _lua_key(value: str) -> dict[str, Any]:
    value = value.strip()
    m = re.fullmatch(r'R\[(\d+)\]', value)
    if m:
        return {'kind':'reg','value':int(m.group(1))}
    return {'kind':'lit','value':value}


def _split_args(argtext: str) -> list[str]:
    argtext = argtext.strip()
    if not argtext:
        return []
    out=[]; cur=[]; depth=0; quote=None; esc=False
    for ch in argtext:
        if quote:
            cur.append(ch)
            if esc: esc=False
            elif ch=='\\': esc=True
            elif ch==quote: quote=None
            continue
        if ch in ('"', "'"):
            quote=ch; cur.append(ch); continue
        if ch in '([{': depth+=1
        elif ch in ')]}': depth=max(0,depth-1)
        if ch==',' and depth==0:
            out.append(''.join(cur).strip()); cur=[]
        else: cur.append(ch)
    if cur: out.append(''.join(cur).strip())
    return out


def _arg_ir(s: str) -> dict[str, Any]:
    s=s.strip()
    m=re.fullmatch(r'R\[(\d+)\]',s)
    if m: return {'kind':'reg','value':int(m.group(1))}
    return {'kind':'lit','value':s}


def lift_handler(body: str, row: dict[str, Any], proto: dict[str, Any], src: str, symbols: dict[str, Any]) -> list[dict[str, Any]]:
    """Translate one specialized IronBrew handler into canonical operations.

    This is deliberately independent of randomized opcode numbers.  The result
    is an instruction list describing protected-program semantics.
    """
    body = resolve_handler_temps(body)
    body = semantic_inline(body, proto, src, symbols)
    body = _strip_parens_num(body)
    pc = int(row['pc'])
    ir: list[dict[str, Any]] = []

    # Control flow.  Keep these even if the same handler also performs an op.
    control_consumed=[]
    for m in re.finditer(r'if\s+R\[(\d+)\]\s+then\s+pc\s*=\s*(-?\d+)\s*;?\s*end', body):
        ir.append({'op':'BRANCH_TRUE','cond':int(m.group(1)),'target':int(m.group(2))+1,'fallthrough':pc+1})
        control_consumed.append(m.span())
    for m in re.finditer(r'if\s+not\s+R\[(\d+)\]\s+then\s+pc\s*=\s*(-?\d+)\s*;?\s*end', body):
        ir.append({'op':'BRANCH_FALSE','cond':int(m.group(1)),'target':int(m.group(2))+1,'fallthrough':pc+1})
        control_consumed.append(m.span())

    # Returns.
    m=re.search(r'\bdo\s+return(?:\s+(.+?))?\s+end\b',body)
    if m:
        vals=[] if not m.group(1) else [_arg_ir(x) for x in _split_args(m.group(1))]
        ir.append({'op':'RETURN','values':vals})

    # CLOSURE.  Handles the common already-resolved child form.
    for m in re.finditer(r'R\[(\d+)\]\s*=\s*bk\(CHILDREN\[(\d+)\].*?ENV\)',body):
        ir.append({'op':'CLOSURE','dst':int(m.group(1)),'child':int(m.group(2))})

    # Globals/upvalues/meta/newtable.
    for m in re.finditer(r'R\[(\d+)\]\s*=\s*ENV\["((?:\\.|[^"\\])*)"\]',body):
        ir.append({'op':'GETGLOBAL','dst':int(m.group(1)),'name':m.group(2)})
    for m in re.finditer(r'ENV\["((?:\\.|[^"\\])*)"\]\s*=\s*R\[(\d+)\]',body):
        ir.append({'op':'SETGLOBAL','name':m.group(1),'src':int(m.group(2))})
    for m in re.finditer(r'R\[(\d+)\]\s*=\s*UPVALUES\[(\d+)\]',body):
        ir.append({'op':'GETUPVAL','dst':int(m.group(1)),'idx':int(m.group(2))})
    for m in re.finditer(r'UPVALUES\[(\d+)\]\s*=\s*R\[(\d+)\]',body):
        ir.append({'op':'SETUPVAL','idx':int(m.group(1)),'src':int(m.group(2))})
    for m in re.finditer(r'R\[(\d+)\]\s*=\s*META\b',body):
        ir.append({'op':'META','dst':int(m.group(1))})
    for m in re.finditer(r'R\[(\d+)\]\s*=\s*\{\s*\}',body):
        ir.append({'op':'NEWTABLE','dst':int(m.group(1))})

    # Method calls emitted by fused handlers, e.g. obj["Destroy"](obj,...)
    meth_rx=re.compile(
        r'R\[(\d+)\]\s*\[\s*"((?:\\.|[^"\\])*)"\s*\]\s*'
        r'\(\s*R\[\1\]\s*(?:,\s*(.*?))?\)'
    )
    for m in meth_rx.finditer(body):
        args=[] if not m.group(3) else [_arg_ir(x) for x in _split_args(m.group(3))]
        ir.append({'op':'METHODCALL','dst':None,'obj':int(m.group(1)),'method':m.group(2),'args':args,'retc':0})

    # Getter-style fused method call: R[a]=tmp(receiver)
    getmeth=re.compile(
        r'R\[(\d+)\]\s*=\s*[A-Za-z_]\w*\(\s*R\[(\d+)\]\s*(?:,\s*(.*?))?\)'
    )
    # We only accept when the handler also contains ["method"] near the call.
    for m in getmeth.finditer(body):
        prefix=body[max(0,m.start()-180):m.start()]
        mm=re.findall(r'\[\s*"((?:\\.|[^"\\])*)"\s*\]',prefix)
        if mm:
            args=[] if not m.group(3) else [_arg_ir(x) for x in _split_args(m.group(3))]
            ir.append({'op':'METHODCALL','dst':int(m.group(1)),'obj':int(m.group(2)),'method':mm[-1],'args':args,'retc':1})

    # Direct calls with explicit register args.
    call_rx=re.compile(r'R\[(\d+)\]\s*=\s*R\[\1\]\(([^()]*)\)')
    for m in call_rx.finditer(body):
        args=[_arg_ir(x) for x in _split_args(m.group(2))]
        ir.append({'op':'CALL','dst':int(m.group(1)),'func':int(m.group(1)),'args':args,'retc':1})
    call0_rx=re.compile(r'(?<![=])R\[(\d+)\]\(([^()]*)\)')
    for m in call0_rx.finditer(body):
        # avoid duplicate direct-call RHS matches
        if m.start()>0 and body[max(0,m.start()-2):m.start()].strip().endswith('='):
            continue
        args=[_arg_ir(x) for x in _split_args(m.group(2))]
        ir.append({'op':'CALL','dst':None,'func':int(m.group(1)),'args':args,'retc':0})

    # Table reads/writes. Literal-key versions first.
    for m in re.finditer(r'R\[(\d+)\]\s*=\s*R\[(\d+)\]\s*\[\s*(R\[\d+\]|"(?:\\.|[^"\\])*"|-?\d+(?:\.\d+)?)\s*\]',body):
        ir.append({'op':'GETTABLE','dst':int(m.group(1)),'obj':int(m.group(2)),'key':_lua_key(m.group(3))})
    for m in re.finditer(r'R\[(\d+)\]\s*\[\s*(R\[\d+\]|"(?:\\.|[^"\\])*"|-?\d+(?:\.\d+)?)\s*\]\s*=\s*R\[(\d+)\]',body):
        ir.append({'op':'SETTABLE','obj':int(m.group(1)),'key':_lua_key(m.group(2)),'src':int(m.group(3))})
    for m in re.finditer(r'R\[(\d+)\]\s*\[\s*(R\[\d+\]|"(?:\\.|[^"\\])*"|-?\d+(?:\.\d+)?)\s*\]\s*=\s*(nil|true|false|-?\d+(?:\.\d+)?|"(?:\\.|[^"\\])*")',body):
        ir.append({'op':'SETTABLEK','obj':int(m.group(1)),'key':_lua_key(m.group(2)),'value':m.group(3)})

    # Arithmetic/comparisons and unary operations.
    binrx=re.compile(r'R\[(\d+)\]\s*=\s*R\[(\d+)\]\s*(==|~=|<=|>=|<|>|\+|-|\*|/|%|\^|\.\.)\s*R\[(\d+)\]')
    for m in binrx.finditer(body):
        ir.append({'op':'BINOP','dst':int(m.group(1)),'operator':m.group(3),'a':int(m.group(2)),'b':int(m.group(4))})
    unrx=re.compile(r'R\[(\d+)\]\s*=\s*(-|not\s+|#)R\[(\d+)\]')
    for m in unrx.finditer(body):
        ir.append({'op':'UNARY','dst':int(m.group(1)),'operator':m.group(2).strip(),'src':int(m.group(3))})

    # Bitwise primitives used by IronBrew/Luau handlers.
    bitrx=re.compile(r'R\[(\d+)\]\s*=\s*(band|bor|bxor|lshift|rshift)\(\s*R\[(\d+)\]\s*,\s*R\[(\d+)\]\s*\)')
    for m in bitrx.finditer(body):
        ir.append({'op':'BITOP','dst':int(m.group(1)),'operator':m.group(2),'a':int(m.group(3)),'b':int(m.group(4))})

    # MOVE after more specific forms.
    for m in re.finditer(r'R\[(\d+)\]\s*=\s*R\[(\d+)\](?!\s*[\[(])',body):
        ir.append({'op':'MOVE','dst':int(m.group(1)),'src':int(m.group(2))})

    # Literal loads. Do not treat GETGLOBAL string contents as loads because
    # destination overlap is deduplicated below.
    lit_rx=re.compile(r'R\[(\d+)\]\s*=\s*(nil|true|false|-?\d+(?:\.\d+)?|"(?:\\.|[^"\\])*")')
    for m in lit_rx.finditer(body):
        ir.append({'op':'LOADK','dst':int(m.group(1)),'value':m.group(2)})

    # Constant-pool object itself is a VM bootstrap artifact, not protected code.
    if re.fullmatch(r'R\[\d+\]\s*=\s*K',body.strip()):
        return [{'op':'NOP','reason':'constant-pool bootstrap'}]

    # Relative/absolute VM jumps from superinstructions.
    jm=re.findall(r'\bpc\s*=\s*(-?\d+)\b',body)
    if jm and not any(x['op'].startswith('BRANCH_') for x in ir):
        ir.append({'op':'JMP','target':int(jm[-1])+1})
    rel=re.findall(r'\bpc\s*=\s*pc\s*\+\s*(-?\d+)',body)
    if rel:
        ir.append({'op':'JMP','target':pc+int(rel[-1])+1})

    # Stable de-duplication. Fused handlers can match generic and specific forms.
    seen=set(); clean=[]
    priority={'GETGLOBAL':100,'SETGLOBAL':100,'METHODCALL':95,'CLOSURE':95,'CALL':90,
              'GETTABLE':80,'SETTABLE':80,'SETTABLEK':80,'BITOP':75,'BINOP':70,'UNARY':70,
              'GETUPVAL':70,'SETUPVAL':70,'NEWTABLE':70,'META':60,'MOVE':50,
              'LOADK':40,'BRANCH_TRUE':110,'BRANCH_FALSE':110,'JMP':110,'RETURN':110,'NOP':1}
    ir.sort(key=lambda x:-priority.get(x['op'],10))
    written=set()
    for x in ir:
        dst=x.get('dst')
        # Suppress generic write operations to a destination already described
        # by a more specific op from this same handler.
        if dst is not None and dst in written and x['op'] in {'MOVE','LOADK','GETTABLE','BINOP','UNARY'}:
            continue
        key=json.dumps(x,sort_keys=True,default=str)
        if key in seen: continue
        seen.add(key); clean.append(x)
        if dst is not None and x['op'] not in {'NOP'}: written.add(dst)

    if not clean:
        # Assignments touching only interpreter scratch variables are not part of
        # the protected program.  They implement the VM's own call/return stack.
        scratch=r'(?:di|dj|dk|dl|dm|dn|_do|dr|ds|dg|df|dz|ea|eb|ec|ed|ee|ef|eg|eh|ei|ej)'
        stripped=re.sub(r'\blocal\s+','',body).strip(' ;')
        if stripped and not re.search(r'R\[|ENV|UPVALUES|CHILDREN|META|bk\(',stripped):
            if all(re.fullmatch(scratch+r'\s*=.*',x.strip()) for x in stripped.split(';') if x.strip()):
                clean=[{'op':'NOP','reason':'VM interpreter bookkeeping'}]
            else:
                clean=[{'op':'UNLIFTED','source':body.strip()}]
        else:
            clean=[{'op':'UNLIFTED','source':body.strip()}]
    return clean


def build_ir_program(src: str, protos: list[dict[str, Any]]):
    vmctx=build_vm_context(src,protos)
    enum=vmctx['enum']; pcname=vmctx['pcname']; symbols=vmctx['symbols']; compiled=vmctx['compiled']
    opcode_test=re.compile(r'\b(?:if|elseif)\s+'+re.escape(enum)+r'\s*(?:[<>=~])')
    program=[]
    handler_cache={}
    for proto in protos:
        ins=[]
        for row in proto['instructions']:
            op=row.get('opcode')
            if not isinstance(op,(int,float)): continue
            opi=int(op)
            template=handler_cache.get(opi)
            if template is None:
                template=resolve_dispatch_tree(compiled,opi)
                handler_cache[opi]=template
            if opcode_test.search(template):
                lifted=[{'op':'UNLIFTED','source':f'unresolved randomized handler {opi}'}]
            else:
                body=specialize(template,row,symbols,pcname,enum)
                lifted=lift_handler(body,row,proto,src,symbols)
            ins.append({'pc':int(row['pc']),'vm_opcode':opi,'ir':lifted})
        program.append({'pid':proto['pid'],'meta':proto['meta'],'instructions':ins})
    return program


def _successors(inst: dict[str, Any], maxpc: int) -> list[int]:
    pc=inst['pc']; ops=inst['ir']
    for x in ops:
        if x['op']=='RETURN': return []
    for x in ops:
        if x['op'] in {'BRANCH_TRUE','BRANCH_FALSE'}:
            return [x['target'],x['fallthrough']]
    for x in ops:
        if x['op']=='JMP': return [x['target']]
    return [pc+1] if pc<maxpc else []


def build_cfg(proto_ir: dict[str, Any]):
    items={x['pc']:x for x in proto_ir['instructions']}
    if not items: return []
    maxpc=max(items)
    succ={pc:_successors(x,maxpc) for pc,x in items.items()}
    pred={pc:set() for pc in items}
    for pc,ss in succ.items():
        for t in ss:
            if t in pred: pred[t].add(pc)
    leaders={min(items)}
    for pc,ss in succ.items():
        if len(ss)!=1 or (ss and ss[0]!=pc+1):
            leaders.update(t for t in ss if t in items)
            if pc+1 in items: leaders.add(pc+1)
    for pc,ps in pred.items():
        if len(ps)>1: leaders.add(pc)
    assigned=set(); blocks=[]
    for start in sorted(leaders):
        if start in assigned or start not in items: continue
        pcs=[]; cur=start
        while cur in items and cur not in assigned:
            assigned.add(cur); pcs.append(cur)
            ss=succ[cur]
            if len(ss)!=1 or not ss or ss[0]!=cur+1: break
            nxt=cur+1
            if nxt in leaders and nxt!=start: break
            cur=nxt
        blocks.append({'id':start,'pcs':pcs})
    for pc in sorted(items):
        if pc not in assigned: blocks.append({'id':pc,'pcs':[pc]})
    block_of={pc:b['id'] for b in blocks for pc in b['pcs']}
    for b in blocks:
        end=b['pcs'][-1]
        b['succ']=[block_of.get(x,x) for x in succ[end] if x in items]
    return blocks


def _lit(v: str) -> str:
    return v


def emit_devirtualized_lua(program: list[dict[str, Any]]) -> str:
    """Emit devirtualized Lua from canonical IR without prototype banners/root wrappers."""

    def global_expr(name: str) -> str:
        if re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', name or ''):
            return name
        return f'ENV[{json.dumps(name)}]'

    def key_expr(key, value_fn) -> str:
        if isinstance(key, dict):
            if key.get('kind') == 'reg':
                return '[' + value_fn(key['value']) + ']'
            raw = str(key.get('value', 'nil'))
        else:
            raw = str(key)
        try:
            decoded = json.loads(raw)
            if isinstance(decoded, str) and re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', decoded):
                return '.' + decoded
        except Exception:
            pass
        return '[' + raw + ']'

    def recv_expr(s: str) -> str:
        s = s.strip()
        if re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*', s):
            return s
        if re.fullmatch(r'v\d+', s):
            return s
        return '(' + s + ')'

    out = [
        '-- https://discord.gg/ztjcsnM6H8',
        '',
        'local ENV = (getfenv and getfenv()) or _ENV',
        ''
    ]

    total_unlifted = 0
    total_ops = 0
    if not program:
        return '\n'.join(out) + '\n'

    root_pid = program[0]['pid']
    children = [p for p in program if p['pid'] != root_pid]
    ordered = children + [program[0]]

    if children:
        out.append('local ' + ', '.join(f'fn_{p["pid"]}' for p in children))
        out.append('')

    for proto in ordered:
        pid = proto['pid']
        is_root = pid == root_pid
        items = {x['pc']: x for x in proto['instructions']}
        blocks = build_cfg(proto)
        indent = '' if is_root else '    '

        if not is_root:
            out.append(f'fn_{pid} = function(...)')

        out.append(indent + 'local upvalues = {}')
        out.append(indent + 'local metadata = {}')

        regs = sorted({
            n
            for x in proto['instructions']
            for op in x['ir']
            for k, n in op.items()
            if k in {'dst', 'src', 'obj', 'func', 'cond', 'a', 'b'} and isinstance(n, int)
        })
        for i in range(0, len(regs), 24):
            out.append(indent + 'local ' + ', '.join(f'v{n}' for n in regs[i:i+24]))
        if regs:
            out.append('')

        block_of = {pc: b['id'] for b in blocks for pc in b['pcs']}
        if blocks:
            out.append(indent + 'local ' + ', '.join(f'B{b["id"]}' for b in blocks))
            out.append('')

        for b in blocks:
            bid = b['id']
            out.append(indent + f'B{bid} = function()')
            bindent = indent + '    '
            expr: dict[int, str] = {}

            def val(arg):
                if isinstance(arg, dict):
                    if arg.get('kind') == 'reg':
                        return expr.get(arg['value'], f'v{arg["value"]}')
                    return str(arg.get('value', 'nil'))
                if isinstance(arg, int):
                    return expr.get(arg, f'v{arg}')
                return str(arg)

            terminated = False

            for pc in b['pcs']:
                for op in items[pc]['ir']:
                    total_ops += 1
                    k = op['op']

                    if k == 'NOP':
                        continue
                    if k == 'LOADK':
                        expr[op['dst']] = _lit(op['value'])
                        continue
                    if k == 'GETGLOBAL':
                        expr[op['dst']] = global_expr(op['name'])
                        continue
                    if k == 'MOVE':
                        expr[op['dst']] = val(op['src'])
                        continue
                    if k == 'META':
                        expr[op['dst']] = 'metadata'
                        continue
                    if k == 'GETUPVAL':
                        expr[op['dst']] = f'upvalues[{op["idx"]}]'
                        continue
                    if k == 'GETTABLE':
                        expr[op['dst']] = recv_expr(val(op['obj'])) + key_expr(op['key'], val)
                        continue
                    if k == 'BITOP':
                        expr[op['dst']] = f'bit32.{op["operator"]}({val(op["a"])}, {val(op["b"])})'
                        continue
                    if k == 'BINOP':
                        expr[op['dst']] = f'({val(op["a"])} {op["operator"]} {val(op["b"])})'
                        continue
                    if k == 'UNARY':
                        sep = ' ' if op['operator'] == 'not' else ''
                        expr[op['dst']] = f'({op["operator"]}{sep}{val(op["src"])})'
                        continue
                    if k == 'CLOSURE':
                        expr[op['dst']] = f'fn_{op["child"]}'
                        continue
                    if k == 'NEWTABLE':
                        out.append(bindent + f'v{op["dst"]} = {{}}')
                        expr[op['dst']] = f'v{op["dst"]}'
                        continue
                    if k == 'SETGLOBAL':
                        out.append(bindent + f'{global_expr(op["name"])} = {val(op["src"])}')
                        continue
                    if k == 'SETUPVAL':
                        out.append(bindent + f'upvalues[{op["idx"]}] = {val(op["src"])}')
                        continue
                    if k == 'SETTABLE':
                        obj = recv_expr(val(op['obj']))
                        out.append(bindent + f'{obj}{key_expr(op["key"], val)} = {val(op["src"])}')
                        continue
                    if k == 'SETTABLEK':
                        obj = recv_expr(val(op['obj']))
                        out.append(bindent + f'{obj}{key_expr(op["key"], val)} = {op["value"]}')
                        continue
                    if k == 'CALL':
                        args = ', '.join(val(x) for x in op['args'])
                        call = f'{recv_expr(val(op["func"]))}({args})'
                        if op.get('dst') is None:
                            out.append(bindent + call)
                        else:
                            out.append(bindent + f'v{op["dst"]} = {call}')
                            expr[op['dst']] = f'v{op["dst"]}'
                        continue
                    if k == 'METHODCALL':
                        args = ', '.join(val(x) for x in op['args'])
                        obj = recv_expr(val(op['obj']))
                        call = f'{obj}:{op["method"]}({args})'
                        if op.get('dst') is None:
                            out.append(bindent + call)
                        else:
                            out.append(bindent + f'v{op["dst"]} = {call}')
                            expr[op['dst']] = f'v{op["dst"]}'
                        continue
                    if k == 'RETURN':
                        values = ', '.join(val(x) for x in op['values'])
                        out.append(bindent + 'return' + ((' ' + values) if values else ''))
                        terminated = True
                        continue
                    if k in {'BRANCH_TRUE', 'BRANCH_FALSE'}:
                        cond = val(op['cond'])
                        t = block_of.get(op['target'], op['target'])
                        f = block_of.get(op['fallthrough'], op['fallthrough'])
                        if k == 'BRANCH_FALSE':
                            cond = f'not ({cond})'
                        out.append(bindent + f'if {cond} then return B{t}() else return B{f}() end')
                        terminated = True
                        continue
                    if k == 'JMP':
                        out.append(bindent + f'return B{block_of.get(op["target"], op["target"])}()')
                        terminated = True
                        continue
                    if k == 'UNLIFTED':
                        total_unlifted += 1
                        out.append(bindent + '-- UNLIFTED: ' + safe_utf8_text(op['source']).replace('\n', ' ')[:500])
                        continue

            if not terminated:
                if b['succ']:
                    out.append(bindent + f'return B{b["succ"][0]}()')
                else:
                    out.append(bindent + 'return')
            out.append(indent + 'end')
            out.append('')

        if blocks:
            if is_root:
                out.append(f'return B{blocks[0]["id"]}()')
            else:
                out.append(f'    return B{blocks[0]["id"]}()')

        if not is_root:
            out.append('end')
        out.append('')

    out.append(f'-- Lift summary: {total_ops} canonical operations, {total_unlifted} residual handlers.')
    return '\n'.join(out) + '\n'


def _resolve_exe(value: str):
    return shutil.which(value) or (str(Path(value).resolve()) if Path(value).exists() else None)


def run_capture(src: str, work: Path, luau: str, timeout: int):
    patched=work/'instrumented_capture.luau'
    patched.write_text(instrument(src),encoding='utf-8')
    exe=_resolve_exe(luau)
    if not exe:
        raise RuntimeError('official Luau CLI not found; put luau.exe next to cli.py or pass --luau C:\\path\\to\\luau.exe')
    cp=subprocess.run([exe,str(patched)],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,errors='replace',timeout=timeout)
    blocks=parse_capture(cp.stdout)
    if not blocks:
        tail='\n'.join(cp.stdout.splitlines()[-30:]).strip()
        if cp.returncode != 0:
            raise RuntimeError('instrumented Luau failed before capture:\n'+(tail or f'luau exit code {cp.returncode}'))
        raise RuntimeError('capture returned no decoded prototypes'+(('\n'+tail) if tail else ''))
    return blocks


def safe_utf8_text(value):
    if not isinstance(value, str): value=str(value)
    return value.encode('utf-8','backslashreplace').decode('utf-8')


def write_utf8(path, value):
    Path(path).write_text(safe_utf8_text(value),encoding='utf-8')


def main():
    ap=argparse.ArgumentParser(prog='ib1-deobf',description='IronBrew1 VM devirtualizer')
    ap.add_argument('input',help='IronBrew1-obfuscated .lua/.luau/.txt file')
    ap.add_argument('-o','--out',default='.',help='output directory (default: current directory)')
    ap.add_argument('--luau',default='luau.exe' if os.name=='nt' else 'luau',help='official Luau CLI executable')
    ap.add_argument('--timeout',type=int,default=300,help='safe decode timeout in seconds')
    ap.add_argument('--emit-ir',action='store_true',help='also write canonical_ir.json for debugging')
    a=ap.parse_args()
    inp=Path(a.input).resolve(); outdir=Path(a.out).resolve(); outdir.mkdir(parents=True,exist_ok=True)
    target=outdir/'readable_deobfuscated.lua'
    if not inp.is_file(): raise SystemExit(f'[-] input not found: {inp}')
    src=inp.read_text(encoding='utf-8',errors='replace')
    if not detect(src): raise SystemExit('[-] input does not look like this IronBrew1 family')

    print('[1/5] locating randomized IronBrew1 VM')
    try:
        d=dispatcher_region(src); syms=analyze_symbols(src)
        print(f'      enum={d["enum"]} pc={d["pc"]} stack={syms["stack"]}')
    except Exception as e: raise SystemExit(f'[-] VM analysis failed: {e}')

    print('[2/5] decoding prototype tables')
    try:
        with tempfile.TemporaryDirectory(prefix='ib1deobf_') as td:
            blocks=run_capture(src,Path(td),a.luau,a.timeout)
    except Exception as e: raise SystemExit(f'[-] capture failed: {e}')

    print('[3/5] recovering VM bytecode')
    protos=[]
    for b in blocks:
        try: protos.append(extract_proto(b))
        except Exception as e: print(f'[!] prototype {b.get("pid")}: {e}')
    if not protos: raise SystemExit('[-] decoded zero prototypes')
    total=sum(len(p['instructions']) for p in protos)
    print(f'      {len(protos)} prototypes / {total} VM instructions')

    print('[4/5] lifting randomized handlers to canonical IR')
    program=build_ir_program(src,protos)
    canon=sum(len(x['ir']) for p in program for x in p['instructions'])
    residual=sum(1 for p in program for x in p['instructions'] for op in x['ir'] if op['op']=='UNLIFTED')
    print(f'      {canon} canonical ops / {residual} residual handlers')

    print('[5/5] building CFG and emitting devirtualized Lua')
    readable=emit_devirtualized_lua(program)
    write_utf8(target,readable)
    if a.emit_ir:
        write_utf8(outdir/'canonical_ir.json',json.dumps(program,ensure_ascii=True,indent=2,default=str))
    print(f'[+] wrote: {target}')


if __name__=='__main__':
    main()
