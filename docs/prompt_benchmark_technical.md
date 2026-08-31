
# Profile Benchmark Comparison: Technical

| Draft Name | TTFT (ms) | Total (ms) | Tokens | Retention % | Expansion Ratio | Status |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| **Draft 1: Concise Baseline (Previous Prompt)** | 244.4 | 506.8 | 137 | **100.0%** | 0.91x | PASS |
| **Draft 2: Zero-Omission Exhaustive Spec (New WhisperDoc Prompt)** | 253.3 | 1060.8 | 378 | **100.0%** | 3.23x | PASS |
| **Draft 3: Direct AI-Agent Directive** | 221.1 | 1279.4 | 558 | **100.0%** | 4.5x | PASS |
| **Draft 4: Technical Acceptance Criteria** | 227.4 | 1507.9 | 653 | **100.0%** | 5.13x | PASS |
| **Draft 5: Minimal Verbatim Polish with Code Casing** | 221.8 | 520.2 | 152 | **100.0%** | 1.08x | PASS |

## Generated Draft Outputs

### Draft 1: Concise Baseline (Previous Prompt)
*Original prompt that compressed details into concise bullet points.*

```markdown
- Replace the 500ms `postgres` polling interval with `LISTEN NOTIFY` on the `jobs` channel.
- Implement exponential backoff for connection failures (`ECONNRESET` or socket timeout):
  - Start at `100ms`.
  - Max out at `5000ms`.
  - Include jitter.
- Ensure the in-flight `job_id` batch (max `50` items) is not dropped during reconnection.
- Set `WORKER_CONCURRENCY` to `4` by default.
- Send a warning to `Sentry` if queue latency exceeds `250ms`.
```
> [!NOTE]
> **Zero Omission**: 100% of user technical details preserved.

---

### Draft 2: Zero-Omission Exhaustive Spec (New WhisperDoc Prompt)
*Exhaustive detail preservation mandate for AI model interpretation.*

```markdown
### Technical Specification: Sync Worker Architecture Update

#### 1. Event-Driven Notification Mechanism
*   **Replace Polling Logic**: Remove the existing polling mechanism that queries `postgres` at a fixed interval of `500ms`.
*   **Implement LISTEN/NOTIFY**: Establish a persistent connection to `postgres` and subscribe to the `jobs` channel using the `LISTEN` command.
*   **Event Handling**: Process job notifications received via `NOTIFY` events on the `jobs` channel.

#### 2. Connection Resilience & Reconnection Strategy
*   **Failure Detection**: Monitor the `postgres` connection for specific error conditions:
    *   `ECONNRESET`
    *   Socket timeout
*   **Reconnection Algorithm**: Upon detection of a connection drop, execute an exponential backoff strategy with the following parameters:
    *   **Initial Delay**: `100ms`
    *   **Maximum Delay**: `5000ms`
    *   **Jitter**: Apply random jitter to the backoff interval to prevent thundering herd effects.

#### 3. Data Integrity & Batch Processing
*   **In-Flight Batch Preservation**: Ensure that the in-flight `job_id` batch is not dropped during connection failures or reconnection attempts.
*   **Batch Capacity Constraint**: The in-flight batch must support a maximum capacity of `50` items.

#### 4. Configuration & Performance Monitoring
*   **Concurrency Setting**: Set the environment variable `WORKER_CONCURRENCY` to a default value of `4`.
*   **Latency Alerting**:
    *   **Threshold**: Monitor queue latency.
    *   **Action**: If queue latency exceeds `250ms`, send a warning event to `Sentry`.
```
> [!NOTE]
> **Zero Omission**: 100% of user technical details preserved.

---

### Draft 3: Direct AI-Agent Directive
*Formatted specifically as structured directive for downstream coding agents.*

```markdown
### Objective
Refactor the `sync_worker` to replace the current PostgreSQL polling mechanism with a reactive `LISTEN/NOTIFY` architecture, implementing robust connection resilience, strict data integrity for in-flight batches, and enhanced observability.

### Technical Constraints
*   **Communication Protocol**: Replace polling every `500ms` with `LISTEN NOTIFY` on the `jobs` channel.
*   **Connection Resilience**:
    *   Trigger reconnection logic specifically on `ECONNRESET` or socket timeout events.
    *   Implement exponential backoff for reconnection attempts.
    *   Initial backoff delay: `100ms`.
    *   Maximum backoff delay: `5000ms`.
    *   Apply jitter to the backoff calculation.
*   **Data Integrity**:
    *   Ensure the in-flight `job_id` batch is never dropped during connection failures or reconnection cycles.
    *   Maximum batch size: `50` items.
*   **Concurrency**:
    *   Set `WORKER_CONCURRENCY` to `4` by default.
*   **Observability**:
    *   Monitor queue latency.
    *   If latency exceeds `250ms`, send a warning to Sentry.

### Execution Steps
1.  **Refactor Connection Logic**:
    *   Remove the existing `500ms` polling interval.
    *   Initialize a PostgreSQL connection subscribed to the `jobs` channel using `LISTEN`.
    *   Implement a `NOTIFY` listener to trigger job processing upon message receipt.
2.  **Implement Reconnection Strategy**:
    *   Attach event listeners for `ECONNRESET` and socket timeout errors.
    *   Develop an exponential backoff function starting at `100ms` and capping at `5000ms`.
    *   Integrate jitter into the backoff delay calculation to prevent thundering herd issues.
3.  **Enforce Batch Integrity**:
    *   Verify that the in-flight `job_id` batch (max `50` items) is persisted or held in memory safely during connection drops.
    *   Ensure no `job_id` is lost when the connection is re-established.
4.  **Configure Concurrency**:
    *   Update the worker configuration to set `WORKER_CONCURRENCY` to `4` as the default value.
5.  **Add Latency Monitoring**:
    *   Instrument the queue processing pipeline to measure latency.
    *   Implement a check: if latency > `250ms`, trigger a Sentry warning event.
```
> [!NOTE]
> **Zero Omission**: 100% of user technical details preserved.

---

### Draft 4: Technical Acceptance Criteria
*Formats thoughts into an explicit engineering ticket with acceptance criteria.*

```markdown
## Overview
The sync worker implementation must transition from a polling-based architecture to an event-driven model using PostgreSQL `LISTEN/NOTIFY`. The system must handle connection instability via exponential backoff with jitter, preserve in-flight data integrity during disconnections, enforce specific concurrency limits, and implement latency monitoring with external alerting.

## Technical Requirements

**1. Event Subscription Mechanism**
*   **Remove**: Polling logic targeting `postgres` with an interval of `500ms`.
*   **Implement**: `LISTEN NOTIFY` subscription on the `jobs` channel.

**2. Connection Resilience & Backoff**
*   **Trigger Conditions**: Connection drop events identified by `ECONNRESET` or `socket timeout`.
*   **Backoff Strategy**: Exponential backoff.
*   **Initial Delay**: `100ms`.
*   **Maximum Delay**: `5000ms`.
*   **Jitter**: Must be applied to the backoff calculation.

**3. Data Integrity**
*   **In-Flight Data**: The `job_id` batch must not be dropped during connection failures.
*   **Batch Capacity**: The in-flight `job_id` batch must support up to `50` items.

**4. Concurrency Configuration**
*   **Variable**: `WORKER_CONCURRENCY`.
*   **Default Value**: `4`.

**5. Monitoring & Alerting**
*   **Metric**: Queue latency.
*   **Threshold**: `250ms`.
*   **Action**: If latency exceeds `250ms`, send a warning to `Sentry`.

## Acceptance Criteria

1.  **No Polling**: Code inspection confirms the absence of any `500ms` polling loop against `postgres`.
2.  **Active Subscription**: The worker successfully establishes a `LISTEN` connection to the `jobs` channel.
3.  **Backoff Verification**:
    *   Upon simulating an `ECONNRESET` or `socket timeout`, the retry delay starts at `100ms`.
    *   Subsequent retries increase exponentially.
    *   The retry delay never exceeds `5000ms`.
    *   Jitter is present in the delay calculation (non-deterministic variance within bounds).
4.  **Data Persistence**:
    *   Simulate a connection drop while holding a batch of `job_id`s.
    *   Verify that the batch is retained in memory/state and not discarded.
    *   Verify the system can handle a batch size of `50` `job_id`s without error.
5.  **Concurrency Check**:
    *   Verify that `WORKER_CONCURRENCY` defaults to `4` if not explicitly overridden.
6.  **Latency Alerting**:
    *   Simulate queue latency exceeding `250ms`.
    *   Verify that a warning event is dispatched to `Sentry`.
    *   Verify that no warning is sent if latency is `250ms` or less.
```
> [!NOTE]
> **Zero Omission**: 100% of user technical details preserved.

---

### Draft 5: Minimal Verbatim Polish with Code Casing
*Retains original speech flow closely while wrapping code symbols and fixing grammar.*

```markdown
So basically, what we need to do for the sync worker is, instead of polling `postgres` every `500ms`, we need to switch to `LISTEN NOTIFY` on the `jobs` channel. And if the connection drops with an `ECONNRESET` or socket timeout, we have to use exponential backoff starting at `100ms`, maxing out at `5000ms` with jitter. Also, make sure we do not drop the in-flight `job_id` batch, which can hold up to `50` items. Also, set `WORKER_CONCURRENCY` to `4` by default and send a warning to `Sentry` if queue latency exceeds `250ms`.
```
> [!NOTE]
> **Zero Omission**: 100% of user technical details preserved.

---
