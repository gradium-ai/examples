# Third-party notices

## RepCounterSDK

Parts of the rep-counting logic in `RepCoachCore` are adapted from
[RepCounterSDK](https://github.com/NazarKozak/RepCounterSDK): the hysteresis counter in
`RepCounter.swift` and the joint-angle math in `Pose.swift`.

```
MIT License

Copyright (c) 2026 Nazar Kozak

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Phonon (xn-ptts)

The voice uses the `PhononTTS` Swift package from
[gradium-ai/xn-ptts](https://github.com/gradium-ai/xn-ptts), fetched by Swift Package Manager and
not copied into this project. Its code is licensed MIT or Apache-2.0. The Phonon model weights
are not in this repository: `scripts/fetch-model.sh` downloads Phonon 31M
([`gradium/phonon-31m-en`](https://huggingface.co/gradium/phonon-31m-en)) as Core ML from the
xn-ptts release. Its weights and voices belong to Gradium and are licensed Apache-2.0.
