# Rewrite model benchmark (OpenRouter)

Which model should the output styles rewrite with on OpenRouter, and how should OpenRouter pick its host? The value being maximised is the whole rewrite: the time from sending the transcript to having the text back, and the quality of the rewrite, at a sensible cost. All runs use the v3.3 Tech prompt (see [technical_prompt.md](technical_prompt.md)), reasoning off, and zero data retention, exactly as the client sends them. Measured 2026-11-23 from one desk; host speeds move by the hour, so read the numbers as a snapshot.

## Decision

- **Default: `qwen/qwen3.8-27b`.** It ties for fastest once routed well, its Tech output was the best measured, and it is the model the styles are tuned on with Groq, so a style reads the same on either service.
- **Routing: lowest latency among hosts writing at least 200 tokens a second** (`provider.sort: "latency"` with `preferred_min_throughput.p50: 200`). A rewrite is about 75 tokens, so both the wait for the first token and the speed after it count.
- **Anyone can pick another model** in Account → OpenRouter → Rewrite model. The app sends that model a one-word rewrite first and refuses one that can't serve the styles, saying why (for example, models that can't turn reasoning off).
- **Groq stays faster.** The same Qwen model answers in about 0.26 s on Groq against about 0.42–0.45 s through OpenRouter, because OpenRouter adds a hop and Groq runs the model on its own inference chips.

## 1. Lightweight models

13 models with a zero-retention host, 4 dictations × 3 runs each, with latency-only routing (what the client sent before v3.3):

| Model | Median | Range | Tech output |
|---|---|---|---|
| Llama 3.1 8B | 439 ms | 328–527 | Loses the formatting: bare commands, no backticks, a dropped path |
| Gemma 4 26B (4B active) | 443 ms | 304–617 | Good, but keeps filler and lowercase starts |
| Nemotron 3 Nano (3B active) | 526 ms | 497–820 | Poor: no backticks, little punctuation, `--d` for `-d` |
| **Qwen3.8 27B** | **568 ms** | 339–827 | **Best, identical to Groq's** |
| Gemini 3.1 Flash Lite | 773 ms | 558–1025 | Good, but writes `docker-compose`, drops lead-ins |
| GPT-4.1 nano | 834 ms | 688–1191 | Not reviewed |
| Qwen3 30B (3B active) | 846 ms | 649–1484 | Not reviewed |
| Claude Haiku 5.5 | 952 ms | 647–1764 | See below |
| Ministral 8B | 1107 ms | 697–1549 | Not reviewed |
| GPT-4o mini | 1754 ms | 1364–2191 | Not reviewed |
| Mistral Small 3.2 24B | 2114 ms | 842–3234 | Not reviewed |
| Gemini 3.5 Flash Lite, GPT-OSS 20B | Refused | — | Reasoning can't be turned off |

A smaller model barely helps: the output is short, so most of the time is OpenRouter's routing and the host's time to the first token, not generation. The fastest small model saved about 0.13 s and lost the code formatting.

## 2. Stronger models

All 8 Tech dictations × 3 runs:

| Model | Median | Range | Notes |
|---|---|---|---|
| Qwen3.8 27B | 524 ms | 326–2699 | Fastest; same output as on Groq |
| DeepSeek V4.1 Flash (1017) | 705 ms | 332–2533 | As good; turned "can you rename…" into a command and wrote "3 services"; cheapest |
| Claude Haiku 5.5 | 1015 ms | 679–1528 | Cleanest prose (the only one to drop a mid-sentence "basically"); steadiest; only two hosts |

## 3. Routing

OpenRouter lists each model's hosts with their latency (time to first token) and throughput over the last 30 minutes, and routes on its last 5 minutes. The options tried, medians over 16 rewrites per row (three sessions; the range shows the spread between sessions):

| Routing | Qwen3.8 27B | DeepSeek V4.1 Flash |
|---|---|---|
| Latency only (before v3.3) | 476–710 ms, ModelRun | 626–671 ms, InferenceNet |
| Throughput only | 402–437 ms, Cerebras | 518–688 ms, p90 up to 3.3 s |
| **Latency, ≥200 tokens/s first (v3.3)** | **423–454 ms, Cerebras** | **439–459 ms, p90 under 0.8 s** |
| Latency, ≥150 tokens/s first | 616 ms, ModelRun | 648 ms |
| `:nitro` (throughput, priority hosts allowed) | 403–467 ms | 520–805 ms, one 12 s spike |
| Pinned to `baseten/fast` | not offered | 992 ms; OpenRouter sent only 2 of 12 there |

Pinning a host doesn't pay: the fastest host on paper changes by the hour, and a pin breaks when it slows down or goes away. Haiku 5.5 is served only by Google Vertex and Amazon Bedrock, so routing doesn't change it.

The faster hosts cost more per token: Qwen on Cerebras is about $1 per 1,000 rewrites against about $0.27 on ModelRun. That is still about a tenth of a cent per rewrite.

## Reproduce

```bash
python scripts/benchmark_prompts.py --provider openrouter     --models qwen/qwen3.8-27b,deepseek/deepseek-v4.1-flash-1017,anthropic/claude-haiku-5.5     --routing app,latency,throughput --runs 3 --out report.md
```

`app` is the routing the client sends, read from `app_constants.dart`. A pull request that changes the default model or the routing should include a report like the one below.

## Full report (2026-11-23, `app` vs `latency` routing)

Provider: openrouter · runs per transcript: 2 · style: technical · 2026-11-23

| Combination | Median | p90 | Length vs input | Rejected | Cost / 1k | Hosts |
|---|---|---|---|---|---|---|
| qwen/qwen3.8-27b · app | 416 ms | 1186 ms | 0.90× | 0 | $0.955 | Cerebras 16 |
| qwen/qwen3.8-27b · latency | 534 ms | 920 ms | 0.89× | 0 | $0.252 | ModelRun 16 |
| deepseek/deepseek-v4.1-flash-1017 · app | 492 ms | 796 ms | 0.90× | 0 | $0.185 | CoreWeave 14, BaseTen 1, Morph 1 |
| deepseek/deepseek-v4.1-flash-1017 · latency | 825 ms | 4107 ms | 0.90× | 0 | $0.065 | InferenceNet 13, CoreWeave 3 |
| anthropic/claude-haiku-5.5 · app | 1021 ms | 1542 ms | 0.90× | 0 | $0.184 | Google 16 |
| anthropic/claude-haiku-5.5 · latency | 1055 ms | 1418 ms | 0.90× | 0 | $0.184 | Google 16 |

## Outputs (first run)

### Function and file names

> okay so in the auth service we need to update the get user by id function in user underscore repository dot pie so it returns none instead of raising when the user is missing and then the fast api route in routes slash users dot pie should return a four oh four

**qwen/qwen3.8-27b · app** (590 ms)

```markdown
In the auth service, update the `get_user_by_id` function in `user_repository.py` so it returns `None` instead of raising when the user is missing. The FastAPI route in `routes/users.py` should return a 404.
```

**qwen/qwen3.8-27b · latency** (483 ms)

```markdown
In the auth service, update the `get_user_by_id` function in `user_repository.py` so it returns `None` instead of raising when the user is missing. The FastAPI route in `routes/users.py` should return a 404.
```

**deepseek/deepseek-v4.1-flash-1017 · app** (440 ms)

```markdown
In the auth service, update the `get_user_by_id` function in `user_repository.py` so it returns `None` instead of raising when the user is missing, and then the FastAPI route in `routes/users.py` should return a 404.
```

**deepseek/deepseek-v4.1-flash-1017 · latency** (627 ms)

```markdown
In the auth service, update the `get_user_by_id` function in `user_repository.py` so it returns `None` instead of raising when the user is missing, and then the FastAPI route in `routes/users.py` should return a 404.
```

**anthropic/claude-haiku-5.5 · app** (939 ms)

```markdown
In the auth service we need to update the `get_user_by_id` function in `user_repository.py` so it returns `None` instead of raising when the user is missing, and then the FastAPI route in `routes/users.py` should return a 404.
```

**anthropic/claude-haiku-5.5 · latency** (733 ms)

```markdown
In the auth service we need to update the `get_user_by_id` function in `user_repository.py` so it returns `None` instead of raising when the user is missing, and then the FastAPI route in `routes/users.py` should return a 404.
```

### Frameworks, platforms and protocols

> um the next js app talks to the back end over web sockets and we want to move the token refresh into a react hook called use session refresh and keep the refresh token in an http only cookie not local storage also the o auth two pkce flow with key cloak needs the redirect uri to match exactly

**qwen/qwen3.8-27b · app** (376 ms)

```markdown
The Next.js app talks to the back end over WebSockets, and we want to move the token refresh into a React hook called `useSessionRefresh` and keep the refresh token in an HTTP-only cookie, not local storage. Also, the OAuth 2.0 PKCE flow with Keycloak needs the redirect URI to match exactly.
```

**qwen/qwen3.8-27b · latency** (518 ms)

```markdown
The Next.js app talks to the back end over WebSockets. We want to move the token refresh into a React hook called `useSessionRefresh` and keep the refresh token in an HTTP-only cookie, not local storage. Also, the OAuth 2.0 PKCE flow with Keycloak needs the `redirect_uri` to match exactly.
```

**deepseek/deepseek-v4.1-flash-1017 · app** (620 ms)

```markdown
The Next.js app talks to the back end over WebSockets, and we want to move the token refresh into a React hook called `useSessionRefresh` and keep the refresh token in an HTTP-only cookie, not local storage. Also, the OAuth 2.0 PKCE flow with Keycloak needs the redirect URI to match exactly.
```

**deepseek/deepseek-v4.1-flash-1017 · latency** (3584 ms)

```markdown
The Next.js app talks to the back end over WebSockets, and we want to move the token refresh into a React hook called `useSessionRefresh` and keep the refresh token in an HTTP-only cookie, not local storage. Also, the OAuth 2.0 PKCE flow with Keycloak needs the redirect URI to match exactly.
```

**anthropic/claude-haiku-5.5 · app** (932 ms)

```markdown
The Next.js app talks to the backend over WebSockets, and we want to move the token refresh into a React hook called `useSessionRefresh`. Keep the refresh token in an HTTP-only cookie, not local storage. Also, the OAuth 2.0 PKCE flow with Keycloak needs the redirect URI to match exactly.
```

**anthropic/claude-haiku-5.5 · latency** (1085 ms)

```markdown
The Next.js app talks to the backend over WebSockets, and we want to move the token refresh into a React hook called `useSessionRefresh`. Keep the refresh token in an HTTP-only cookie, not local storage. Also, the OAuth 2.0 PKCE flow with Keycloak needs the redirect URI to match exactly.
```

### System design

> so the architecture is basically the api gateway sits in front of three services the order service the payment service and the notification service they talk over g r p c and the payment service publishes events to a kafka topic called payment dot completed which the notification service consumes and everything runs on kubernetes in e k s with postgres on r d s

**qwen/qwen3.8-27b · app** (599 ms)

```markdown
The architecture is basically the API gateway sits in front of three services: the order service, the payment service, and the notification service. They talk over gRPC, and the payment service publishes events to a Kafka topic called `payment.completed`, which the notification service consumes. Everything runs on Kubernetes in EKS with Postgres on RDS.
```

**qwen/qwen3.8-27b · latency** (571 ms)

```markdown
The architecture is that the API gateway sits in front of three services: the order service, the payment service, and the notification service. They talk over gRPC, and the payment service publishes events to a Kafka topic called `payment.completed`, which the notification service consumes. Everything runs on Kubernetes in EKS with Postgres on RDS.
```

**deepseek/deepseek-v4.1-flash-1017 · app** (509 ms)

```markdown
The architecture is: the API gateway sits in front of 3 services, the order service, the payment service and the notification service. They talk over gRPC, and the payment service publishes events to a Kafka topic called `payment.completed`, which the notification service consumes. Everything runs on Kubernetes in EKS with Postgres on RDS.
```

**deepseek/deepseek-v4.1-flash-1017 · latency** (705 ms)

```markdown
The architecture is the API gateway sits in front of 3 services: the order service, the payment service, and the notification service. They talk over gRPC, and the payment service publishes events to a Kafka topic called `payment.completed`, which the notification service consumes. Everything runs on Kubernetes in EKS with Postgres on RDS.
```

**anthropic/claude-haiku-5.5 · app** (946 ms)

```markdown
The API gateway sits in front of three services: the order service, the payment service, and the notification service. They talk over gRPC. The payment service publishes events to a Kafka topic called `payment.completed`, which the notification service consumes. Everything runs on Kubernetes in EKS, with Postgres on RDS.
```

**anthropic/claude-haiku-5.5 · latency** (955 ms)

```markdown
The API gateway sits in front of three services: the order service, the payment service and the notification service. They talk over gRPC, and the payment service publishes events to a Kafka topic called `payment.completed`, which the notification service consumes. Everything runs on Kubernetes in EKS, with Postgres on RDS.
```

### Commands and config

> run docker compose up dash d then cube control get pods dash n staging and check that the redis url environment variable is set in the dot env file the value should be redis colon slash slash localhost colon six three seven nine

**qwen/qwen3.8-27b · app** (735 ms)

```markdown
Run `docker compose up -d`, then `kubectl get pods -n staging`, and check that the `REDIS_URL` environment variable is set in the `.env` file. The value should be `redis://localhost:6379`.
```

**qwen/qwen3.8-27b · latency** (436 ms)

```markdown
Run `docker compose up -d`, then `kubectl get pods -n staging`, and check that the `REDIS_URL` environment variable is set in the `.env` file. The value should be `redis://localhost:6379`.
```

**deepseek/deepseek-v4.1-flash-1017 · app** (474 ms)

```markdown
Run `docker compose up -d`, then `kubectl get pods -n staging` and check that the `REDIS_URL` environment variable is set in the `.env` file. The value should be `redis://localhost:6379`.
```

**deepseek/deepseek-v4.1-flash-1017 · latency** (868 ms)

```markdown
Run `docker compose up -d`, then `kubectl get pods -n staging` and check that the `REDIS_URL` environment variable is set in the `.env` file. The value should be `redis://localhost:6379`.
```

**anthropic/claude-haiku-5.5 · app** (1024 ms)

```markdown
Run `docker compose up -d`, then `kubectl get pods -n staging`, and check that the `REDIS_URL` environment variable is set in the `.env` file. The value should be `redis://localhost:6379`.
```

**anthropic/claude-haiku-5.5 · latency** (880 ms)

```markdown
Run `docker compose up -d` then `kubectl get pods -n staging` and check that the `REDIS_URL` environment variable is set in the `.env` file. The value should be `redis://localhost:6379`.
```

### Short edit request

> can you rename the camel case variable max retry count to max retries and bump the version in pub spec dot yaml to three point three point oh

**qwen/qwen3.8-27b · app** (383 ms)

```markdown
Can you rename the camelCase variable `maxRetryCount` to `maxRetries` and bump the version in `pubspec.yaml` to 3.3.0?
```

**qwen/qwen3.8-27b · latency** (393 ms)

```markdown
Rename the camelCase variable `maxRetryCount` to `maxRetries` and bump the version in `pubspec.yaml` to 3.3.0.
```

**deepseek/deepseek-v4.1-flash-1017 · app** (471 ms)

```markdown
Rename the camelCase variable `maxRetryCount` to `maxRetries` and bump the version in `pubspec.yaml` to 3.3.0.
```

**deepseek/deepseek-v4.1-flash-1017 · latency** (676 ms)

```markdown
Rename the camelCase variable `maxRetryCount` to `maxRetries` and bump the version in `pubspec.yaml` to 3.3.0.
```

**anthropic/claude-haiku-5.5 · app** (791 ms)

```markdown
Can you rename the camelCase variable `maxRetryCount` to `maxRetries` and bump the version in `pubspec.yaml` to 3.3.0?
```

**anthropic/claude-haiku-5.5 · latency** (1497 ms)

```markdown
Can you rename the camelCase variable `maxRetryCount` to `maxRetries` and bump the version in `pubspec.yaml` to 3.3.0?
```

### Dictated steps

> okay three things first add a retry decorator to the fetch invoice function with three attempts second log the response body when the status is five hundred or above and third write a pie test for the timeout case in tests slash test underscore billing dot pie

**qwen/qwen3.8-27b · app** (504 ms)

```markdown
Three things:

1. Add a retry decorator to the `fetch_invoice` function with 3 attempts.
2. Log the response body when the status is 500 or above.
3. Write a pytest test for the timeout case in `tests/test_billing.py`.
```

**qwen/qwen3.8-27b · latency** (549 ms)

```markdown
Three things:

1. Add a retry decorator to the `fetch_invoice` function with 3 attempts.
2. Log the response body when the status is 500 or above.
3. Write a pytest test for the timeout case in `tests/test_billing.py`.
```

**deepseek/deepseek-v4.1-flash-1017 · app** (504 ms)

```markdown
Three things:

1. Add a retry decorator to the `fetch_invoice` function with 3 attempts.
2. Log the response body when the status is 500 or above.
3. Write a pytest for the timeout case in `tests/test_billing.py`.
```

**deepseek/deepseek-v4.1-flash-1017 · latency** (985 ms)

```markdown
Three things:

1. Add a retry decorator to the `fetch_invoice` function with 3 attempts.
2. Log the response body when the status is 500 or above.
3. Write a pytest for the timeout case in `tests/test_billing.py`.
```

**anthropic/claude-haiku-5.5 · app** (2040 ms)

```markdown
1. Add a retry decorator to the `fetch_invoice` function with three attempts.
2. Log the response body when the status is 500 or above.
3. Write a Python test for the timeout case in `tests/test_billing.py`.
```

**anthropic/claude-haiku-5.5 · latency** (1146 ms)

```markdown
1. Add a retry decorator to the `fetch_invoice` function with three attempts.
2. Log the response body when the status is 500 or above.
3. Write a pytest test for the timeout case in `tests/test_billing.py`.
```

### Plain words stay plain

> i think the main problem is that the cash is too small so the dashboard feels slow in the morning when everyone logs in we should look at it next sprint

**qwen/qwen3.8-27b · app** (396 ms)

```markdown
I think the main problem is that the cache is too small, so the dashboard feels slow in the morning when everyone logs in. We should look at it next sprint.
```

**qwen/qwen3.8-27b · latency** (728 ms)

```markdown
I think the main problem is that the cache is too small, so the dashboard feels slow in the morning when everyone logs in. We should look at it next sprint.
```

**deepseek/deepseek-v4.1-flash-1017 · app** (363 ms)

```markdown
I think the main problem is that the cache is too small, so the dashboard feels slow in the morning when everyone logs in. We should look at it next sprint.
```

**deepseek/deepseek-v4.1-flash-1017 · latency** (726 ms)

```markdown
I think the main problem is that the cache is too small, so the dashboard feels slow in the morning when everyone logs in. We should look at it next sprint.
```

**anthropic/claude-haiku-5.5 · app** (1173 ms)

```markdown
I think the main problem is that the cache is too small, so the dashboard feels slow in the morning when everyone logs in. We should look at it next sprint.
```

**anthropic/claude-haiku-5.5 · latency** (714 ms)

```markdown
I think the main problem is that the cache is too small, so the dashboard feels slow in the morning when everyone logs in. We should look at it next sprint.
```

### Already-clean spec

> so basically what we need to do for the sync worker is instead of polling postgres every 500ms we need to switch to LISTEN NOTIFY on the jobs channel and if the connection drops with an ECONNRESET or socket timeout we have to use exponential backoff starting at 100ms maxing out at 5000ms with jitter and make sure we do not drop the in-flight job_id batch which can hold up to 50 items also set WORKER_CONCURRENCY to 4 by default and send a warning to Sentry if queue latency exceeds 250ms

**qwen/qwen3.8-27b · app** (1346 ms)

```markdown
For the sync worker, instead of polling Postgres every 500 ms, switch to `LISTEN NOTIFY` on the `jobs` channel. If the connection drops with an `ECONNRESET` or socket timeout, use exponential backoff starting at 100 ms, maxing out at 5000 ms, with jitter. Ensure the in-flight `job_id` batch, which can hold up to 50 items, is not dropped. Set `WORKER_CONCURRENCY` to 4 by default and send a warning to Sentry if queue latency exceeds 250 ms.
```

**qwen/qwen3.8-27b · latency** (1013 ms)

```markdown
For the sync worker, instead of polling Postgres every 500 ms, switch to `LISTEN`/`NOTIFY` on the `jobs` channel. If the connection drops with `ECONNRESET` or a socket timeout, use exponential backoff starting at 100 ms, maxing out at 5000 ms, with jitter. Ensure the in-flight `job_id` batch, which can hold up to 50 items, is not dropped. Set `WORKER_CONCURRENCY` to 4 by default and send a warning to Sentry if queue latency exceeds 250 ms.
```

**deepseek/deepseek-v4.1-flash-1017 · app** (1209 ms)

```markdown
For the sync worker, instead of polling Postgres every 500 ms we need to switch to `LISTEN`/`NOTIFY` on the `jobs` channel. If the connection drops with an `ECONNRESET` or socket timeout, we have to use exponential backoff starting at 100 ms, maxing out at 5000 ms, with jitter. Make sure we do not drop the in-flight `job_id` batch, which can hold up to 50 items. Also set `WORKER_CONCURRENCY` to 4 by default and send a warning to Sentry if queue latency exceeds 250 ms.
```

**deepseek/deepseek-v4.1-flash-1017 · latency** (5328 ms)

```markdown
For the sync worker, instead of polling Postgres every 500 ms, we need to switch to `LISTEN`/`NOTIFY` on the `jobs` channel. If the connection drops with an `ECONNRESET` or socket timeout, we have to use exponential backoff starting at 100 ms, maxing out at 5000 ms, with jitter. Make sure we do not drop the in-flight `job_id` batch, which can hold up to 50 items. Also set `WORKER_CONCURRENCY` to 4 by default, and send a warning to Sentry if queue latency exceeds 250 ms.
```

**anthropic/claude-haiku-5.5 · app** (1258 ms)

```markdown
For the sync worker, instead of polling Postgres every 500 ms, we need to switch to `LISTEN`/`NOTIFY` on the `jobs` channel. If the connection drops with an `ECONNRESET` or socket timeout, we have to use exponential backoff starting at 100 ms and maxing out at 5000 ms, with jitter. Make sure we do not drop the in-flight `job_id` batch, which can hold up to 50 items. Also set `WORKER_CONCURRENCY` to 4 by default, and send a warning to Sentry if queue latency exceeds 250 ms.
```

**anthropic/claude-haiku-5.5 · latency** (1348 ms)

```markdown
For the sync worker, instead of polling Postgres every 500 ms, we need to switch to `LISTEN`/`NOTIFY` on the `jobs` channel. If the connection drops with an `ECONNRESET` or socket timeout, we have to use exponential backoff starting at 100 ms and maxing out at 5000 ms, with jitter. Make sure we do not drop the in-flight `job_id` batch, which can hold up to 50 items. Also set `WORKER_CONCURRENCY` to 4 by default, and send a warning to Sentry if queue latency exceeds 250 ms.
```
