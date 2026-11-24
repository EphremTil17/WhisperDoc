/// How accurate OpenRouter's speech models were, as Artificial Analysis
/// measured them on 2026-11-23: word error rate in percent (AA-WER v2.2,
/// non-streaming; lower is better).
///
/// A fixed snapshot, kept by hand: matching OpenRouter's model ids to
/// Artificial Analysis's names can't be automated reliably, so nothing here
/// is fetched or refreshed. A model missing from it (a new one, or one never
/// measured) shows as not measured; it is never hidden.
///
/// Checked against every Artificial Analysis entry on 2026-11-23. Not
/// measured there, so left out: assemblyai/universal-3-6-pro,
/// elevenlabs/scribe-v2-medical, qwen/qwen3-asr-0.6b, qwen/qwen3-asr-1.7b,
/// moondream/parakeet-ultra and
/// nvidia/nemotron-3.5-asr-streaming-multilingual-0.6b. Also left out:
/// mistralai/voxtral-mini-transcribe, which OpenRouter doesn't tie to a
/// version (Artificial Analysis scores Voxtral Mini Transcribe 2,
/// `voxtral-mini-2602`, at 3.6%). Other leaderboards (e.g. Hugging Face's
/// Open ASR) use different test sets and score the same model differently,
/// so their figures are not mixed into this column.
abstract final class SpeechModelAccuracy {
  static const String source = 'Artificial Analysis';
  static const String measuredOn = '2026-11-23';

  /// OpenRouter model id to word error rate.
  static const Map<String, double> wordErrorRate = {
    'microsoft/mai-transcribe-2': 2.0,
    'mistralai/voxtral-small-transcribe-3-0': 2.1,
    'elevenlabs/scribe-v2': 2.2,
    'mistralai/voxtral-mini-transcribe-3-0': 2.2,
    'x-ai/grok-stt-2.0': 2.3,
    'microsoft/mai-transcribe-1.5': 2.4,
    'google/gemini-3.5-transcribe': 2.6,
    'mistralai/voxtral-small-24b-2507-stt': 2.8,
    'assemblyai/universal-3-5-pro': 3.0,
    'openai/gpt-transcribe': 3.3,
    'nvidia/nemotron-3.5-transcribe': 3.4,
    'mistralai/voxtral-mini-3b-2507': 3.8,
    'openai/gpt-4o-transcribe': 4.0,
    'openai/whisper-1': 4.1,
    'google/chirp-3': 4.3,
    'nvidia/parakeet-tdt-0.6b-v3': 4.5,
    'openai/gpt-4o-mini-transcribe': 4.5,
    'openai/whisper-large-v3': 4.5,
    'openai/whisper-large-v3-turbo': 4.6,
    'deepgram/nova-3': 5.2,
  };
}
