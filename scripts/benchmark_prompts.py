#!/usr/bin/env python3
"""Benchmark WhisperDoc's output styles: prompts, rewrite models and routing.

Every request is the one the Flutter client sends: the style's system prompt
read straight from ``dictation_profile.dart`` (so the benchmark can't drift
from what ships), the transcript in ``<transcript>`` tags, temperature 0.1,
reasoning off, and on OpenRouter zero data retention plus a routing choice.
The transcripts are written the way speech recognition hands them over:
lower case, spoken symbols ("dot", "slash"), misheard names.

Examples (keys come from GROQ_API_KEY / OPENROUTER_API_KEY or --env-file,
and are never printed):

  # Compare a draft Tech prompt with the shipped one on Groq
  python scripts/benchmark_prompts.py --compare my_tech.txt --runs 2

  # Time rewrite models on OpenRouter under each routing choice
  python scripts/benchmark_prompts.py --provider openrouter \\
      --models qwen/qwen3.8-27b,deepseek/deepseek-v4.1-flash-1017 \\
      --routing app,latency,throughput --runs 3 --out report.md

A change to a style's prompt or to the default rewrite model should come
with a report from this script (see docs/benchmarks/README.md).
"""

from __future__ import annotations

import argparse
import collections
import io
import json
import os
import pathlib
import re
import statistics
import sys
import time
import urllib.error
import urllib.request
from dataclasses import dataclass, field

ROOT = pathlib.Path(__file__).resolve().parent.parent
PROFILES_DART = ROOT / "flutter_client/lib/logic/models/dictation_profile.dart"
CONSTANTS_DART = ROOT / "flutter_client/lib/infrastructure/constants/app_constants.dart"

ENDPOINTS = {
    "groq": "https://api.groq.com/openai/v1/chat/completions",
    "openrouter": "https://openrouter.ai/api/v1/chat/completions",
}
KEY_NAMES = {"groq": "GROQ_API_KEY", "openrouter": "OPENROUTER_API_KEY"}

# The client rejects a rewrite longer than this many times its input.
MAX_LENGTH_RATIO = 4.5

# The Dart constant holding each style's prompt.
STYLE_PROMPTS = {
    "clean": "_cleanPrompt",
    "professional": "_proPrompt",
    "casual": "_casualPrompt",
    "technical": "_techPrompt",
}

# How OpenRouter picks a host. "app" is what the client sends.
ROUTING = {
    "app": None,  # filled from app_constants.dart
    "latency": ("", {"sort": "latency"}),
    "throughput": ("", {"sort": "throughput"}),
    "nitro": (":nitro", {}),
}

TRANSCRIPTS = {
    "technical": {
        "Function and file names": (
            "okay so in the auth service we need to update the get user by id function in "
            "user underscore repository dot pie so it returns none instead of raising when "
            "the user is missing and then the fast api route in routes slash users dot pie "
            "should return a four oh four"
        ),
        "Frameworks, platforms and protocols": (
            "um the next js app talks to the back end over web sockets and we want to move "
            "the token refresh into a react hook called use session refresh and keep the "
            "refresh token in an http only cookie not local storage also the o auth two "
            "pkce flow with key cloak needs the redirect uri to match exactly"
        ),
        "System design": (
            "so the architecture is basically the api gateway sits in front of three "
            "services the order service the payment service and the notification service "
            "they talk over g r p c and the payment service publishes events to a kafka "
            "topic called payment dot completed which the notification service consumes "
            "and everything runs on kubernetes in e k s with postgres on r d s"
        ),
        "Commands and config": (
            "run docker compose up dash d then cube control get pods dash n staging and "
            "check that the redis url environment variable is set in the dot env file the "
            "value should be redis colon slash slash localhost colon six three seven nine"
        ),
        "Short edit request": (
            "can you rename the camel case variable max retry count to max retries and bump "
            "the version in pub spec dot yaml to three point three point oh"
        ),
        "Dictated steps": (
            "okay three things first add a retry decorator to the fetch invoice function "
            "with three attempts second log the response body when the status is five "
            "hundred or above and third write a pie test for the timeout case in tests "
            "slash test underscore billing dot pie"
        ),
        "Plain words stay plain": (
            "i think the main problem is that the cash is too small so the dashboard feels "
            "slow in the morning when everyone logs in we should look at it next sprint"
        ),
        "Already-clean spec": (
            "so basically what we need to do for the sync worker is instead of polling "
            "postgres every 500ms we need to switch to LISTEN NOTIFY on the jobs channel "
            "and if the connection drops with an ECONNRESET or socket timeout we have to "
            "use exponential backoff starting at 100ms maxing out at 5000ms with jitter and "
            "make sure we do not drop the in-flight job_id batch which can hold up to 50 "
            "items also set WORKER_CONCURRENCY to 4 by default and send a warning to "
            "Sentry if queue latency exceeds 250ms"
        ),
    },
    "clean": {
        "Filler and false starts": (
            "um so basically what i wanted to say is like we need to update the server "
            "because ah the database is kind of slow you know"
        ),
    },
    "professional": {
        "Budget escalation": (
            "hey so looking at the q3 cloud infrastructure numbers we are currently tracking "
            "18% over budget mostly because of unreserved rds instances in us-east-1 and "
            "honestly if we do not purchase one-year savings plans by next tuesday we are "
            "going to burn another twelve thousand dollars before the quarter ends so i need "
            "finance approval on the procurement request today"
        ),
    },
    "casual": {
        "Deployment heads-up": (
            "hey guys quick heads up about the deployment today we had to roll back the "
            "billing service because of a cache miss loop on redis but everything is stable "
            "on the old version now and we are pushing a hotfix in about 20 minutes so no "
            "need to panic"
        ),
    },
}


@dataclass
class Run:
    """One rewrite: how long it took, who served it, what it said."""

    ms: float
    text: str
    host: str
    cost: float


@dataclass
class Cell:
    """Every run of one prompt × model × routing combination."""

    label: str
    runs: list[Run] = field(default_factory=list)
    first: dict[str, Run] = field(default_factory=dict)
    error: str | None = None


def dart_string(source: str, name: str) -> str:
    """The body of a Dart ''' string constant, with the preamble spliced in."""
    match = re.search(rf"{name} =\s*'''\n(.*?)''';", source, re.DOTALL)
    if not match:
        sys.exit(f"{name} not found in {PROFILES_DART.name}")
    return match.group(1)


def shipped_prompt(style: str) -> str:
    source = PROFILES_DART.read_text(encoding="utf-8")
    preamble = dart_string(source, "sharedPreamble")
    return dart_string(source, STYLE_PROMPTS[style]).replace(
        "${DictationProfile.sharedPreamble}", preamble
    )


def app_routing() -> tuple[str, dict]:
    """The client's own provider preferences, read from app_constants.dart."""
    source = CONSTANTS_DART.read_text(encoding="utf-8")
    floor = re.search(r"openRouterRewriteMinThroughput = (\d+);", source)
    if not floor:
        sys.exit("openRouterRewriteMinThroughput not found in app_constants.dart")
    return "", {
        "sort": "latency",
        "preferred_min_throughput": {"p50": int(floor.group(1))},
    }


def default_model() -> str:
    source = CONSTANTS_DART.read_text(encoding="utf-8")
    match = re.search(r"openRouterTransformModel = '([^']+)';", source)
    if not match:
        sys.exit("openRouterTransformModel not found in app_constants.dart")
    return match.group(1)


def api_key(provider: str, env_file: str | None) -> str:
    name = KEY_NAMES[provider]
    if env_file:
        for line in pathlib.Path(env_file).read_text(encoding="utf-8").splitlines():
            if line.startswith(f"{name}="):
                return line.split("=", 1)[1].strip()
    key = os.environ.get(name)
    if not key:
        sys.exit(f"Set {name} or pass --env-file")
    return key


def _post(request: urllib.request.Request, tries: int = 4) -> tuple[float, dict]:
    """Sends the request, waiting out rate limits between tries.

    Returns the time to the full response in ms, and its JSON body.
    """
    wait = 0.0
    for _ in range(tries):
        time.sleep(wait)
        start = time.perf_counter()
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                data = json.load(response)
            return (time.perf_counter() - start) * 1000, data
        except urllib.error.HTTPError as e:
            if e.code != 429:
                detail = e.read()[:200].decode("utf-8", "replace")
                raise RuntimeError(f"HTTP {e.code}: {detail}") from e
            wait = float(e.headers.get("retry-after") or 10)
    raise RuntimeError(f"HTTP 429: still rate limited after {tries} tries")


def rewrite(provider, key, model, routing, system, text) -> Run:
    """One completion, timed end to end like the client sees it."""
    suffix, preferences = routing
    body = {
        "model": model + suffix,
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": f"<transcript>\n{text}\n</transcript>"},
        ],
        "temperature": 0.1,
        "stream": False,
    }
    # Room for twice the input, as the client allows.
    tokens = max(128, min(4096, int(len(text) / 3 * 2)))
    if provider == "groq":
        body |= {"max_completion_tokens": tokens, "include_reasoning": False}
    else:
        body |= {
            "max_tokens": tokens,
            "reasoning": {"enabled": False},
            "usage": {"include": True},
            "provider": {"zdr": True, **preferences},
        }
    request = urllib.request.Request(
        ENDPOINTS[provider],
        data=json.dumps(body).encode(),
        headers={
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
            "User-Agent": "whisperdoc-benchmark",
        },
    )
    ms, data = _post(request)
    usage = data.get("usage") or {}
    return Run(
        ms=ms,
        text=(data["choices"][0]["message"].get("content") or "").strip(),
        host=data.get("provider") or provider,
        cost=usage.get("cost") or 0.0,
    )


def measure(args, key, prompts, transcripts) -> list[Cell]:
    routings = args.routing.split(",") if args.provider == "openrouter" else ["-"]
    cells = []
    for prompt_label, system in prompts.items():
        for model in args.models.split(","):
            for routing_name in routings:
                routing = ROUTING.get(routing_name) or ("", {})
                label = " · ".join(
                    part
                    for part in (prompt_label, model, routing_name)
                    if part and part != "-"
                )
                cell = Cell(label)
                print(f"{label} …", flush=True)
                try:
                    # Interleave transcripts so a slow minute is shared.
                    for _ in range(args.runs):
                        for title, text in transcripts.items():
                            run = rewrite(
                                args.provider, key, model, routing, system, text
                            )
                            cell.runs.append(run)
                            cell.first.setdefault(title, run)
                except RuntimeError as e:
                    cell.error = str(e)
                cells.append(cell)
    return cells


def report(args, cells, transcripts) -> str:
    lines = [
        (
            f"Provider: {args.provider} · runs per transcript: {args.runs} · "
            f"style: {args.style} · {time.strftime('%Y-%m-%d')}"
        ),
        "",
        "| Combination | Median | p90 | Length vs input | Rejected | Cost / 1k | Hosts |",
        "|---|---|---|---|---|---|---|",
    ]
    inputs = list(transcripts.values()) * args.runs
    for cell in cells:
        if cell.error:
            lines.append(f"| {cell.label} | failed: {cell.error} ||||||")
            continue
        times = [run.ms for run in cell.runs]
        ratios = [len(run.text) / len(text) for run, text in zip(cell.runs, inputs)]
        p90 = statistics.quantiles(times, n=10)[-1] if len(times) > 1 else times[0]
        hosts = collections.Counter(run.host for run in cell.runs)
        cost = statistics.mean(run.cost for run in cell.runs) * 1000
        lines.append(
            f"| {cell.label} | {statistics.median(times):.0f} ms | {p90:.0f} ms | "
            f"{statistics.mean(ratios):.2f}× | "
            f"{sum(r > MAX_LENGTH_RATIO for r in ratios)} | "
            f"{'$' + format(cost, '.3f') if cost else '—'} | "
            f"{', '.join(f'{h} {n}' for h, n in hosts.most_common())} |"
        )
    lines += ["", "## Outputs (first run)", ""]
    for title, text in transcripts.items():
        lines += [f"### {title}", "", f"> {text}", ""]
        for cell in cells:
            run = cell.first.get(title)
            if run:
                lines += [
                    f"**{cell.label}** ({run.ms:.0f} ms)",
                    "",
                    "```markdown",
                    run.text,
                    "```",
                    "",
                ]
    return "\n".join(lines)


def main() -> None:
    if isinstance(sys.stdout, io.TextIOWrapper):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--style", choices=STYLE_PROMPTS, default="technical")
    parser.add_argument("--provider", choices=ENDPOINTS, default="groq")
    parser.add_argument(
        "--models", help="Comma-separated model ids (default: the app's rewrite model)"
    )
    parser.add_argument(
        "--routing",
        default="app",
        help=f"OpenRouter only, comma-separated: {', '.join(ROUTING)} (default: app)",
    )
    parser.add_argument(
        "--compare",
        action="append",
        default=[],
        metavar="FILE",
        help="A prompt (without the shared preamble) to run beside the shipped "
        "one, labelled by its file name; repeatable",
    )
    parser.add_argument("--runs", type=int, default=1, help="Runs per transcript")
    parser.add_argument("--env-file", help="A KEY=value file holding the API key")
    parser.add_argument("--out", help="Write the markdown report here")
    args = parser.parse_args()

    ROUTING["app"] = app_routing()
    args.models = args.models or default_model()
    unknown = set(args.routing.split(",")) - set(ROUTING)
    if unknown:
        parser.error(f"unknown routing: {', '.join(sorted(unknown))}")

    preamble = dart_string(PROFILES_DART.read_text(encoding="utf-8"), "sharedPreamble")
    prompts = {
        pathlib.Path(path).stem: preamble
        + "\n"
        + pathlib.Path(path).read_text(encoding="utf-8")
        for path in args.compare
    }
    # A lone shipped prompt needs no label in the report.
    prompts["shipped" if prompts else ""] = shipped_prompt(args.style)

    transcripts = TRANSCRIPTS[args.style]
    key = api_key(args.provider, args.env_file)
    text = report(args, measure(args, key, prompts, transcripts), transcripts)
    if args.out:
        pathlib.Path(args.out).write_text(text + "\n", encoding="utf-8", newline="\n")
        print(f"Report written to {args.out}")
    else:
        print(text)


if __name__ == "__main__":
    main()
