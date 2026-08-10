# FnScribe

FnScribe is a small macOS dictation helper:

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
FNSCRIBE_START_SOUND="Tink"
FNSCRIBE_STOP_SOUND="Pop"
OPENAI_TRANSCRIBE_MODEL="gpt-4o-mini-transcribe"
OPENAI_CLEANUP_MODEL="gpt-5-mini"
```

Set `OPENAI_CLEANUP_MODEL=""` to skip cleanup and make completion faster.

Set `FNSCRIBE_SOUND="0"` to disable start/stop sound cues.

Other built-in macOS sound names include `Ping`, `Glass`, `Bottle`, `Hero`, `Submarine`, and `Morse`.

## Data

FnScribe stores local working data under `work/` by default:

- audio recordings
- transcript history
- logs

It mirrors browser-readable files into `public/`.

Both `work/` and `public/` are ignored by git.

## Notes

The experimental WidgetKit project under `Native/` is included, but the practical supported UI is the menu bar app. macOS Notification Center widgets require native signed WidgetKit extensions and can be finicky for local/ad-hoc builds.
