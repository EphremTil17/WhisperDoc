# Benchmarks

Measurements behind WhisperDoc's defaults. Each page says how it was measured and how to run it again. A pull request that changes a default (an engine, a model, a style's prompt, the routing) should come with a run of the matching benchmark.

| Page | What it decides |
|---|---|
| [Speech engines](#speech-engines) (below) | Whisper or Parakeet on your own server |
| [Parakeet on a desktop GPU](../../backend/engine/PARAKEET_BENCHMARK.md) | parakeet.cpp end to end on an RTX 3060 Ti, VRAM, long audio |
| [OpenRouter speech models](#openrouter-speech-models) (below) | The default OpenRouter speech model |
| [Rewrite models](rewrite_models.md) | The model and host routing for output styles on OpenRouter |
| [Tech style prompt](technical_prompt.md) | The Tech style's prompt (v3.2 against v3.3) |
| [Professional style prompts](professional_prompt_results.md) | The Pro style's prompt (v3.0) |
| [Custom email style](custom_email_style_results.md) | Not a built-in style: drafts for a custom style that writes emails, kept as an example of tuning one |

## Speech engines

Published model-level figures from the [Open ASR Leaderboard](https://huggingface.co/spaces/hf-audio/open_asr_leaderboard); they leave out WhisperDoc's own overhead.

| Engine | Model | WER ↓ | RTFx ↑ | Language | VRAM (fp16) |
|---|---|---|---|---|---|
| **Parakeet** | `nvidia/parakeet-tdt-0.6b-v2` | **6.05%** | **3,386** | English | ~2.4 GB |
| **Whisper** | `openai/whisper-large-v3-turbo` | 7.83% | 200 | Multilingual | ~3.5 GB |

End to end on an RTX 3060 Ti, a 9.16-second clip took a median of 74.6 ms with parakeet.cpp and 319.4 ms with Whisper Turbo, HTTP included ([report](../../backend/engine/PARAKEET_BENCHMARK.md)).

Research to watch:

- [LiteASR](https://github.com/efeslab/LiteASR) (EMNLP 2025) compresses Whisper's encoder by about a third with almost no accuracy loss. It needs Hugging Face Transformers today; CTranslate2 support for low-rank layers would let the Whisper engine use it.
- [CrisperWhisper](https://github.com/nyrahealth/CrisperWhisper) (INTERSPEECH 2024) is a verbatim Whisper Large v3 (6.66% average WER against 7.7%) that marks fillers. A [CTranslate2 conversion](https://huggingface.co/nyrahealth/faster_CrisperWhisper) exists; it is licensed CC-BY-NC-4.0 (non-commercial).

## OpenRouter speech models

Release to text, median, for 3 s / 14 s / 38 s clips with zero data retention, measured from one desk on 2026-11-23. Word error rates are [Artificial Analysis](https://artificialanalysis.ai/speech-to-text)'s, snapshotted the same day in `speech_model_accuracy.dart`.

| Model | Word error | Release to text |
|---|---|---|
| AssemblyAI Universal-3.5 Pro | 3.0% | 237 / 261 / 367 ms |
| Microsoft MAI-Transcribe 2 (default) | 2.0% | 473 / 614 / 700 ms |
| NVIDIA Nemotron 3.5 Transcribe | 3.4% | 470 / 680 / 1102 ms |
| Groq direct, Whisper Large v3 Turbo (for comparison) | 4.6% | 190 / 225 / 334 ms |

The app shows each model's live latency in its picker, from OpenRouter's own last 30 minutes of traffic.

## Running the style benchmarks

`scripts/benchmark_prompts.py` sends exactly what the client sends: the style's prompt read from `dictation_profile.dart`, the routing read from `app_constants.dart`, and transcripts written the way speech recognition hands them over. Keys come from `GROQ_API_KEY` / `OPENROUTER_API_KEY` (or `--env-file`) and are never printed.

```bash
python scripts/benchmark_prompts.py --help
```
