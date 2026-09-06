"""Generate original, deterministic PCM sound effects using only the standard library."""

from array import array
from pathlib import Path
import math
import random
import sys
import wave

RATE = 24000
ROOT = Path(__file__).resolve().parent
TAU = math.tau


def write(name, channels, peak=0.65):
    maximum = max(abs(value) for channel in channels for value in channel) or 1.0
    gain = min(1.0, peak / maximum)
    pcm = array("h", (int(max(-1, min(1, value * gain)) * 32767)
                     for frame in zip(*channels) for value in frame))
    if sys.byteorder != "little":
        pcm.byteswap()
    with wave.open(str(ROOT / (name + ".wav")), "wb") as output:
        output.setnchannels(len(channels))
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(pcm.tobytes())


def cue(name, duration, notes=(), rustle=0.0, knocks=()):
    rng = random.Random(name)
    samples = []
    low = 0.0
    for i in range(int(duration * RATE)):
        t = i / RATE
        noise = rng.uniform(-1, 1)
        low += (noise - low) * 0.16
        value = rustle * (noise - low) * math.sin(math.pi * min(t / duration, 1)) ** 2
        for start, frequency, decay, volume in notes:
            age = t - start
            if age >= 0:
                envelope = min(1, age / 0.009) * math.exp(-age / decay)
                value += volume * envelope * (math.sin(TAU * frequency * age)
                    + 0.24 * math.sin(TAU * frequency * 2.01 * age) * math.exp(-age * 12))
        for start, volume in knocks:
            age = t - start
            if age >= 0:
                value += volume * math.exp(-age * 32) * (low * 1.5 + math.sin(TAU * 105 * age))
        fade = min(1, t / 0.008, max(0, (duration - t) / 0.06))
        samples.append(value * fade)
    write(name, [samples])


def ambience(name, length=12.0):
    count = int(length * RATE)
    overlap = int(0.35 * RATE)
    channels = []
    for channel in range(2):
        rng = random.Random(name + str(channel))
        slow = medium = fast = 0.0
        values = []
        for i in range(count + overlap):
            t = i / RATE
            noise = rng.uniform(-1, 1)
            slow += 0.008 * (noise - slow)
            medium += 0.05 * (noise - medium)
            fast += 0.38 * (noise - fast)
            gust = 0.76 + 0.16 * math.sin(TAU * t / length) + 0.08 * math.sin(TAU * t * 3 / length)
            if name == "rain":
                value = (fast * 0.60 + medium * 0.65 + noise * 0.12) * gust
            elif name == "storm":
                value = (slow * 2.5 + medium * 0.50) * gust
                value += 0.025 * math.sin(TAU * 53 * t) * (0.5 + 0.5 * math.sin(TAU * t / length)) ** 6
            elif name == "sand":
                value = (medium * 0.65 + fast * 0.28) * gust
                value += (noise - fast) * 0.05 * max(0, math.sin(TAU * t * 5 / length))
            else:
                value = (slow * 1.25 + medium * 0.18) * gust
            values.append(value)
        # Overlap the tail with the lead-in, then loop back to the next source sample.
        loop = values[overlap:count]
        for i in range(overlap):
            blend = i / overlap
            loop.append(values[count + i] * (1 - blend) + values[i] * blend)
        channels.append(loop)
    write(name, channels, 0.5)


if __name__ == "__main__":
    cue("select", .12, [(0, 720, .026, .18)], rustle=.08)
    cue("draw", .25, [(0.09, 480, .04, .12)], rustle=.34)
    cue("cancel", .18, [(0, 540, .035, .18), (.06, 360, .035, .14)])
    cue("rotate", .12, [(0, 620, .025, .13)], knocks=[(0, .10)])
    cue("seed", .65, [(0, 523.25, .10, .28), (.08, 783.99, .12, .22), (.18, 1046.5, .10, .15)], rustle=.04)
    cue("develop", .5, [(0.15, 261.63, .12, .16)], rustle=.10, knocks=[(0, .30), (.13, .19)])
    cue("build", .8, [(.14, 392, .17, .20), (.24, 523.25, .20, .18), (.32, 659.25, .20, .14)], knocks=[(0, .38), (.09, .16)])
    cue("road", .38, [(0.12, 440, .06, .13)], knocks=[(0, .22), (.08, .18), (.16, .15)])
    cue("weather", .75, [(0, 392, .18, .20), (.12, 587.33, .22, .17)], rustle=.045)
    cue("rainbow", 1.1, [(i*.1, f, .24, .16) for i, f in enumerate([523.25, 659.25, 783.99, 1046.5])])
    cue("warning", .28, [(0, 293.66, .06, .18), (.10, 261.63, .06, .15)])
    cue("reward", .9, [(0, 659.25, .18, .22), (.1, 783.99, .18, .20), (.22, 1046.5, .24, .16)])
    cue("turn", .7, [(0, 392, .15, .18), (.16, 523.25, .2, .20)])
    cue("victory", 1.6, [(i*.16, f, .28, .17) for i, f in enumerate([392, 523.25, 659.25, 783.99, 1046.5])])
    cue("thunder", 2.4, [(0, 49, .48, .25), (.15, 63, .55, .18)], rustle=.055, knocks=[(0, .18)])
    for name in ["rain", "storm", "sand", "dry"]:
        ambience(name)
    print("Generated 15 cues and 4 seamless stereo ambience loops.")
