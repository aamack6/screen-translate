import re, unicodedata, sys, json
src=open(__import__("os").path.join(__import__("os").path.dirname(__import__("os").path.abspath(__file__)), "..", "ScreenTranslate", "ListingTerms.swift")).read()
terms=[]
for m in re.finditer(r'Term\(\[(.*?)\], \.(\w+), \.(\w+), "(.*?)"\)', src):
    words=re.findall(r'"(.*?)"', m.group(1))
    terms.append((words,m.group(2),m.group(3),m.group(4)))
neg=re.search(r'negations = \[(.*?)\]',src).group(1)
negs=re.findall(r'"(.*?)"',neg)
def matches(text):
    t=unicodedata.normalize('NFKC',text)
    allw=sorted([(w,tm) for tm in terms for w in tm[0]], key=lambda x:-len(x[0]))
    found=[];covered=[]
    for w,tm in allw:
        start=0
        while True:
            i=t.find(w,start)
            if i<0: break
            start=i+len(w)
            r=(i,i+len(w))
            if any(a<r[1] and r[0]<b for a,b in covered): continue
            rest=t[r[1]:]
            n=[x for x in negs if rest.startswith(x)] if tm[2]=='caution' else []
            ng=max(n,key=len) if n else ''
            covered.append((i,r[1]+len(ng)))
            if ng: mt=(w+ng,tm[1],'good','seller says no: '+tm[3])
            else: mt=(w,tm[1],tm[2],tm[3])
            if not any(f[3]==mt[3] for f in found): found.append(mt)
            break
    return found
if __name__=='__main__':
    print(len(terms),'terms')
    for s in sys.argv[1:]:
        print(s, '->', [(f[0],f[2]) for f in matches(s)])
