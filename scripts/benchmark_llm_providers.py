#!/usr/bin/env python3
"""
Benchmark LLM Providers for WhisperDoc Post-Processing Transformation.

Measures Time-to-First-Token (TTFT), Generation Time, Tokens Per Second (TPS),
and Total Wall-Clock Latency across Groq and Cerebras endpoints for speech rewriting.
"""

import argparse
import io
import json
import os
import sys
import time
from typing import Any, Dict, List, Optional, Tuple
import requests

# Ensure UTF-8 output on Windows console
if isinstance(sys.stdout, io.TextIOWrapper):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

# Endpoints
GROQ_BASE_URL = "https://api.groq.com/openai/v1/chat/completions"
CEREBRAS_BASE_URL = "https://api.cerebras.ai/v1/chat/completions"

# Test Profiles & System Prompts
PROFILES = {
    "clean": {
        "name": "Clean & Disfluency Polish",
        "system": (
            "You are a speech-to-text post-processor. Clean the transcript by removing stutters, "
            "verbal filler words (e.g. um, uh, like, you know), and false starts, and fixing "
            "punctuation and capitalization. Preserve the user's original words and meaning exactly. "
            "Output ONLY the cleaned text. Do NOT add preamble, quotes, or commentary."
        ),
        "input": "um so basically what i wanted to say is like we need to update the server because ah the database is kind of slow you know",
    },
    "professional": {
        "name": "Professional Polish",
        "system": (
            "You are an executive speech editor. Rewrite the spoken transcript into concise, "
            "clear, professional workplace English suitable for an email or formal proposal. "
            "Output ONLY the finalized text. Do NOT add preamble, quotes, or commentary."
        ),
        "input": "hey so we ran the numbers for the client and honestly it's looking pretty bad if we don't fix the server churn by next week we're gonna lose them",
    },
    "casual": {
        "name": "Casual Chat Messaging",
        "system": (
            "You are a messaging editor. Format the spoken transcript for friendly, natural "
            "team chat (e.g. Slack or Teams). Keep it natural, human, and conversational. "
            "Output ONLY the finalized message. Do NOT add preamble, quotes, or commentary."
        ),
        "input": "hey john can you please check the pull request when you get a chance no rush thanks so much",
    },
}

# Provider Model Candidates (Exact Active Catalog IDs)
GROQ_MODELS = [
    "openai/gpt-oss-120b",
    "openai/gpt-oss-20b",
    "qwen/qwen3.8-27b",
    "qwen/qwen3.6-27b",
    "groq/compound-mini",
]

CEREBRAS_MODELS = [
    "gpt-oss-120b",
    "qwen-3.8-27b",
    "gemma-4-31b",
]


def run_streaming_benchmark(
    endpoint: str,
    api_key: str,
    model: str,
    system_prompt: str,
    user_input: str,
    timeout_seconds: float = 5.0,
) -> Dict[str, Any]:
    """Execute a single streaming request measuring TTFT, TPS, and Total Wall-Clock."""
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
    }
    payload = {
        "model": model,
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_input},
        ],
        "temperature": 0.1,
        "max_completion_tokens": 256,
        "stream": True,
    }

    t_start = time.perf_counter()
    ttft: Optional[float] = None
    accumulated_text = []
    token_count = 0

    try:
        response = requests.post(
            endpoint,
            headers=headers,
            json=payload,
            stream=True,
            timeout=timeout_seconds,
        )

        if response.status_code != 200:
            return {
                "success": False,
                "status_code": response.status_code,
                "error": response.text[:200],
            }

        for chunk in response.iter_lines(decode_unicode=True):
            if not chunk or not chunk.startswith("data: "):
                continue
            data_str = chunk[6:].strip()
            if data_str == "[DONE]":
                break

            try:
                data_json = json.loads(data_str)
                delta = data_json.get("choices", [{}])[0].get("delta", {})
                content = delta.get("content", "")
                if content:
                    if ttft is None:
                        ttft = (time.perf_counter() - t_start) * 1000.0  # ms
                    accumulated_text.append(content)
                    token_count += 1
            except json.JSONDecodeError:
                continue

        t_end = time.perf_counter()
        total_time_ms = (t_end - t_start) * 1000.0
        gen_time_ms = total_time_ms - (ttft or total_time_ms)
        tps = (token_count / (gen_time_ms / 1000.0)) if gen_time_ms > 0 else 0.0

        return {
            "success": True,
            "status_code": 200,
            "ttft_ms": round(ttft or total_time_ms, 1),
            "generation_ms": round(gen_time_ms, 1),
            "total_ms": round(total_time_ms, 1),
            "token_count": token_count,
            "tps": round(tps, 1),
            "output_text": "".join(accumulated_text).strip(),
        }

    except requests.exceptions.RequestException as e:
        return {
            "success": False,
            "status_code": 0,
            "error": str(e),
        }


def benchmark_provider(
    provider_name: str,
    endpoint: str,
    api_key: str,
    models: List[str],
) -> List[Dict[str, Any]]:
    results = []
    print(f"\n=======================================================")
    print(f"Benchmarking Provider: {provider_name.upper()}")
    print(f"Endpoint: {endpoint}")
    print(f"=======================================================")

    for model in models:
        print(f"\n[Model: {model}]")
        for profile_id, profile in PROFILES.items():
            sys.stdout.write(f"  - Testing Profile '{profile['name']}'... ")
            sys.stdout.flush()

            res = run_streaming_benchmark(
                endpoint=endpoint,
                api_key=api_key,
                model=model,
                system_prompt=profile["system"],
                user_input=profile["input"],
            )

            if res["success"]:
                print(
                    f"OK | Total: {res['total_ms']}ms | TTFT: {res['ttft_ms']}ms | "
                    f"TPS: {res['tps']} ({res['token_count']} tokens)"
                )
                print(f"    Output: \"{res['output_text'][:90]}...\"")
            else:
                print(f"FAILED (Status {res.get('status_code')}): {res.get('error')}")

            results.append({
                "provider": provider_name,
                "model": model,
                "profile": profile_id,
                **res,
            })
    return results


def print_summary_table(results: List[Dict[str, Any]]) -> None:
    print("\n\n" + "=" * 88)
    print(f"{'Provider':<10} | {'Model':<25} | {'Profile':<12} | {'TTFT(ms)':<8} | {'Total(ms)':<9} | {'TPS':<7} | {'Status'}")
    print("-" * 88)

    for r in results:
        if r.get("success"):
            print(
                f"{r['provider']:<10} | {r['model']:<25} | {r['profile']:<12} | "
                f"{r['ttft_ms']:<8} | {r['total_ms']:<9} | {r['tps']:<7} | OK"
            )
        else:
            err = r.get("error", "Error")[:15]
            print(
                f"{r['provider']:<10} | {r['model']:<25} | {r['profile']:<12} | "
                f"{'N/A':<8} | {'N/A':<9} | {'N/A':<7} | FAIL ({err})"
            )
    print("=" * 88)


def main():
    parser = argparse.ArgumentParser(description="WhisperDoc LLM Post-Processing Benchmark")
    parser.add_argument("--groq-key", default=os.environ.get("GROQ_API_KEY"), help="Groq API Key")
    parser.add_argument("--cerebras-key", default=os.environ.get("CEREBRAS_API_KEY"), help="Cerebras API Key")
    args = parser.parse_args()

    if not args.groq_key and not args.cerebras_key:
        print("Error: Please provide at least one API key via --groq-key, --cerebras-key,")
        print("or via environment variables GROQ_API_KEY / CEREBRAS_API_KEY.")
        sys.exit(1)

    all_results = []

    if args.groq_key:
        groq_results = benchmark_provider(
            provider_name="Groq",
            endpoint=GROQ_BASE_URL,
            api_key=args.groq_key,
            models=GROQ_MODELS,
        )
        all_results.extend(groq_results)

    if args.cerebras_key:
        cerebras_results = benchmark_provider(
            provider_name="Cerebras",
            endpoint=CEREBRAS_BASE_URL,
            api_key=args.cerebras_key,
            models=CEREBRAS_MODELS,
        )
        all_results.extend(cerebras_results)

    print_summary_table(all_results)


if __name__ == "__main__":
    main()
