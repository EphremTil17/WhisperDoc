# Parakeet Migration: NVIDIA NeMo to parakeet.cpp

**Status:** Accepted and implemented  
**Date:** 2026-08-16  
**Decision:** Replace the in-process NVIDIA NeMo Parakeet runtime with an
isolated `parakeet.cpp` F16 CUDA sidecar while preserving WhisperDoc's public
transcription contract.

## Executive summary

WhisperDoc originally ran `nvidia/parakeet-tdt-0.6b-v2` through
`nemo_toolkit[asr]` inside the FastAPI/Uvicorn process. That path delivered
excellent inference latency, but the process became unable to accept new
WebSocket upgrades after transcription. Diagnostics proved that a shared
`b" "` bytes object used by Uvicorn's h11 upgrade path changed from `0x20` to
`0x00`. Native-state corruption is the strongest explanation, but the exact
native component in the NeMo/PyTorch/CUDA dependency chain was never isolated
with a memory debugger. This distinction matters: the failure was reproducible
and the corrupted byte was observed, while attribution to a specific upstream
library remains a hypothesis.

The selected replacement runs the same Parakeet TDT model family as a pinned
GGUF model in a separate `parakeet.cpp` CUDA container. WhisperDoc's Python API
communicates with it over a private Compose network. Native inference can no
longer mutate the CPython/Uvicorn process, and a sidecar failure is constrained
to the model service rather than the public HTTP/WebSocket server.

The migration removes the NeMo compatibility path rather than maintaining two
Parakeet implementations. `ASR_ENGINE=parakeet` now means the C++ sidecar
directly. There are no aliases, monkey-patches, runtime shims, or legacy model
fallbacks.

## What remains unchanged for users

No Flutter or other client change is required for normal dictation. Engine
selection remains a backend deployment concern.

| Public behavior | Before | After | Compatibility |
| --- | --- | --- | --- |
| HTTP transcription | Authenticated `POST /transcribe` with multipart audio | Same endpoint, authentication, upload, and response | Unchanged |
| WebSocket transport | Connect to `/ws`, exchange `hello`, stream PCM, send `end-of-stream` | Same event sequence and payloads | Unchanged |
| Authentication | API key or OIDC/JWT handshake | Same | Unchanged |
| Incoming audio | Client streams 16-kHz, 16-bit mono PCM | Same | Unchanged |
| Success event | `event=transcription` with `text`, `segments`, and `processing_time` | Same fields and types | Unchanged |
| Error envelope | Structured WebSocket error or existing HTTP error response | Same public envelope | Unchanged |
| Engine selector | `ASR_ENGINE=parakeet` | `ASR_ENGINE=parakeet` | Unchanged |
| Whisper option | `ASR_ENGINE=whisper` | Same independent engine | Unchanged |

The orchestration layer still writes streamed PCM to a temporary WAV, calls a
synchronous `BaseEngine.transcribe()`, sanitizes segment text, wipes the audio
buffer, and emits the existing transcription event. The new engine returns the
same `TranscriptionResult` and `SegmentResult` data classes expected by that
pipeline.

### Deliberate internal differences

These changes do not alter the client protocol, but operators and maintainers
must understand them:

| Internal behavior | NeMo implementation | parakeet.cpp implementation |
| --- | --- | --- |
| Process location | Model and native libraries inside Uvicorn's CPython process | Native model server in an isolated container |
| Segment mapping | Used model timestamps when available | One segment for short dictation; timestamp-owned bounded segments for long recordings |
| Maximum utterance | No explicit adapter limit | 30 seconds per native request; longer recordings are split at quiet boundaries |
| Model lifecycle | Python engine loaded and freed GPU weights | Compose owns the native process and VRAM; API `unload()` detaches |
| Model installation | Framework/model resolution through NeMo | Explicit, digest-verified provisioning before startup |
| Startup readiness | Python model object loaded | Sidecar health check plus a 10-second silent CUDA warmup |

The 30-second native-request bound is intentional. Fixed-width chunking was
tested and caused word loss, duplication, and split words. The replacement
planner searches for quiet boundaries, adds bounded acoustic overlap, and uses
the sidecar's word timestamps to assign each overlap word to exactly one output
window. No new native VAD dependency is loaded into Uvicorn.

## Failure that motivated the migration

The retired runtime produced the following sequence with a 100% reproduction
rate in the diagnostic environment:

1. Uvicorn starts and accepts WebSocket connections normally.
2. NeMo completes one Parakeet transcription.
3. A bytes object used to reconstruct the h11 WebSocket request line is
   observed as `0x00` instead of ASCII space `0x20`.
4. Reconstructed requests become `GET\x00/ws HTTP/1.1`.
5. Every subsequent WebSocket upgrade in that process fails with HTTP 400.
6. HTTP transcription continues working, and restarting the process restores
   WebSockets until the next transcription.

The previous mitigation reconstructed the request with a dynamically allocated
space byte. It reduced the observed symptom but could not make an in-process
native memory write safe. It was therefore removed along with the NeMo runtime.

The detailed evidence and confidence assessment are retained in
[`NEMO_CPYTHON_MEMORY_CORRUPTION.md`](../git_exclude/docs/NEMO_CPYTHON_MEMORY_CORRUPTION.md).

## Architecture comparison

### Retired topology

```text
Client
  -> FastAPI / Uvicorn / h11
       -> Python ParakeetEngine
            -> NeMo -> PyTorch -> CUDA and native extensions

All network protocol state and native inference state share one process.
```

### Selected topology

```text
Client
  -> FastAPI / Uvicorn / websockets-sansio
       -> canonical ParakeetEngine adapter
            -> private HTTP on the Compose network
                 -> parakeet.cpp server -> ggml CUDA -> pinned GGUF

The public protocol process and native inference process have separate address
spaces and separate failure domains.
```

The sidecar is a meaningful isolation boundary, not a claim that C++ or CUDA
cannot fail. A native crash can still fail an individual transcription until
Compose restarts the sidecar, but it cannot directly overwrite CPython objects
inside the API container.

## Alternatives examined

| Candidate | Evidence | Decision |
| --- | --- | --- |
| Keep NeMo in process and retain the h11 patch | Fastest retired in-process measurement, but corruption remained in the API address space and the patch treated one symptom | Rejected |
| Put NeMo in a Python worker process | Would isolate Uvicorn, but retains the large training-oriented dependency graph, slow loading, logging behavior, and native Python runtime | Rejected as unnecessary complexity |
| Sherpa-ONNX CUDA, FP16 | Prototype emitted repeated `<unk>` tokens on the RTX 3060 Ti | Rejected for correctness |
| Sherpa-ONNX CUDA, INT8 | Correct short transcript, but approximately 396-451 ms median in the Phase 1 prototype with unstable p95 results | Rejected for interactive latency |
| parakeet.cpp Q8_0 CUDA | Correct and approximately 461 MiB less VRAM than F16, but slightly slower to load and transcribe on this GPU | Retained as an explicit low-memory model option, not the default |
| parakeet.cpp F16 CUDA | Exact short transcript, near-NeMo direct inference latency, stable integrated soaks, simple pinned deployment | Selected |
| faster-whisper large-v3-turbo | Reliable and multilingual, but materially slower on the measured English dictation path | Retained as the independent Whisper engine |
| Custom batching server or LocalAI | Native decoder batching is useful under existing concurrency, but interactive dictation should not wait for a batch | Deferred until production concurrency proves a need |

Riva and other serving systems were considered conceptually but were not
benchmark finalists. They introduce a larger operational envelope without
solving a demonstrated requirement that the small native sidecar does not
already meet.

## Direct performance comparison

All local figures below were measured on WSL2 with an NVIDIA RTX 3060 Ti 8 GiB
and driver 580.97. The short sample was `assets/anyone_pause.wav`: 9.16 seconds,
16-kHz mono PCM. Results from different layers are labeled because direct
engine latency and authenticated endpoint latency are not interchangeable.

### Short dictation latency and accuracy

| Runtime and layer | Precision / configuration | Median | p95 | Transcript result |
| --- | --- | ---: | ---: | --- |
| Retired in-process Parakeet engine | NeMo FP16 CUDA | 51.4 ms | 66.2 ms | Correct |
| parakeet.cpp direct CLI | F16 CUDA, 4 threads | 52.3 ms | 59.1 ms | Exact expected text |
| parakeet.cpp private HTTP | F16 CUDA, fresh connection | 63.1 ms | 67.4 ms | Exact expected text |
| Final WhisperDoc HTTP endpoint | F16 sidecar, authenticated | 78.6 ms | 88.6 ms | 30/30 identical and exact |
| Final WhisperDoc WebSocket cycle | F16 sidecar, fresh authenticated connection | 74.3 ms | 82.0 ms | 50/50 identical and exact |
| WhisperDoc faster-whisper endpoint | large-v3-turbo FP16, beam 3 | 319.4 ms | 330.3 ms | Correct, minor wording difference |
| Sherpa-ONNX prototype | INT8 CUDA, 2-4 threads | 396.3-450.9 ms | 591.8-3318.5 ms | Correct short sample |

The C++ CLI was within approximately 1 ms of the retired NeMo median. Process
isolation and authenticated transport add roughly 22-27 ms relative to that
raw in-process number, but the final Parakeet path remains about four times
faster than the measured Whisper Turbo endpoint. The small transport cost was
accepted in exchange for eliminating shared native state between inference and
the WebSocket server.

### Startup, memory, and deployment footprint

| Characteristic | NeMo path | Selected parakeet.cpp path |
| --- | --- | --- |
| Direct model load | Approximately 6-12 seconds in the diagnosed deployment | 0.98 seconds measured for F16 |
| Steady incremental VRAM | Approximately 2 GiB observed/estimated | 1,729-1,899 MiB observed; use 1.9 GiB for planning |
| Model artifact | Framework-managed NeMo model | 1.404 GB F16 GGUF with pinned SHA-256 |
| API image | Included the NeMo/PyTorch ASR framework chain | 167 MB core-only Python API image |
| Native runtime image | Part of the API image and Python dependency graph | 1.79 GB pinned CUDA sidecar image |
| Python lock resolution | 240 packages before removal | 74 packages after removal |
| Native host RAM at final check | Not isolated from API process | 935 MiB sidecar plus 50 MiB API |
| Failure containment | Inference and protocol server fail together | Compose can restart the model service independently |

The 1,729 MiB VRAM delta was measured with the idle Whisper model unloaded:
total GPU memory fell from 3,328 MiB to 1,599 MiB when the experiment stack
stopped. A co-resident soak measured a 1,899 MiB delta. The difference reflects
host/co-resident state, so 1.9 GiB is the conservative capacity value.

### F16 versus Q8_0

| GGUF variant | Direct HTTP median | Direct HTTP p95 | Load time | VRAM trade-off | Decision |
| --- | ---: | ---: | ---: | --- | --- |
| F16 | 63.1 ms | 67.4 ms | 0.98 s | Baseline | Default latency-first model |
| Q8_0 | 64.1 ms | 69.3 ms | 1.49 s | Approximately 461 MiB less | Optional for constrained VRAM |

Quantization did not improve latency on the RTX 3060 Ti. F16 was selected
because the project is latency-first and the 8-GiB target GPU has sufficient
capacity when only the selected ASR engine is resident.

### Long-form examination

| Path | 516.853-second TED sample | Result |
| --- | ---: | --- |
| Retired in-process baseline | 3.901 seconds | Reference transcript |
| faster-whisper | 10.62 seconds | Completed |
| parakeet.cpp whole-file F16 | More than two minutes; approximately 7.8 GiB total GPU memory | Terminated and rejected as a production path |
| parakeet.cpp fixed 30-second slices | 3.318 seconds wall time | 17 edits across 1,233 words, or 1.3788%, from boundary damage |
| parakeet.cpp silence-aware overlap | 4.044 seconds engine time | 20 bounded requests, 19 quiet cuts, 1,227 assembled words |

`PARAKEET_MAX_AUDIO_SECONDS=30` now bounds each native request rather than the
entire utterance. On a representative 35-second excerpt, the production path
used two requests and one quiet cut, completing in 267 ms with 76 assembled
words. The long TED run is approximately 22% slower than naive fixed slices,
but it avoids arbitrary boundary cuts and remains approximately 128x real time.

## Reliability and test evidence

### Architecture-evaluation soaks

Before the final naming/purge commit, the isolated architecture completed:

| Gate | Result |
| --- | --- |
| Authenticated HTTP soak | 1,000 requests, zero failures, zero transcript mismatches |
| HTTP latency during soak | 71.7 ms median, 78.7 ms p95 |
| VRAM sampling | Stabilized by request 300; final sample 11 MiB above request 100 and 5 MiB below the maximum |
| WebSocket transcription soak | 1,000 cycles across 40 authenticated connections, zero failures and mismatches |
| WebSocket latency during soak | 68.2 ms median, 76.5 ms p95 |
| Error scan | No transcription, traceback, CUDA, segmentation, or memory-corruption errors |

The 1,000-cycle WebSocket soak still had the obsolete h11 symptom patch in the
API source, so it proved sidecar stability but was not used alone to justify
patch removal.

### Final patch-free gates

After deleting NeMo, its compatibility code, and the h11 monkey-patch, the
canonical deployment passed:

| Gate | Result |
| --- | --- |
| Host unit suite | 102 passed, 6 intentional integration skips |
| Engine contract suite | Whisper and Parakeet both satisfied `BaseEngine` output and lifecycle contracts |
| Final authenticated HTTP | 30/30 successful; one exact transcript; 78.6 ms median, 88.6 ms p95 |
| Final authenticated WebSocket | 50/50 fresh connect/transcribe/disconnect cycles; 74.3 ms median, 82.0 ms p95 |
| WebSocket limit rationale | 50 is the configured per-IP pre-ban threshold, so the reconnect gate stopped there intentionally |
| CUDA verification | RTX 3060 Ti detected, backend reported `CUDA0`, CUDA graph warmup completed |
| Runtime log scan | No CPU fallback, h11, traceback, transcription, or memory-corruption errors |
| Static analysis | Ruff clean; Pyright reported zero errors and warnings |
| Dependency reproducibility | `uv lock --check` passed with 74 resolved packages |
| Deployment validation | Compose configuration, real image build, sidecar health, API health, and authenticated endpoint all passed |
| Synchronization | WD-Sync completed without retained conflicts; Windows and WSL worktrees returned clean |

The tests demonstrate that the observed failure mode did not recur under the
measured load. They do not mathematically prove that every native failure is
impossible; process isolation limits the impact when one occurs.

## Deployment contract

The selected backend is configured with:

```dotenv
ASR_ENGINE=parakeet
COMPOSE_PROFILES=parakeet
PARAKEET_ACCELERATOR=CUDA0
PARAKEET_MODEL_FILE=tdt-0.6b-v2-f16.gguf
```

Provision the model before startup:

```bash
uv run --project backend python backend/tools/provision_parakeet.py
docker compose build whisper-backend
docker compose up -d
```

The provisioner validates the model's exact byte length and SHA-256 digest,
writes to a temporary file in the destination filesystem, calls `fsync()`, and
atomically replaces the target only after verification. The sidecar image is
also pinned by digest.

`PARAKEET_ACCELERATOR` is intentionally distinct from the native container's
`PARAKEET_DEVICE` variable. Retired deployments used the value `cuda`, while
parakeet.cpp expects `CUDA0`; passing the retired value caused a silent CPU
fallback during final testing. Compose now maps the explicit WhisperDoc value
to the native variable, and the final live gate verified GPU execution.

## Removed components

The migration deliberately removed rather than deprecated:

- the NeMo-backed `ParakeetEngine` implementation;
- the separate `parakeet_cpp` engine name and `parakeet-cpp` alias;
- `nemo_toolkit[asr]`, Lightning, Hydra, Lhotse, gRPC, and the associated
  training-oriented transitive dependency graph;
- the NeMo-specific Docker build and runtime variables;
- NeMo module stubs and legacy engine tests;
- NeMo/Lhotse logging suppression;
- the h11 WebSocket-upgrade monkey-patch;
- stdio redirection and other symptom-oriented compatibility code.

Historical release notes remain unchanged because they describe software that
was actually shipped. They are not active configuration or runtime guidance.

## Decision consequences

### Benefits

- Native inference is isolated from CPython, Uvicorn, h11, authentication, and
  WebSocket state.
- Interactive English dictation remains below 100 ms at the measured p95 and
  approximately four times faster than the measured Whisper Turbo endpoint.
- Startup is faster and the Python API image/dependency graph is substantially
  smaller.
- Model and runtime artifacts are reproducible through pinned digests.
- CUDA warmup happens before the first user transcription.
- Whisper remains available as an independent reliable and multilingual
  backend without importing Parakeet dependencies.
- Operations can restart or inspect the native model process independently.

### Costs and accepted limitations

- Compose runs two containers for Parakeet instead of one.
- Private HTTP isolation adds approximately 22-27 ms over raw in-process
  inference on the short test.
- Short output contains one full-utterance segment; long output contains
  non-overlapping logical segments assembled from model word timestamps.
- Parakeet remains English-only.
- Long recordings add one sequential sidecar request per bounded chunk; the
  516.853-second test measured approximately 22% overhead versus fixed slices.
- F16 uses approximately 461 MiB more VRAM than Q8_0.
- Running Whisper and Parakeet simultaneously is not recommended on the 8-GiB
  target GPU; the selected Compose profile should control residency.

## Final decision

The migration is accepted because it preserves WhisperDoc's client-facing
dictation pipeline while replacing an unreliable shared-process runtime with a
small, reproducible, independently supervised inference service. The selected
F16 path gives near-NeMo raw inference speed, sub-100-ms integrated latency,
lower operational coupling, and strong measured reliability without retaining
the dependency and compatibility burden that caused the migration.

Detailed raw benchmark context is available in
[`PARAKEET_BENCHMARK.md`](../backend/engine/PARAKEET_BENCHMARK.md).
