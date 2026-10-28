"""Ищет чистые тоны (ноту «маримбы») в звуках: python3 tools/check_tonal.py assets/audio/*.wav
Окно считается тональным, если пик в 1,2–9 кГц выше медианы спектра больше чем в 40 раз.
У шума это 10–30, у синуса — тысячи. Нужен numpy."""
import sys, wave, numpy as np
def load(p):
    w=wave.open(p); n=w.getnframes(); d=np.frombuffer(w.readframes(n),dtype=np.int16).astype(float)/32768
    if w.getnchannels()==2: d=d[::2]
    return d,w.getframerate()
def report(p, win_ms=25, thr=40.0):
    d,sr=load(p); n=int(sr*win_ms/1000); n+=n%2
    out=[]
    for s in range(0,len(d)-n,n//2):
        seg=d[s:s+n]
        if np.sqrt(np.mean(seg**2))<0.02: continue
        sp=np.abs(np.fft.rfft(seg*np.hanning(n))); f=np.fft.rfftfreq(n,1/sr)
        m=(f>1200)&(f<9000); b=sp[m]; fb=f[m]
        r=b.max()/np.median(b)
        if r>thr: out.append((round(s/sr,3),int(fb[b.argmax()]),round(r)))
    return out
for p in sys.argv[1:]:
    r=report(p); print(p.split('/')[-1], len(r),'tonal windows', r[:14])
