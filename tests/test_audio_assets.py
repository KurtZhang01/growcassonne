from array import array
from pathlib import Path
import math
import sys
import unittest
import wave


class AudioAssets(unittest.TestCase):
    def test_pcm_assets(self):
        folder = Path(__file__).resolve().parents[1] / "assets" / "audio"
        files = list(folder.glob("*.wav"))
        self.assertEqual(len(files), 19)
        for path in files:
            with self.subTest(name=path.name), wave.open(str(path), "rb") as source:
                self.assertEqual(source.getframerate(), 24000)
                self.assertEqual(source.getsampwidth(), 2)
                data = array("h", source.readframes(source.getnframes()))
                if sys.byteorder != "little":
                    data.byteswap()
                peak = max(abs(value) for value in data) / 32767
                rms = math.sqrt(sum((value / 32767) ** 2 for value in data) / len(data))
                self.assertGreater(rms, 0.003, "Audio must not be silent")
                self.assertLessEqual(peak, 0.651, "Assets must retain mixing headroom")
                if path.stem in {"rain", "storm", "sand", "dry"}:
                    self.assertEqual(source.getnchannels(), 2)
                    self.assertEqual(source.getnframes(), 12 * 24000)
                    for channel in range(2):
                        signal = data[channel::2]
                        self.assertLess(abs(signal[-1] - signal[0]) / 32767, 0.25)
                else:
                    self.assertEqual(source.getnchannels(), 1)
                    self.assertLess(abs(data[0]), 8)
                    self.assertLess(abs(data[-1]), 50)


if __name__ == "__main__":
    unittest.main()
