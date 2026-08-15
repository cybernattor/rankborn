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
    dur = 0.18
    n = int(dur * RATE)
    t = np.linspace(0, dur, n, endpoint=False)
    
    # === LAYER 1: Noise burst (the main "CRACK") ===
    raw_noise = np.random.uniform(-1.0, 1.0, n)
    # Hard gate: full volume for first 1ms, then fast decay
    noise_env = np.zeros(n)
    gate_samples = int(0.001 * RATE)
    decay_samples = int(0.04 * RATE)
    noise_env[:gate_samples] = 1.0
    end = min(gate_samples + decay_samples, n)
    noise_env[gate_samples:end] = np.linspace(1.0, 0.0, end - gate_samples)
    noise_burst = raw_noise * noise_env * 0.8
    
    # === LAYER 2: Mid body (rifle snap, not boom) ===
    boom = np.sin(2 * np.pi * 150 * t) * np.exp(-t * 30) * 0.4
    boom += np.sin(2 * np.pi * 200 * t) * np.exp(-t * 40) * 0.3
    
    # === LAYER 3: High crack (supersonic snap) ===
    crack = np.sin(2 * np.pi * 600 * t) * np.exp(-t * 60) * 0.5
    crack += np.sin(2 * np.pi * 1000 * t) * np.exp(-t * 80) * 0.3
    
    # === LAYER 4: Metal ring (brief barrel resonance) ===
    ring = np.sin(2 * np.pi * 2800 * t) * np.exp(-t * 50) * 0.06
    
    # === LAYER 5: Short reverb ===
    tail = np.zeros(n)
    for delay_ms in [10, 22, 40]:
        d = int(delay_ms / 1000.0 * RATE)
        gain = 0.08 * np.exp(-delay_ms / 25.0)
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

out_dir = os.path.join(os.path.dirname(os.path.dirname(__file__)), "assets", "audio")
os.makedirs(out_dir, exist_ok=True)

save_wav(os.path.join(out_dir, "shoot.wav"), gen_shoot())
print("shoot.wav")
save_wav(os.path.join(out_dir, "empty.wav"), gen_empty())
print("empty.wav")
print("Done.")
