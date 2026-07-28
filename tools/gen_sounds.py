import numpy as np
import struct
import os

RATE = 44100

def save_wav(path, samples, rate=RATE):
    samples = np.clip(samples, -1.0, 1.0)
    data = (samples * 32767).astype(np.int16)
    n = len(data)
    with open(path, 'wb') as f:
        f.write(b'RIFF')
        f.write(struct.pack('<I', 36 + n * 2))
        f.write(b'WAVE')
        f.write(b'fmt ')
        f.write(struct.pack('<IHHIIHH', 16, 1, 1, rate, rate * 2, 2, 16))
        f.write(b'data')
        f.write(struct.pack('<I', n * 2))
        f.write(data.tobytes())

def noise(n):
    return np.random.uniform(-1.0, 1.0, n)

def sine(freq, t):
    return np.sin(2.0 * np.pi * freq * t)

def envelope(n, attack, hold, decay, sr=RATE):
    e = np.zeros(n)
    a_samples = int(attack * sr)
    h_samples = int(hold * sr)
    d_samples = int(decay * sr)
    idx = 0
    # Attack
    seg = min(a_samples, n - idx)
    e[idx:idx+seg] = np.linspace(0, 1, seg)
    idx += seg
    # Hold
    seg = min(h_samples, n - idx)
    e[idx:idx+seg] = 1.0
    idx += seg
    # Decay
    seg = min(d_samples, n - idx)
    e[idx:idx+seg] = np.linspace(1, 0, seg)
    idx += seg
    return e

def gen_shoot():
    """Rifle shot: low boom + mid crack + high hiss + reverb tail"""
    dur = 0.15
    n = int(dur * RATE)
    t = np.linspace(0, dur, n)
    
    # Layer 1: Low boom (muzzle blast)
    boom = sine(80, t) * np.exp(-t * 25) * 0.7
    boom += sine(55, t) * np.exp(-t * 20) * 0.4
    
    # Layer 2: Mid crack (supersonic snap)
    crack = sine(400, t) * np.exp(-t * 60) * 0.5
    crack += sine(700, t) * np.exp(-t * 80) * 0.3
    
    # Layer 3: High hiss (gas expansion)
    hiss = noise(n) * np.exp(-t * 100) * 0.2
    
    # Layer 4: Mechanical bolt
    bolt_t = t - 0.015
    bolt = np.where(bolt_t > 0, sine(2200, bolt_t) * np.exp(-bolt_t * 150) * 0.15, 0)
    
    # Reverb tail (simple delay)
    tail = np.zeros(n)
    for d in [0.02, 0.04, 0.07]:
        delay = int(d * RATE)
        if delay < n:
            env = np.exp(-np.linspace(0, 3, n - delay))
            tail[delay:] += (boom[:n-delay] * 0.1 * env)
    
    out = boom + crack + hiss + bolt + tail
    out *= envelope(n, 0.001, 0.01, 0.12)
    return out * 1.5

def gen_reload():
    """Mag eject + mag insert + bolt release"""
    dur = 0.35
    n = int(dur * RATE)
    t = np.linspace(0, dur, n)
    out = np.zeros(n)
    
    # Phase 1: Mag eject (0-0.1s) — slide + click
    seg1_end = int(0.1 * RATE)
    t1 = t[:seg1_end]
    out[:seg1_end] += sine(1800, t1) * np.exp(-t1 * 30) * 0.3
    out[:seg1_end] += noise(seg1_end) * np.exp(-t1 * 40) * 0.15
    
    # Phase 2: Mag insert (0.12-0.22s) — solid thunk
    seg2_start = int(0.12 * RATE)
    seg2_end = int(0.22 * RATE)
    t2 = t[seg2_start:seg2_end] - 0.12
    out[seg2_start:seg2_end] += sine(300, t2) * np.exp(-t2 * 25) * 0.5
    out[seg2_start:seg2_end] += sine(150, t2) * np.exp(-t2 * 20) * 0.4
    out[seg2_start:seg2_end] += noise(seg2_end - seg2_start) * np.exp(-t2 * 35) * 0.1
    
    # Phase 3: Bolt release (0.25-0.32s) — sharp metallic snap
    seg3_start = int(0.25 * RATE)
    seg3_end = int(0.32 * RATE)
    t3 = t[seg3_start:seg3_end] - 0.25
    out[seg3_start:seg3_end] += sine(2800, t3) * np.exp(-t3 * 100) * 0.35
    out[seg3_start:seg3_end] += sine(1400, t3) * np.exp(-t3 * 80) * 0.2
    
    return np.clip(out, -1.0, 1.0)

def gen_hit():
    """Body impact thud"""
    dur = 0.08
    n = int(dur * RATE)
    t = np.linspace(0, dur, n)
    
    thud = sine(60, t) * np.exp(-t * 40) * 0.6
    crack = noise(n) * np.exp(-t * 60) * 0.3
    
    out = thud + crack
    out *= envelope(n, 0.001, 0.005, 0.06)
    return out

def gen_step():
    """Boot on ground — low thump + gravel"""
    dur = 0.07
    n = int(dur * RATE)
    t = np.linspace(0, dur, n)
    
    thump = sine(50, t) * np.exp(-t * 35) * 0.35
    gravel = noise(n) * np.exp(-t * 45) * 0.12
    
    out = thump + gravel
    out *= envelope(n, 0.001, 0.005, 0.05)
    return out

def gen_empty():
    """Dry bolt click — metallic snap"""
    dur = 0.035
    n = int(dur * RATE)
    t = np.linspace(0, dur, n)
    
    click = sine(3500, t) * np.exp(-t * 250) * 0.4
    rattle = sine(1800, t) * np.exp(-t * 180) * 0.2
    
    out = click + rattle
    out *= envelope(n, 0.0005, 0.003, 0.025)
    return out

# Generate all
out_dir = os.path.join(os.path.dirname(__file__), "assets", "audio")
os.makedirs(out_dir, exist_ok=True)

sounds = {
    "shoot.wav": gen_shoot,
    "reload.wav": gen_reload,
    "hit.wav": gen_hit,
    "step.wav": gen_step,
    "empty.wav": gen_empty,
}

for name, fn in sounds.items():
    path = os.path.join(out_dir, name)
    save_wav(path, fn())
    print(f"  {name}")

print("Done.")
