# Tech style prompt benchmark

The Tech output style is for developers talking to a coding agent or a colleague. It should write down what they said, with every technical term the way it appears in code, documentation or a terminal: function and file names, commands, frameworks, platforms, protocols and system design, never paraphrased or generalized.

This page compares the prompt that shipped up to v3.2 with the one that replaced it in v3.3. Both run on `qwen/qwen3.8-27b` on Groq with the exact request the client sends.

## What changed

**The v3.2 prompt** asked for a "precise, highly structured technical specification". In practice it did three things wrong:

- **It turned every dictation into a headed spec** at 2.6 times the input length on average. That included a one-line rename request and a casual remark ("the cash is too small" became a `cache` component with a root cause and an action item).
- **It added what nobody said.** Examples: "exclusively via WebSockets", "to mitigate XSS vulnerabilities", "as well as between the backend services themselves".
- **It overran the client's token cap.** The cap is twice the input length. 3 of the 8 rewrites below were cut off mid-sentence, and the client treats a cut-off rewrite as failed, so those dictations lost their style.

The benchmark that chose that prompt ([`prompts/technical_v3.2.txt`](prompts/technical_v3.2.txt)) never caught this: its only transcript was already typed cleanly, with `ECONNRESET` and `job_id` spelled out. Real speech recognition hands the style "user underscore repository dot pie" and "cube control".

**The v3.3 prompt** (`_techPrompt` in [`dictation_profile.dart`](../../flutter_client/lib/logic/models/dictation_profile.dart)) keeps the speaker's sentences, removes filler, and gets the terms right:

1. Code symbols in backticks, rebuilt from spoken symbols ("dot", "slash", "underscore") with the casing the language uses.
2. Frameworks, platforms and protocols spelled as their makers do, without backticks, keeping the name the speaker chose (Postgres stays Postgres). A misheard name is corrected only when the context makes it clear.
3. Numbers, versions, ports and durations as digits.
4. System design kept exactly as stated: no added components, reasons or best practices.
5. A numbered list only when the speaker counts off steps. Never a title.

## Results

| | v3.2 prompt | v3.3 prompt |
|---|---|---|
| Median time (Groq) | 487 ms | 262 ms |
| 90th percentile | 1004 ms | 558 ms |
| Length vs the input | 2.59× | 0.90× |
| Cut off at the client's token cap | 3 of 8 | 0 of 8 |
| Words or claims added | Several per rewrite | None seen |

Across both runs of every transcript the v3.3 wording was stable. One known flaw: a "basically" in the middle of a sentence sometimes survives.

## Reproduce

```bash
python scripts/benchmark_prompts.py     --compare docs/benchmarks/prompts/technical_v3.2.txt --runs 2
```

The script reads the shipped prompt from the app's source, so this always compares against what ships. Add `--provider openrouter` to run it through OpenRouter.

## Full report (2026-11-23)

The rows below are labelled `technical_v3.2` for the old prompt and `shipped` for the v3.3 prompt.

Provider: groq · runs per transcript: 2 · style: technical · 2026-11-23

| Combination | Median | p90 | Length vs input | Rejected | Cost / 1k | Hosts |
|---|---|---|---|---|---|---|
| technical_v3.2 · qwen/qwen3.8-27b | 487 ms | 1004 ms | 2.59× | 0 | — | groq 16 |
| shipped · qwen/qwen3.8-27b | 262 ms | 558 ms | 0.90× | 0 | — | groq 16 |

## Outputs (first run)

### Function and file names

> okay so in the auth service we need to update the get user by id function in user underscore repository dot pie so it returns none instead of raising when the user is missing and then the fast api route in routes slash users dot pie should return a four oh four

**technical_v3.2 · qwen/qwen3.8-27b** (492 ms)

```markdown
**Technical Specification: Authentication Service - User Retrieval Error Handling**

**1. Repository Layer Modification**
*   **Target File:** `user_repository.py`
*   **Target Function:** `get_user_by_id`
*   **Required Behavior Change:**
    *   Modify the function logic to return `None` when the requested user ID does not correspond to an existing user record.
    *   Remove any existing exception-raising behavior associated with missing user records.

**2. API Route Layer Modification**
*   **Target File:** `routes/users.py`
*   **Target Framework:** FastAPI
*   **Required Behavior Change:**
    *   Update the route handler to check the return value of the repository function.
    *   If the repository returns `None`, the API endpoint must respond with an HTTP status
```

**shipped · qwen/qwen3.8-27b** (815 ms)

```markdown
In the auth service, update the `get_user_by_id` function in `user_repository.py` so it returns `None` instead of raising when the user is missing. The FastAPI route in `routes/users.py` should return a 404.
```

### Frameworks, platforms and protocols

> um the next js app talks to the back end over web sockets and we want to move the token refresh into a react hook called use session refresh and keep the refresh token in an http only cookie not local storage also the o auth two pkce flow with key cloak needs the redirect uri to match exactly

**technical_v3.2 · qwen/qwen3.8-27b** (468 ms)

```markdown
**Technical Specification: Session Management and OAuth 2.0 PKCE Integration**

**1. Architecture Overview**
*   **Frontend Framework:** Next.js application.
*   **Communication Protocol:** The frontend communicates with the backend exclusively via WebSockets.

**2. Session Refresh Implementation**
*   **Encapsulation:** Refactor the token refresh logic into a dedicated React hook named `useSessionRefresh`.
*   **Storage Security:**
    *   Store the refresh token exclusively in an `HttpOnly` cookie.
    *   **Constraint:** Prohibit the use of `localStorage` for storing refresh tokens to mitigate XSS vulnerabilities.

**3. OAuth 2.0 PKCE Configuration**
*   **Identity Provider:** Keycloak.
*   **Flow:** OAuth 2.0 Authorization Code Flow with Proof Key for Code Exchange (PKCE).
*   **Redirect URI Constraint:**
    *   The `
```

**shipped · qwen/qwen3.8-27b** (306 ms)

```markdown
The Next.js app talks to the back end over WebSockets. We want to move the token refresh into a React hook called `useSessionRefresh` and keep the refresh token in an HTTP-only cookie, not `localStorage`. Also, the OAuth 2.0 PKCE flow with Keycloak needs the `redirect_uri` to match exactly.
```

### System design

> so the architecture is basically the api gateway sits in front of three services the order service the payment service and the notification service they talk over g r p c and the payment service publishes events to a kafka topic called payment dot completed which the notification service consumes and everything runs on kubernetes in e k s with postgres on r d s

**technical_v3.2 · qwen/qwen3.8-27b** (482 ms)

```markdown
## System Architecture Specification

### 1. High-Level Topology
The system utilizes a microservices architecture comprising an API gateway and three distinct backend services. The API gateway is positioned as the primary entry point, routing traffic to the following services:
*   `order-service`
*   `payment-service`
*   `notification-service`

### 2. Inter-Service Communication
*   **Protocol:** All synchronous communication between the API gateway and the backend services, as well as between the backend services themselves, utilizes gRPC.

### 3. Asynchronous Event Flow
*   **Event Producer:** The `payment-service` publishes events to an Apache Kafka topic.
*   **Topic Name:** `payment.completed`
*   **Event Consumer:** The `notification-service` subscribes to and consumes events from the `payment.completed` topic.

### 4. Infrastructure & Data Persistence
*   **Container Orchestration:** All services are deployed and managed on Amazon Elastic Kubernetes Service (EKS).
*   **Database:** The system utilizes PostgreSQL hosted on Amazon Relational Database Service (RDS).
```

**shipped · qwen/qwen3.8-27b** (263 ms)

```markdown
The architecture is basically the API gateway sits in front of three services: the order service, the payment service, and the notification service. They talk over gRPC, and the payment service publishes events to a Kafka topic called `payment.completed`, which the notification service consumes. Everything runs on Kubernetes in EKS with Postgres on RDS.
```

### Commands and config

> run docker compose up dash d then cube control get pods dash n staging and check that the redis url environment variable is set in the dot env file the value should be redis colon slash slash localhost colon six three seven nine

**technical_v3.2 · qwen/qwen3.8-27b** (521 ms)

```markdown
**Procedure: Staging Environment Deployment and Configuration Verification**

1.  **Service Deployment**
    *   Execute the following command to start the application services:
        ```bash
        docker compose up -d
        ```

2.  **Pod Status Verification**
    *   Execute the following command to retrieve the status of all pods within the `staging` namespace:
        ```bash
        kubectl get pods -n staging
        ```

3.  **Environment Configuration Validation**
    *   Inspect the `.env` file to verify the presence and correctness of the `REDIS_URL` environment variable.
    *   **Expected Value**: `redis://localhost:6379`
```

**shipped · qwen/qwen3.8-27b** (241 ms)

```markdown
Run `docker compose up -d`, then `kubectl get pods -n staging`, and check that the `REDIS_URL` environment variable is set in the `.env` file. The value should be `redis://localhost:6379`.
```

### Short edit request

> can you rename the camel case variable max retry count to max retries and bump the version in pub spec dot yaml to three point three point oh

**technical_v3.2 · qwen/qwen3.8-27b** (266 ms)

```markdown
**Task 1: Variable Renaming**
- **Action**: Rename the variable `maxRetryCount` to `maxRetries`.
- **Constraint**: Ensure the original variable name `maxRetryCount` is in camelCase.

**Task 2: Version Update**
- **File**: `pubspec.yaml`
- **Action**: Update the version field to `3.3.0`.
```

**shipped · qwen/qwen3.8-27b** (211 ms)

```markdown
Can you rename the camelCase variable `maxRetryCount` to `maxRetries` and bump the version in `pubspec.yaml` to 3.3.0?
```

### Dictated steps

> okay three things first add a retry decorator to the fetch invoice function with three attempts second log the response body when the status is five hundred or above and third write a pie test for the timeout case in tests slash test underscore billing dot pie

**technical_v3.2 · qwen/qwen3.8-27b** (277 ms)

```markdown
1. Implement a retry decorator for the `fetch_invoice` function.
   - Configure the decorator to execute exactly three attempts.

2. Implement conditional logging for HTTP responses.
   - Log the response body when the HTTP status code is 500 or greater.

3. Create a unit test for the timeout scenario.
   - File path: `tests/test_billing.py`.
   - Test case: Verify behavior during a timeout event.
```

**shipped · qwen/qwen3.8-27b** (253 ms)

```markdown
Three things:

1. Add a retry decorator to the `fetch_invoice` function with 3 attempts.
2. Log the response body when the status is 500 or above.
3. Write a pytest test for the timeout case in `tests/test_billing.py`.
```

### Plain words stay plain

> i think the main problem is that the cash is too small so the dashboard feels slow in the morning when everyone logs in we should look at it next sprint

**technical_v3.2 · qwen/qwen3.8-27b** (334 ms)

```markdown
**Issue Identification**
*   **Root Cause:** The `cache` size is insufficient.
*   **Observed Symptom:** The dashboard exhibits high latency and perceived slowness.
*   **Trigger Condition:** High-concurrency access events occurring during the morning login peak.

**Action Item**
*   **Task:** Investigate and resolve the cache sizing issue.
*   **Timeline:** Schedule for execution in the next sprint.
```

**shipped · qwen/qwen3.8-27b** (227 ms)

```markdown
I think the main problem is that the cache is too small, so the dashboard feels slow in the morning when everyone logs in. We should look at it next sprint.
```

### Already-clean spec

> so basically what we need to do for the sync worker is instead of polling postgres every 500ms we need to switch to LISTEN NOTIFY on the jobs channel and if the connection drops with an ECONNRESET or socket timeout we have to use exponential backoff starting at 100ms maxing out at 5000ms with jitter and make sure we do not drop the in-flight job_id batch which can hold up to 50 items also set WORKER_CONCURRENCY to 4 by default and send a warning to Sentry if queue latency exceeds 250ms

**technical_v3.2 · qwen/qwen3.8-27b** (863 ms)

```markdown
### Technical Specification: Sync Worker Architecture Update

**1. Event-Driven Architecture Migration**
*   **Current State:** The sync worker currently implements a polling mechanism against the PostgreSQL database with an interval of 500ms.
*   **Required Change:** Replace the polling mechanism with a PostgreSQL `LISTEN`/`NOTIFY` implementation.
*   **Target Channel:** The worker must subscribe to the `jobs` channel.

**2. Connection Resilience & Reconnection Logic**
*   **Trigger Conditions:** Implement reconnection logic specifically for the following error states:
    *   `ECONNRESET`
    *   Socket timeout
*   **Backoff Strategy:** Utilize an exponential backoff algorithm with the following parameters:
    *   **Initial Delay:** 100ms
    *   **Maximum Delay:** 5000ms
    *   **Jitter:** Apply random jitter to the backoff intervals to prevent thundering herd issues.

**3. Data Integrity Constraints**
*   **In-Flight Batch Preservation:** Ensure that the in-flight `job_id` batch is not dropped during connection interruptions or reconnection attempts.
*   **Batch Capacity:** The in-flight batch must support a maximum capacity of 50 items.

**4. Configuration & Performance Monitoring**
*   **Concurrency Setting:** Set the environment variable `WORKER_CONCURRENCY` to a default value of `4`.
*   **Latency Alerting:**
    *   **Threshold:** Monitor queue latency.
    *
```

**shipped · qwen/qwen3.8-27b** (448 ms)

```markdown
For the sync worker, instead of polling Postgres every 500 ms, switch to `LISTEN NOTIFY` on the `jobs` channel. If the connection drops with an `ECONNRESET` or socket timeout, use exponential backoff starting at 100 ms, maxing out at 5000 ms, with jitter. Ensure the in-flight `job_id` batch, which can hold up to 50 items, is not dropped. Set `WORKER_CONCURRENCY` to 4 by default and send a warning to Sentry if queue latency exceeds 250 ms.
```
