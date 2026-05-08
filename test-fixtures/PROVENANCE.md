# test-fixtures/

## demo-audio-for-gemma.wav

- **Source:** Simon Willison's voice memo, supplied to the gemma-on-vm
  contract on 2026-05-05 (PLAN.md F4 reference). Used as a test fixture
  for ASR reproducibility checks.
- **Format:** WAV, 48 kHz mono PCM, ~14 s.
- **Size:** 1,347,662 bytes.
- **SHA-256:** `4bbb06bca4b3188f5d957adbf176485d6a0a7420b0dcb25bce52263e5d5d4735`

## demo-audio-for-gemma.expected.txt

The canonical whisperX `--task translate` output for the WAV above,
captured on the gemma-on-vm VM (Apple M3 Max, paravirtualised UTM).

- **Backend:** whisperx 3.8.5 + faster-whisper-large-v3 (Systran)
- **Flags:** `--model large-v3 --task translate --output_format txt --no_align --compute_type float32`
- **Reproduced byte-identical across:** T2-repeat run1, T2-repeat run2, T3-resource, T4-egress (4 independent runs on 2026-05-06).
- **SHA-256:** `dc4ff7e23a04ac6b0051882858dec69be5e070343db496d5d1c21d42c6c7bada`

This is the empirical basis for `dictate-verify`'s strict equality check.
The byte-stability is documented as PLAN.md F29 ("whisperX is byte-deterministic
at the default temperature").

## Why these are bundled in the tap

`brew install psibook/dictation/dictation-stack` installs the runtime tools
but cannot prove they work end-to-end without a known input + known output.
These fixtures let `dictate-verify` produce a binary PASS/FAIL verdict that
covers the entire stack (ffmpeg + uv + whisperX + faster-whisper + Metal
driver path) on the host, in one command.

## Provenance for downstream forks

If you fork this tap and want to swap in your own audio fixture:

1. Replace `demo-audio-for-gemma.wav` with your file.
2. Compute its SHA-256:
   ```
   shasum -a 256 your-fixture.wav
   ```
3. Run whisperX once with the flags above to capture the expected output:
   ```
   whisperx your-fixture.wav --model large-v3 --task translate \
     --output_format txt --no_align --compute_type float32 \
     --output_dir /tmp/expected
   shasum -a 256 /tmp/expected/your-fixture.txt
   ```
4. Update `*.input.sha256`, `*.expected.txt`, `*.expected.sha256` accordingly.
