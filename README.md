# FnScribe

FnScribe is a small macOS dictation helper and Wispr Flow alternative:

- Hold `Fn` to record; release to stop.
- Double-tap `Fn` to start/stop a longer recording.
- Transcribes with OpenAI speech-to-text.
- Optionally cleans up the transcript with a text model.
- Pastes a `transcribing...` placeholder immediately, then replaces it with the final text.
- Copies the finished transcript to the clipboard.
- Keeps local transcript history.
- Provides a tiny menu bar app for copying recent transcripts.

## Requirements

- macOS
- Xcode command line tools / Xcode
- An OpenAI API key with API credits
- Microphone permission
- Accessibility permission for the terminal/app that runs FnScribe

ChatGPT subscriptions do not include API credits by default.

## Setup

```sh
cp .env.example .env
```

Edit `.env` and add your API key:

```sh
OPENAI_API_KEY="your-api-key"
```

Build:

```sh
scripts/build.sh
```

Run interactively:

```sh
scripts/run.sh
```

## Install at Login

Install the recorder service:

```sh
scripts/install-recorder-launch-agent.sh
```

Install the menu bar recent-transcripts app:

```sh
scripts/install-menu-launch-agent.sh
```

Remove both launch agents:

```sh
scripts/uninstall-launch-agents.sh
```

## Menu Bar App

After installing or running the menu app, look for **Fn** in the macOS menu bar. It shows the latest five transcripts and lets you copy cleaned or raw text.

## Cost Compared With Wispr Flow

Wispr Flow Pro is listed at about `$15/user/month` monthly, or about `$12/user/month` when billed annually. FnScribe uses your own OpenAI API key instead of a subscription.

With the default `gpt-4o-mini-transcribe` model, OpenAI lists transcription at about `$0.003/minute` of audio. At that rate:

- `$15` buys roughly `5,000` minutes, or about `83` hours, of transcription.
- `$12` buys roughly `4,000` minutes, or about `67` hours, of transcription.

FnScribe also optionally sends the transcript through a cleanup model, so your real cost will be a little higher when cleanup is enabled. For short dictation, that cleanup cost is usually small compared with the transcription cost.

One real early-use sample from FnScribe's local history:

- `18` transcriptions
- `4.52` minutes of recorded audio
- about `3,854` raw transcript characters
- about `3,576` cleaned transcript characters
- transcription estimate: about `$0.0136`
- cleanup estimate with `gpt-5-mini`: about `$0.0023`
- total estimate: about `$0.0159`, or `1.6 cents`

That cleanup estimate is approximate because local history stores the transcript text, not the exact billable token count from the API. It includes a rough allowance for the cleanup instruction sent with each request. In this sample, a `$10` API credit would cover roughly `2,800-3,000` minutes of similar short-form dictation with cleanup enabled.

Try it for a week or two and compare your actual API usage against what you would pay for Wispr Flow. If you dictate constantly, a polished subscription app may still be worth it. If you mostly do short bursts of dictation, FnScribe may save you money.

Current pricing can change, so check:

- OpenAI transcription pricing: <https://developers.openai.com/api/docs/models/gpt-4o-mini-transcribe>
- OpenAI API pricing: <https://openai.com/api/pricing/>
- Wispr Flow pricing: <https://wisprflow.ai/business>

## Local History UI

The recorder writes a local UI into `public/` and serves it at:

```text
http://127.0.0.1:8765/fn-scribe-history.html
```

This is mainly useful for debugging and reviewing the full transcript list.

## Configuration

Set values in `.env`:

```sh
FNSCRIBE_TRIGGER="fn"
FNSCRIBE_HISTORY_LIMIT="50"
FNSCRIBE_SOUND="1"
FNSCRIBE_START_SOUND="Ping"
FNSCRIBE_STOP_SOUND="Pop"
FNSCRIBE_COMPLETE_SOUND="Glass"
OPENAI_TRANSCRIBE_MODEL="gpt-4o-mini-transcribe"
OPENAI_CLEANUP_MODEL="gpt-5-mini"
```

Set `OPENAI_CLEANUP_MODEL=""` to skip cleanup and make completion faster.

Set `FNSCRIBE_SOUND="0"` to disable sound cues.

Other built-in macOS sound names include `Ping`, `Glass`, `Bottle`, `Hero`, `Submarine`, and `Morse`.

## Data

FnScribe stores local working data under `work/` by default:

- audio recordings
- transcript history
- logs

It mirrors browser-readable files into `public/`.

Both `work/` and `public/` are ignored by git.
