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
- A code signing certificate (see [Signing](#signing)) so permissions survive rebuilds
- Three macOS permissions for the recorder binary (see [Permissions](#permissions)):
  - Microphone
  - Input Monitoring, to detect the `Fn` key
  - Accessibility, to paste the transcript

ChatGPT subscriptions do not include API credits by default.

## Setup

```sh
cp .env.example .env
```

Edit `.env` and add your API key:

```sh
OPENAI_API_KEY="your-api-key"
```

Create your signing certificate before building, so the build can use it — see
[Signing](#signing). Skipping this step means re-granting macOS permissions
after every single rebuild.

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

The menu agent records the repository path it was installed from. If you move
the repository, re-run both install scripts, or the menu app will keep reading
status from the old location and never update.

## Signing

Do this before granting permissions, or you will grant them twice.

macOS ties permission grants to a binary's code signature. The default build is
ad-hoc signed, which means the signature is keyed by a hash of the binary
itself: every rebuild produces a new hash, macOS treats the result as different
software, and **every permission you granted is silently revoked**. Nothing
fails loudly. The recorder starts normally, the key tap is created
successfully, and no events ever arrive.

Signing with your own certificate fixes this, because the resulting requirement
names the certificate rather than the binary's hash, and so keeps matching
after a rebuild.

Create the certificate once, in Keychain Access:

1. **Keychain Access → Certificate Assistant → Create a Certificate…**
2. Name: `FnScribe Dev`
3. Identity Type: **Self Signed Root**
4. Certificate Type: **Code Signing**
5. Create.

`scripts/build.sh` picks it up automatically by name. Override with
`FNSCRIBE_SIGN_IDENTITY` if you named it something else. If no matching
certificate exists, the build warns and falls back to ad-hoc signing.

To confirm a build is signed the durable way:

```sh
codesign -d -r- work/bin/fn-scribe
```

Look for a requirement naming `certificate leaf`, with no `cdhash`:

```text
designated => identifier "local.fnscribe.recorder" and certificate leaf = H"..."
```

`security find-identity -v -p codesigning` may report `0 valid identities` for a
self-signed root, because it is not marked as trusted. That is expected and does
not prevent signing.

## Permissions

FnScribe needs two separate permissions that are easy to confuse. Granting one
does not grant the other, and each failure looks different:

| Permission | Used for | Symptom when missing |
| --- | --- | --- |
| Input Monitoring | Detecting the `Fn` key | Pressing `Fn` does nothing at all |
| Accessibility | Pasting via synthetic `Cmd+V` | Recording and transcription work, clipboard is correct, but nothing is pasted and no placeholder appears |

Grant both to the recorder **binary**, not to your terminal:

```text
work/bin/fn-scribe
```

When FnScribe runs as a launch agent, macOS cannot show a permission prompt, so
nothing will ever ask you. Add the binary by hand:

1. Open **System Settings → Privacy & Security → Input Monitoring**.
2. Unlock the pane, or the toggle will not stick.
3. Drag `work/bin/fn-scribe` in from Finder, then switch the toggle on.
4. Repeat under **Privacy & Security → Accessibility**.
5. Restart the recorder:

```sh
launchctl kickstart -k "gui/$(id -u)/local.fnscribe.recorder"
```

If an entry for `fn-scribe` is already listed, remove it with `−` before adding
it again. A stale entry from an earlier build takes precedence over a new one.

The recorder logs what it actually has at startup, so you never have to infer
permissions from symptoms:

```sh
grep "Permissions:" work/fn-scribe.log | tail -1
```

```text
Permissions: accessibility(post events)=true inputMonitoring(listen)=true
```

Microphone is different: it prompts normally the first time, and the log
records the result as `Microphone access granted.`

## Troubleshooting

Everything the recorder does is logged:

```sh
tail -f work/fn-scribe.log
```

**Pressing `Fn` does nothing.** Check the recorder is actually running, since
the menu bar app runs as a separate agent and its presence proves nothing:

```sh
launchctl list | grep fnscribe
```

If it is running, check the `Permissions:` line for
`inputMonitoring(listen)=false`. If it is `true` and the key still does nothing,
confirm the binary is signed with your certificate, not ad-hoc.

**Nothing pastes, but the clipboard has the right text.** Accessibility is
missing. The transcript is complete, so paste the text manually with `Cmd+V`
until the permission is granted.

**Permissions worked, then stopped after a rebuild.** The build fell back to
ad-hoc signing. Check for the warning in the build output, confirm the
certificate exists, then re-grant both permissions once.

**The menu bar item is missing or stale.** Confirm the menu agent points at the
current repository path:

```sh
grep -A1 FNSCRIBE_PROJECT_ROOT ~/Library/LaunchAgents/local.fnscribe.menu.plist
```

Re-run `scripts/install-menu-launch-agent.sh` if it points somewhere else.

**No sound cues.** Confirm `FNSCRIBE_SOUND` is not `0`, then check the sound
cues are audible outside FnScribe: the output device, the alert volume in Sound
settings (separate from the main volume), and Focus modes all silence them
independently of this app.

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
FNSCRIBE_CLEANUP_MODE="auto"
```

`FNSCRIBE_CLEANUP_MODE` controls when FnScribe uses the cleanup model:

- `auto`: skip cleanup for short, clean-looking transcripts and clean up messier dictation.
- `always`: always run the cleanup model.
- `never`: never run the cleanup model.

Set `OPENAI_CLEANUP_MODEL=""` to disable cleanup completely and make completion faster.

Set `FNSCRIBE_SOUND="0"` to disable sound cues.

Other built-in macOS sound names include `Ping`, `Glass`, `Bottle`, `Hero`, `Submarine`, and `Morse`.

## Data

FnScribe stores local working data under `work/` by default:

- audio recordings
- transcript history
- logs

It mirrors browser-readable files into `public/`.

Both `work/` and `public/` are ignored by git.
