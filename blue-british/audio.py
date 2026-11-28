import json, os, subprocess, sys
import numpy as np
import soundfile as sf

ROOT=os.path.abspath(sys.argv[1]) if len(sys.argv)>1 else os.path.dirname(os.path.abspath(__file__))
SR=44100; DUR=35.0
with open(os.path.join(ROOT,'lines.json'),encoding='utf8') as f: lines=json.load(f)
mix=np.zeros((int(SR*DUR),2),dtype=np.float32)

def add_tone(freq,start,length,amp,pan=0,partials=(1,.35,.12),decay=2.8):
    a=max(0,int(start*SR)); n=min(int(length*SR),len(mix)-a)
    if n<=0:return
    t=np.arange(n,dtype=np.float32)/SR
    env=np.exp(-decay*t)*(1-np.exp(-45*t))
    sig=sum(k*np.sin(2*np.pi*freq*h*t) for h,k in enumerate(partials,1))*env*amp
    mix[a:a+n,0]+=sig*(1-pan)*.5;mix[a:a+n,1]+=sig*(1+pan)*.5

# Sparse, original brushed-jazz cue: mallet chords, a plucked walking bass and soft brush ticks.
bpm=108; beat=60/bpm
chords=[(0,[392,494,587,698]),(8,[349,440,523,659]),(16,[330,392,494,587]),(24,[392,494,587,698]),(32,[349,440,523,659]),(40,[330,392,494,587]),(48,[392,494,587,698]),(56,[349,440,523,659])]
for bar,notes in chords:
    for i,note in enumerate(notes): add_tone(note,bar*beat+i*.035,.9,.052,(-.4+i*.26),decay=2.1)
for b in range(63):
    start=b*beat
    root=[98,87,82,98,87,82,98,87][b//8]
    if b%2==0: add_tone(root*(1 if b%4==0 else 1.5),start,.42,.075,-.12,partials=(1,.22,.04),decay=5)
    # airy brushed tick, synthesized deterministically
    a=int(start*SR); n=min(1800,len(mix)-a); t=np.arange(n)/SR
    rng=np.random.default_rng(b+71); noise=rng.normal(0,1,n).astype(np.float32)
    env=np.exp(-t*28)*.009; brush=noise*env
    mix[a:a+n,0]+=brush*.8;mix[a:a+n,1]+=brush
# Small ceramic clinks, soft fabric swishes and a bell after the screened beat.
for sec,freq,amp in [(3.4,880,.10),(7.8,1318,.09),(11.5,784,.06),(19.7,698,.05),(27.5,1175,.17),(31.5,988,.08)]:
    add_tone(freq,sec,.45,amp,partials=(1,.5,.18, .05),decay=5)

if len(sys.argv)>1:
    for hit, second in enumerate(np.arange(27.84, 34.5, .245)):
        add_tone(106+16*(hit%2),second,.115,.031,(-.12 if hit%2 else .14),decay=22)
    for second, frequency in [(29.25,294),(30.09,247),(32.80,392),(33.06,294)]:
        add_tone(frequency,second,.22,.065,partials=(1,.41,.06),decay=11)

for item in lines:
    base=os.path.join(ROOT,'out','voice_'+item['id'])
    aiff=base+'.aiff'; wav=base+'.wav'
    subprocess.run(['say','-v','Milena','-r','178','-o',aiff,item['text']],check=True)
    subprocess.run(['ffmpeg','-y','-v','error','-i',aiff,'-ar',str(SR),'-ac','2',wav],check=True)
    voice,sr=sf.read(wav,dtype='float32',always_2d=True)
    if sr!=SR: raise RuntimeError(f'Unexpected voice sample rate: {sr}')
    start=int(item['t']*SR); n=min(len(voice),len(mix)-start)
    mix[start:start+n]+=voice[:n]*.50

peak=np.max(np.abs(mix));
if peak>.89: mix*=.89/peak
sf.write(os.path.join(ROOT,'out','mix.wav'),mix,SR,subtype='PCM_24')
