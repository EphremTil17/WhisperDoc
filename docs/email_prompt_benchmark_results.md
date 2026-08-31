# Email System Prompt Benchmark Evaluation

**Model**: `qwen/qwen3.8-27b`
**Evaluated At**: 2026-09-05

## Variant_1_Cue_Routing

### Test: `full_email_sarah` (Full Email (Review Request))

- **Spoken Transcript**: *"hey sarah just checking if you reviewed the Q3 slide deck need your thumbs up before monday"*
- **Expected Behavior**: Full email with Subject, greeting, body, and sign-off
- **Latency**: `481.6ms` | **Tokens**: `87` | **Expansion Ratio**: `3.79x`

```markdown
Subject: Quick review on Q3 slide deck

Hi Sarah,

Hope you're having a good week.

Just checking in to see if you have had a chance to look over the Q3 slides. We are hoping to get your sign-off before Monday. Whenever you get a moment, please take a look and let me know if everything looks good or if you'd like any adjustments.

Best,
Alex
```

### Test: `inline_addition_figma` (Inline Addition (Continuation Cue: 'also'))

- **Spoken Transcript**: *"also please make sure the design team has the figma link before noon tomorrow"*
- **Expected Behavior**: Inline paragraph only (NO Subject, NO greeting, NO sign-off)
- **Latency**: `339.1ms` | **Tokens**: `27` | **Expansion Ratio**: `1.64x`

```markdown
Also, please make sure the design team has the Figma link before noon tomorrow so they have enough time to review the layouts.
```

### Test: `inline_addition_one_more_thing` (Inline Addition (Continuation Cue: 'one more thing'))

- **Spoken Transcript**: *"one more thing don't forget to push the staging build tonight so QA can test tomorrow morning"*
- **Expected Behavior**: Inline paragraph only (NO Subject, NO greeting, NO sign-off)
- **Latency**: `324.4ms` | **Tokens**: `27` | **Expansion Ratio**: `1.44x`

```markdown
Also, please don't forget to push the staging build tonight so the QA team has everything they need to start testing tomorrow morning.
```

### Test: `quick_reply_mark` (Quick Reply / Confirmation)

- **Spoken Transcript**: *"thanks mark let's go with option b and sync on friday to review progress"*
- **Expected Behavior**: Quick reply body with greeting and sign-off, or inline reply
- **Latency**: `372.7ms` | **Tokens**: `48` | **Expansion Ratio**: `2.61x`

```markdown
Subject: Moving forward with Option B

Hi Mark,

Thanks for the update. Let's go ahead with Option B. Let's sync up on Friday to review progress and see where things stand.

Thanks,
Alex
```

### Test: `bulleted_tasks` (Multi-Task Email to Team)

- **Spoken Transcript**: *"email the dev team three things first fix the auth timeout second update redis cache keys and third check sentry before deploying"*
- **Expected Behavior**: Subject, greeting, bulleted list of 3 items, and sign-off
- **Latency**: `464.5ms` | **Tokens**: `96` | **Expansion Ratio**: `3.17x`

```markdown
Subject: Pre-deployment checklist

Hi Team,

Hope you're having a good week.

Before we move forward with the next deployment, there are three quick items we need to address:

- Fix the auth timeout issue
- Update the Redis cache keys
- Check Sentry for any new errors

Please take a look at these when you get a chance. Let me know once everything is resolved so we can proceed with confidence.

Best,
Alex
```

## Variant_2_Intent_Classification

### Test: `full_email_sarah` (Full Email (Review Request))

- **Spoken Transcript**: *"hey sarah just checking if you reviewed the Q3 slide deck need your thumbs up before monday"*
- **Expected Behavior**: Full email with Subject, greeting, body, and sign-off
- **Latency**: `453.0ms` | **Tokens**: `84` | **Expansion Ratio**: `3.55x`

```markdown
Subject: Quick check: Q3 slide deck

Hi Sarah,

Hope you're having a good week.

I'm just checking in to see if you've had a chance to review the Q3 slide deck. I'd really appreciate your thumbs up before Monday so we can finalize everything on our end.

Whenever you get a moment, let me know what you think.

Best,
Alex
```

### Test: `inline_addition_figma` (Inline Addition (Continuation Cue: 'also'))

- **Spoken Transcript**: *"also please make sure the design team has the figma link before noon tomorrow"*
- **Expected Behavior**: Inline paragraph only (NO Subject, NO greeting, NO sign-off)
- **Latency**: `318.5ms` | **Tokens**: `18` | **Expansion Ratio**: `1.03x`

```markdown
Also, please make sure the design team has the Figma link before noon tomorrow.
```

### Test: `inline_addition_one_more_thing` (Inline Addition (Continuation Cue: 'one more thing'))

- **Spoken Transcript**: *"one more thing don't forget to push the staging build tonight so QA can test tomorrow morning"*
- **Expected Behavior**: Inline paragraph only (NO Subject, NO greeting, NO sign-off)
- **Latency**: `341.1ms` | **Tokens**: `25` | **Expansion Ratio**: `1.29x`

```markdown
One more thing: please don't forget to push the staging build tonight so the QA team can start testing tomorrow morning.
```

### Test: `quick_reply_mark` (Quick Reply / Confirmation)

- **Spoken Transcript**: *"thanks mark let's go with option b and sync on friday to review progress"*
- **Expected Behavior**: Quick reply body with greeting and sign-off, or inline reply
- **Latency**: `401.1ms` | **Tokens**: `65` | **Expansion Ratio**: `3.22x`

```markdown
Subject: Re: Next steps - Option B

Hi Mark,

Thanks for the options. Let's go ahead with Option B.

I'd like to sync up on Friday to review our progress and make sure we're on track. Let me know if that works for you.

Best,
Alex
```

### Test: `bulleted_tasks` (Multi-Task Email to Team)

- **Spoken Transcript**: *"email the dev team three things first fix the auth timeout second update redis cache keys and third check sentry before deploying"*
- **Expected Behavior**: Subject, greeting, bulleted list of 3 items, and sign-off
- **Latency**: `439.9ms` | **Tokens**: `97` | **Expansion Ratio**: `3.19x`

```markdown
Subject: Three quick items before deployment

Hi Team,

Hope you're having a good week.

I wanted to flag three things we need to handle before we move forward with the deployment. First, please fix the auth timeout issue. Second, we need to update the Redis cache keys. And third, make sure to check Sentry for any new errors before we push.

Whenever you get a moment, let me know what you think.

Best,
Alex
```

## Variant_3_Template_Interpolation

### Test: `full_email_sarah` (Full Email (Review Request))

- **Spoken Transcript**: *"hey sarah just checking if you reviewed the Q3 slide deck need your thumbs up before monday"*
- **Expected Behavior**: Full email with Subject, greeting, body, and sign-off
- **Latency**: `450.0ms` | **Tokens**: `85` | **Expansion Ratio**: `3.7x`

```markdown
Subject: Quick check: Q3 slide deck review

Hi Sarah,

Hope you're having a good week.

I'm just checking in to see if you've had a chance to review the Q3 slide deck. I'd really appreciate your thumbs up before Monday so we can finalize everything on time.

Whenever you get a chance, let me know if everything looks good.

Best,
Alex
```

### Test: `inline_addition_figma` (Inline Addition (Continuation Cue: 'also'))

- **Spoken Transcript**: *"also please make sure the design team has the figma link before noon tomorrow"*
- **Expected Behavior**: Inline paragraph only (NO Subject, NO greeting, NO sign-off)
- **Error**: `HTTP 429: {"error":{"message":"Rate limit reached for model `qwen/qwen3.8-27b` in organization `org_01kgkma6w2fqksh9ek090yrvnm` service tier `on_demand` on input tokens per minute (ITPM): Limit 7000, Used 6745,`

### Test: `inline_addition_one_more_thing` (Inline Addition (Continuation Cue: 'one more thing'))

- **Spoken Transcript**: *"one more thing don't forget to push the staging build tonight so QA can test tomorrow morning"*
- **Expected Behavior**: Inline paragraph only (NO Subject, NO greeting, NO sign-off)
- **Error**: `HTTP 429: {"error":{"message":"Rate limit reached for model `qwen/qwen3.8-27b` in organization `org_01kgkma6w2fqksh9ek090yrvnm` service tier `on_demand` on input tokens per minute (ITPM): Limit 7000, Used 6668,`

### Test: `quick_reply_mark` (Quick Reply / Confirmation)

- **Spoken Transcript**: *"thanks mark let's go with option b and sync on friday to review progress"*
- **Expected Behavior**: Quick reply body with greeting and sign-off, or inline reply
- **Error**: `HTTP 429: {"error":{"message":"Rate limit reached for model `qwen/qwen3.8-27b` in organization `org_01kgkma6w2fqksh9ek090yrvnm` service tier `on_demand` on input tokens per minute (ITPM): Limit 7000, Used 6576,`

### Test: `bulleted_tasks` (Multi-Task Email to Team)

- **Spoken Transcript**: *"email the dev team three things first fix the auth timeout second update redis cache keys and third check sentry before deploying"*
- **Expected Behavior**: Subject, greeting, bulleted list of 3 items, and sign-off
- **Error**: `HTTP 429: {"error":{"message":"Rate limit reached for model `qwen/qwen3.8-27b` in organization `org_01kgkma6w2fqksh9ek090yrvnm` service tier `on_demand` on input tokens per minute (ITPM): Limit 7000, Used 6493,`

