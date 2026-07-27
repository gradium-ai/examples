"""Shared GenZ translation bits: multilingual slang glossaries + streaming rewrite.

Gradium's STT is multilingual, so the user can speak any supported language; the
selected language (from the UI picker) chooses which slang glossary and which
in-language system prompt the LLM rewrite uses. Glossary files are loaded per
language and are optional - a missing file just yields an empty glossary.
"""

import json
import os
import pathlib

import aiohttp

# The rewrite runs against any OpenAI-compatible chat-completions endpoint.
# Point LLM_URL at your provider (Gradium-hosted model, OpenAI, Groq, Ollama, …)
# and set LLM_MODEL to the model you want. Auth reuses your GRADIUM_API_KEY.
LLM_URL = os.environ.get("LLM_URL")
LLM_MODEL = os.environ.get("LLM_MODEL", "google/gemma-4-26B-A4B-it")
if not LLM_URL:
    raise RuntimeError(
        "Set LLM_URL to an OpenAI-compatible chat-completions endpoint "
        "(e.g. https://your-provider.example/v1/chat/completions). See README."
    )

_HERE = pathlib.Path(__file__).parent

# lang code -> (display name, glossary filename)
LANGS: dict[str, tuple[str, str]] = {
    "en": ("English", "genz_slang.json"),
    "fr": ("French", "genz_slang.fr.json"),
    "de": ("German", "genz_slang.de.json"),
    "pt": ("Portuguese", "genz_slang.pt.json"),
    "es": ("Spanish", "genz_slang.es.json"),
}
DEFAULT_LANG = "en"

# A short in-language example per language anchors the model's output style.
_EXAMPLES = {
    "en": '- Example: "Hey hello, this is really good" -> "Yo, this slaps, no cap"',
    "fr": "- Exemple : \"Salut, c'est vraiment bien\" -> \"Wesh, c'est chanmé, sur la vie\"",
    "de": '- Beispiel: "Hallo, das ist wirklich gut" -> "Digga, das ist so lit, kein Cap"',
    "pt": '- Exemplo: "Oi, isso é muito bom" -> "Mano, isso é mó top, juro"',
    "es": '- Ejemplo: "Hola, esto está muy bien" -> "Tío, esto es una pasada, te lo juro"',
}


def _load_glossary(fname: str) -> str:
    """Read a slang file into a '- term: meaning' block (empty if missing)."""
    path = _HERE / fname
    if not path.exists():
        return ""
    slang = json.loads(path.read_text())["slang"]
    return "\n".join(f'- {s["term"]}: {s["meaning"]}' for s in slang)


def _build_prompt(language: str, glossary: str, example: str) -> str:
    return f"""You are a live interpreter that translates plain spoken {language} into {language} GenZ slang.

Rewrite the user's sentence in {language} GenZ speak. Ground yourself in this slang glossary:
{glossary}

Rules:
- ALWAYS write your output in {language}. Never switch to another language, except for
  slang loanwords that {language}-speaking GenZ genuinely use.
- Output ONLY the translation. No quotes, no explanations, no emojis.
- Keep it SHORTER or equal in length to the input. Punchy.
- Keep the original meaning intact, just maximally GenZ-ify the delivery.
- The input may be a FRAGMENT of a sentence still being spoken. Translate only
  what is there - NEVER invent a continuation or add words beyond the input.
- You are subtitling ONE continuous stream of speech. When given "translation
  so far", your output is the NEXT PIECE of that same running caption: never
  repeat or rephrase what is already translated, never restart with greetings
  or interjections - it must read as a seamless continuation.
{example}
"""


SYSTEM_PROMPTS: dict[str, str] = {
    code: _build_prompt(name, _load_glossary(fname), _EXAMPLES.get(code, ""))
    for code, (name, fname) in LANGS.items()
}


def system_prompt(lang: str) -> str:
    return SYSTEM_PROMPTS.get(lang, SYSTEM_PROMPTS[DEFAULT_LANG])


async def llm_genz_stream(
    http: aiohttp.ClientSession,
    api_key: str,
    text: str,
    context: str = "",
    lang: str = DEFAULT_LANG,
):
    """Stream GenZ tokens continuing the running caption, in the given language.

    `context` is the GenZ caption so far; the model returns only the
    continuation covering `text`. Low temperature keeps re-translations of a
    growing fragment stable, so the live-updating text doesn't flicker.
    """
    if context:
        prompt = (
            f'GenZ translation so far (do NOT repeat any of it):\n"{context}"\n\n'
            f'Next speech fragment to translate:\n"{text}"\n\n'
            "Continuation:"
        )
    else:
        prompt = text
    # PERF / server-side follow-up: the system prompt (the whole slang glossary,
    # ~1.5k tokens) is byte-identical on every call for a given language, and we
    # fire many calls per utterance. It goes FIRST in `messages` so it forms a
    # stable prefix. If the LLM server has automatic prefix caching enabled,
    # those glossary tokens are cached after the first hit and time-to-first-
    # token stays flat as the bank grows - making per-request term "retrieval"
    # (indexing/RAG) unnecessary at this scale. TODO: confirm prefix caching is
    # ON for the LLM endpoint; that, not the JSON format, is the lever.
    payload = {
        "model": LLM_MODEL,
        "messages": [
            {"role": "system", "content": system_prompt(lang)},
            {"role": "user", "content": prompt},
        ],
        "stream": True,
        "temperature": 0.3,
        "max_tokens": 100,
        "chat_template_kwargs": {"enable_thinking": False},
    }
    headers = {"Authorization": f"Bearer {api_key}"}
    async with http.post(LLM_URL, json=payload, headers=headers) as resp:
        resp.raise_for_status()
        async for raw in resp.content:
            line = raw.decode("utf-8", "ignore").strip()
            if not line.startswith("data:"):
                continue
            data = line[5:].strip()
            if data == "[DONE]":
                break
            delta = json.loads(data)["choices"][0].get("delta", {})
            if tok := delta.get("content"):
                yield tok
