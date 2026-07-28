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

def gen_shoot():
    dur = 0.25
    n = int(dur * RATE)
    t = np.linspace(0, dur, n, endpoint=False)
    
    # === LAYER 1: Noise burst (the main "BANG") ===
    raw_noise = np.random.uniform(-1.0, 1.0, n)
    # Hard gate: full volume for first 2ms, then fast decay
    noise_env = np.zeros(n)
    gate_samples = int(0.002 * RATE)
    decay_samples = int(0.08 * RATE)
    noise_env[:gate_samples] = 1.0
    end = min(gate_samples + decay_samples, n)
    noise_env[gate_samples:end] = np.linspace(1.0, 0.0, end - gate_samples)
    noise_burst = raw_noise * noise_env * 0.9
    
    # === LAYER 2: Low boom (muzzle blast body) ===
    boom = np.sin(2 * np.pi * 60 * t) * np.exp(-t * 15) * 0.7
    boom += np.sin(2 * np.pi * 45 * t) * np.exp(-t * 12) * 0.5
    
    # === LAYER 3: Mid crack (supersonic snap) ===
    crack = np.sin(2 * np.pi * 500 * t) * np.exp(-t * 50) * 0.4
    crack += np.sin(2 * np.pi * 800 * t) * np.exp(-t * 70) * 0.25
    
    # === LAYER 4: Metal ring (barrel resonance) ===
    ring = np.sin(2 * np.pi * 3200 * t) * np.exp(-t * 40) * 0.08
    
    # === LAYER 5: Reverb tail ===
    tail = np.zeros(n)
    # Simple multi-tap delay
    for delay_ms in [15, 30, 50, 80]:
        d = int(delay_ms / 1000.0 * RATE)
        gain = 0.12 * np.exp(-delay_ms / 40.0)
        if d < n:
            tail[d:] += noise_burst[:n-d] * gain
    
    out = noise_burst + boom + crack + ring + tail
    
    # Normalize
    peak = np.max(np.abs(out))
    if peak > 0:
        out = out / peak * 0.95
    
    return out

def gen_empty():
    dur = 0.04
    n = int(dur * RATE)
    t = np.linspace(0, dur, n, endpoint=False)
    
    # Dry metallic bolt click
    click = np.sin(2 * np.pi * 3000 * t) * np.exp(-t * 200) * 0.5
    click += np.sin(2 * np.pi * 1500 * t) * np.exp(-t * 150) * 0.3
    click += np.random.uniform(-0.15, 0.15, n) * np.exp(-t * 250)
    
    peak = np.max(np.abs(click))
    if peak > 0:
        click = click / peak * 0.8
    return click

out_dir = os.path.join(os.path.dirname(__file__), "assets", "audio")
os.makedirs(out_dir, exist_ok=True)

save_wav(os.path.join(out_dir, "shoot.wav"), gen_shoot())
print("shoot.wav")
save_wav(os.path.join(out_dir, "empty.wav"), gen_empty())
print("empty.wav")
print("Done.")
