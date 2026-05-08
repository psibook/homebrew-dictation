class DictationStack < Formula
  desc "Local audio→text + audio→reasoning stack (5 Whisper backends + Gemma 4)"
  homepage "https://github.com/psibook/homebrew-dictation"
  # The formula's `url` is whisper.cpp's source tarball — the only component
  # of the stack that gets compiled rather than `uv tool install`-ed.
  url "https://github.com/ggml-org/whisper.cpp/archive/refs/tags/v1.8.4.tar.gz"
  # Formula version is independent of whisper.cpp's tag because this formula
  # also vends the dictate-* scripts and test fixtures.
  version "0.1.0"
  sha256 "b26f30e52c095ccb75da40b168437736605eb280de57381887bf9e2b65f31e66"
  license "MIT"

  # MLX, Metal, MPS, codesign and install_name_tool are macOS-only.
  # ffmpeg@7 provides libavutil.59, which torchcodec 0.7 binds against —
  # required for insanely-fast-whisper to load. See PLAN.md F3 in
  # https://github.com/psibook/gemma-on-vm.
  depends_on "cmake" => :build
  depends_on "ffmpeg"
  depends_on "ffmpeg@7"
  depends_on :macos
  depends_on "uv"

  def install
    # ----- 1. Build whisper.cpp from staged source -------------------
    # GGML_METAL=ON enables Metal acceleration on Apple Silicon. Confirmed
    # to work under UTM paravirtualisation (PLAN.md F1).
    system "cmake", "-B", "build",
           *std_cmake_args,
           "-DCMAKE_BUILD_TYPE=Release",
           "-DGGML_METAL=ON"
    system "cmake", "--build", "build", "-j", "--config", "Release"
    bin.install "build/bin/whisper-cli"
    bin.install "build/bin/whisper-server" if File.exist?("build/bin/whisper-server")

    # ----- 2. Locate the tap root via __dir__ ------------------------
    # The formula file lives at <tap>/Formula/dictation-stack.rb. __dir__
    # is the Formula/ directory; its parent is the tap root, where bin/
    # and test-fixtures/ live.
    tap_root = Pathname.new(__dir__).parent

    # ----- 3. Install the dictation-stack helper scripts -------------
    bin.install tap_root/"bin/dictate-verify"
    bin.install tap_root/"bin/dictate-stack-install"
    bin.install tap_root/"bin/dictate-warmup"

    # ----- 4. Install test fixtures into pkgshare --------------------
    pkgshare.install tap_root/"test-fixtures/demo-audio-for-gemma.wav"
    pkgshare.install tap_root/"test-fixtures/demo-audio-for-gemma.input.sha256"
    pkgshare.install tap_root/"test-fixtures/demo-audio-for-gemma.expected.txt"
    pkgshare.install tap_root/"test-fixtures/demo-audio-for-gemma.expected.sha256"
    pkgshare.install tap_root/"test-fixtures/PROVENANCE.md"
  end

  def post_install
    # Run dictate-stack-install to:
    #   - uv tool install the 5 Python tools (openai-whisper, mlx-whisper,
    #     whisperx, insanely-fast-whisper, mlx-vlm)
    #   - apply the IFW torchcodec rpath patch (PLAN.md F5/F27)
    #
    # This deliberately writes into ~/.local/share/uv/tools/ — outside the
    # Homebrew prefix. ADR-002 (decisions/ADR-002-tap-structure.md) records
    # the trade-off. If this step fails, the user can re-run
    # `dictate-stack-install` by hand without re-installing the formula.
    system bin/"dictate-stack-install"
  end

  def caveats
    <<~EOS
      The dictation-stack post-install pulled five Python tools into your
      uv tool directory (typically ~/.local/share/uv/tools/):

        openai-whisper, mlx-whisper, whisperx,
        insanely-fast-whisper (with torch>=2.11 + rpath patch),
        mlx-vlm

      These are USER-SCOPE installs, not Homebrew-managed, and `brew uninstall
      dictation-stack` will NOT remove them. To clean them up:

        dictate-stack-install --uninstall
        rm -rf ~/.cache/huggingface ~/.cache/whisper

      Add ~/.local/bin to your PATH if not already there:

        export PATH="$HOME/.local/bin:$PATH"

      Verify the install end-to-end (runs whisperX on a bundled WAV; first
      run pulls ~3 GB of weights from huggingface.co):

        dictate-verify

      Pre-pull all model weights for all 6 backends (~25 GB):

        dictate-warmup            # all backends
        dictate-warmup --whisper-only   # skip Gemma 4 (saves 16 GB)

      If you later run `uv tool upgrade insanely-fast-whisper`, re-apply
      the rpath patch:

        dictate-stack-install --patch-only

      Reference: https://github.com/psibook/homebrew-dictation
    EOS
  end

  test do
    # `brew test dictation-stack` runs dictate-verify, which:
    #   1. verifies the bundled audio's SHA-256
    #   2. runs whisperX --task translate (downloading weights on first run)
    #   3. compares the transcript against a hash recorded across 4 runs
    #      on the gemma-on-vm VM (PLAN.md F29 — byte-deterministic).
    #
    # On a fresh test machine this can take 5–10 minutes the first time
    # (model download). Subsequent runs are <40 s.
    system bin/"dictate-verify"
  end
end
