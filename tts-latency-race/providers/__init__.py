"""One module per TTS provider, each with the same small contract, so server.py can race any of them.

Most of these clients are adapted from Coval's open benchmark runner,
https://github.com/coval-ai/benchmarks (runner/src/coval_bench/providers/tts, Apache-2.0), so the
wire settings match the numbers on https://benchmarks.coval.ai.

A provider module defines:

    KEYS    tuple of environment variable names, all required (e.g. ("AZURE_SPEECH_KEY", "AZURE_SPEECH_REGION"))
    HOST    the hostname, for the network round-trip shown on the page

    async def open(lane_cfg: dict, keys: dict[str, str]) -> dict
        Connect and send any session setup: everything that does not carry the text. This runs
        before Go, so connect, TLS, the websocket upgrade and setup stay out of the measurement.
        Returns a connection dict with at least "sr", the sample rate of the PCM that run()
        delivers. A websocket provider puts its socket in "ws"; an HTTP provider puts its
        pre-warmed client in "http".

    async def run(lane, text: str, conn: dict) -> None
        Call `await lane.t0()` immediately before the first byte of text goes out, then
        `await lane.audio(pcm)` for every chunk of 16-bit little-endian mono PCM at conn["sr"],
        raise on a provider error, close what open() opened, and finish with `await lane.done()`.

Optional:

    def alive(conn) -> bool     whether a pooled connection can still be used (default: the
                                websocket is open, or the HTTP client is not closed)
    async def close(conn)       drop a pooled connection that was never used

lane_cfg is the lane's entry in server.LANES: label, model, voice, and any provider-specific
fields. Ask every provider for 24 kHz mono PCM when it offers it, so no lane pays for a container
or a decode step.
"""
import importlib

_CACHE = {}


def get(name):
    """The provider module `providers.<name>`, imported once."""
    if name not in _CACHE:
        _CACHE[name] = importlib.import_module(f"{__name__}.{name}")
    return _CACHE[name]
