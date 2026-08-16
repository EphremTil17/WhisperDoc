# Parakeet.cpp CUDA Evaluation

Date: 2026-08-16  
Host: WSL2, NVIDIA RTX 3060 Ti 8 GiB, driver 580.97  
Runtime: `ghcr.io/mudler/parakeet.cpp-server` at digest
`sha256:dfbe0fa76a49386b5dd413392b74c89bc68fcac0a445dbb4efec083d7dc1acbf`

This report records the local measurements used to design WhisperDoc's
`ASR_ENGINE=parakeet` path. These are host-specific results,
not general vendor performance claims.

## Short dictation

Input: `assets/anyone_pause.wav`, 9.16 seconds, 16-kHz mono PCM. All accepted
Parakeet candidates produced the exact expected transcript.

| Runtime | Configuration | Median | p95 | Notes |
| --- | --- | ---: | ---: | --- |
| Retired in-process baseline | FP16 CUDA | 51.4 ms | 66.2 ms | Measurement retained for comparison |
| parakeet.cpp CLI | F16 CUDA, 4 threads | 52.3 ms | 59.1 ms | 20 decodes after model load |
| parakeet.cpp HTTP | F16 CUDA, 4 threads | 63.1 ms | 67.4 ms | Fresh loopback connection per request |
| parakeet.cpp HTTP | Q8_0 CUDA, 4 threads | 64.1 ms | 69.3 ms | Smaller, but slower on this GPU |
| WhisperDoc + parakeet.cpp | F16 sidecar, authenticated upload | 74.6 ms | 79.9 ms | Engine portion: 60.5 / 64.1 ms |
| WhisperDoc + faster-whisper | large-v3-turbo, FP16, beam 3 | 319.4 ms | 330.3 ms | Engine portion: 304.7 / 315.7 ms |

On the identical authenticated upload path, parakeet.cpp reduced median
end-to-end latency by 76.6% (4.28x faster) relative to the running Whisper
Turbo container.

F16 model load was 0.98 seconds in the direct benchmark. Q8_0 loaded in 1.49
seconds. A health check alone did not initialize all lazy CUDA work: the first
real request took 328-416 ms. A 10-second silent decode during engine warmup
removed that spike.

The example server's HTTP keep-alive path added approximately 40 ms on this
host. Sending `Connection: close` reduced steady HTTP latency to roughly 63 ms;
the adapter therefore makes that behavior explicit.

## VRAM

After the 1,000-request integrated soak, total GPU memory with both Whisper and
Parakeet resident was 5,326 MiB. Stopping only the experiment stack reduced the
total to 3,427 MiB, giving the F16 sidecar an observed incremental footprint of
approximately 1,899 MiB. The lightweight Python API used 62.6 MiB host RAM and
the native sidecar used 1.185 GiB host RAM at the end of the soak.

Earlier controlled F16/Q8_0 snapshots under the same co-resident conditions
showed Q8_0 saving approximately 461 MiB, but Q8_0 did not improve latency. F16
is therefore the default for WhisperDoc's latency-first target; Q8_0 remains an
explicit provisioning option for tighter VRAM budgets.

The final canonical deployment was also measured with the idle Whisper model
unloaded: total GPU memory fell from 3,328 MiB to 1,599 MiB when the isolated
stack stopped, an incremental 1,729 MiB. At that point the native sidecar used
935 MiB of host RAM and the Python API used 50 MiB. The two VRAM deltas describe
different co-resident states; the conservative planning figure remains 1.9 GiB.

## Integrated reliability soak

The isolated Compose stack completed 1,000 authenticated uploads through the
full Uvicorn → Python adapter → native sidecar path with zero request failures
and zero transcript mismatches.

- End-to-end latency: 71.7 ms median, 78.7 ms p95.
- Sidecar request portion: 57.6 ms median, 64.1 ms p95.
- Total co-resident GPU memory sampled every 100 requests: 5,315, 5,324,
  5,331, 5,331, 5,331, 5,331, 5,331, 5,331, 5,327, and 5,326 MiB.
- Memory stabilized by request 300; the final sample was 11 MiB above request
  100 and 5 MiB below the observed maximum.

This passes the experiment's zero-failure and no-monotonic-growth gates. It
does not prove native code is incapable of failing, but it exercises the
specific repeated web/native boundary that was unreliable in the retired
implementation.

An additional WebSocket soak completed 1,000 transcription cycles across 40
authenticated connections. This forced 39 fresh Uvicorn WebSocket upgrades
after native inference had already run, directly exercising the failure mode
that motivated process isolation. This architectural soak preceded removal of
the obsolete transport monkey-patch, so a separate patch-free gate was run on
the final replacement below.

- Zero request failures and zero transcript mismatches.
- Full WebSocket cycle latency: 68.2 ms median, 76.5 ms p95.
- Sidecar request portion: 58.6 ms median, 66.6 ms p95.
- Co-resident GPU memory samples ranged from 5,066 to 5,090 MiB and ended at
  the observed maximum without monotonic growth.
- Complete API and native-sidecar logs contained no h11, transcription,
  traceback, CUDA, segmentation, or memory-corruption errors.

After the legacy engine and transport monkey-patch were deleted, the canonical
deployment completed 30 authenticated HTTP transcriptions and 50 fresh,
authenticated WebSocket connect/transcribe/disconnect cycles. Fifty cycles is
the configured per-IP pre-ban limit, so the gate intentionally stopped there.

- HTTP: zero failures, one exact transcript, 78.6 ms median and 88.6 ms p95.
- WebSocket: zero failures, one exact transcript, 74.3 ms median and 82.0 ms p95.
- The sidecar reported `CUDA0` and completed CUDA graph warmup; logs contained
  no fallback, h11, traceback, transcription, or memory-corruption errors.

The final local Docker artifacts were 167 MB for the core-only Python API image
and 1.79 GB for the CUDA sidecar image, with the 1.404 GB F16 model stored
separately in the host model cache. The corresponding Whisper API/model-runtime
image was 1.73 GB before its separately cached Whisper weights.

## Long-form boundary

Input: 516.853-second TED sample.

- A single whole-file F16 request exceeded two minutes, saturated the GPU, and
  drove total GPU memory to approximately 7.8 GiB. It was terminated.
- Eighteen fixed 30-second requests completed in 3.318 seconds wall time (3.191
  seconds summed inference time), but naive transcript joining differed from
  the retired baseline by 17 word edits across 1,233 words (1.3788%). Splits cut
  words, dropped words, and duplicated boundary text.
- The retired baseline completed this sample in 3.901 seconds and faster-whisper
  in 10.62 seconds.

Consequently, the first adapter rejects audio above 30 seconds by default.
Fixed interval chunking is not an acceptable production implementation.
Long-form support requires silence-aware boundaries plus overlap and transcript
de-duplication, followed by a new accuracy benchmark.

## Decoder batching

The native batched decoder is effective only when requests are already
concurrent. With F16, four threads, and the short clip, batch sizes 4, 8, and 10
produced 2.81x, 6.08x, and 7.86x decoder speedups respectively. Batch size 1
was effectively unchanged (1.03x).

The upstream example HTTP server serializes inference and does not expose that
batch path. WhisperDoc will not delay interactive dictation to fill a batch.
LocalAI or a custom pool/batching worker should be considered only after real
concurrent load demonstrates a need; adding either now would be premature.

## Deployment decision

- `ASR_ENGINE=parakeet` selects the native CUDA sidecar directly.
- Keep the C++ runtime outside CPython/Uvicorn.
- Pin both the sidecar image and GGUF digest. Provision weights before startup;
  never download model code or weights in API startup.
- Do not run Whisper and Parakeet sidecars together in normal production on an
  8-GiB GPU. The selected Compose profile should determine what becomes
  resident.

The sidecar boundary materially improves failure isolation, but it is not a
claim that native code cannot fail. Both integrated HTTP and authenticated
WebSocket-cycle soaks passed, and the obsolete transport monkey-patch was
removed with the retired runtime.

## Upstream references

- [parakeet.cpp README](https://github.com/mudler/parakeet.cpp/blob/master/README.md)
- [parakeet.cpp benchmarks](https://github.com/mudler/parakeet.cpp/blob/master/benchmarks/BENCHMARK.md)
- [Published GGUF collection](https://huggingface.co/mudler/parakeet-cpp-gguf)
