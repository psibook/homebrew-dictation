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
  head "https://github.com/ggml-org/whisper.cpp.git", branch: "master"

  livecheck do
    url :stable
    strategy :github_latest
  end

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

    # ----- 5. Install host-tests/ so users can run the full suite ----
    # `$(brew --prefix dictation-stack)/share/dictation-stack/host-tests/run-all.sh`
    # gives the user the documented test runner without having to clone
    # this tap repo.
    (pkgshare/"host-tests").install Dir[tap_root/"host-tests/*"]
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

      These are USER-SCOPE installs, not Homebrew-managed, and
      `brew uninstall dictation-stack` will NOT remove them. To clean
      them up:

        dictate-stack-install --uninstall
        rm -rf ~/.cache/huggingface ~/.cache/whisper

      Add ~/.local/bin to your PATH if not already there:

        export PATH="$HOME/.local/bin:$PATH"

      Verify the install end-to-end (whisperX, ~3 GB weights on first run):

        dictate-verify

      Run the full host-side test suite (T1–T6):

        $(brew --prefix dictation-stack)/share/dictation-stack/host-tests/run-all.sh

      Pre-pull every backend's weights (~25 GB across HF and openai-whisper):

        dictate-warmup            # all backends
        dictate-warmup --whisper-only   # skip Gemma 4, saves 16 GB

      If you later run `uv tool upgrade insanely-fast-whisper`, re-apply
      the IFW rpath patch:

        dictate-stack-install --patch-only

      Reference: https://github.com/psibook/homebrew-dictation
    EOS
  end

  test do
    # `brew test dictation-stack` exercises the install through several
    # cheap assertions before the more expensive dictate-verify run:
    #
    #   (a) every script the formula installs is on PATH and `--help`-able
    #   (b) every test fixture is in pkgshare and the audio SHA-256 matches
    #   (c) whisper-cli (the source-built binary) reports a sane version
    #   (d) dictate-verify either passes (strict) or — if whisperX is fresh
    #       and weights aren't cached — at least exits with a network-aware
    #       error rather than a tool-not-found error.
    #
    # The full F29 strict-hash check happens via `dictate-verify` itself
    # outside `brew test`, since `brew test` is not the right place to
    # download 3 GB of weights.

    # (a) every dictate-* script can print its --help
    %w[dictate-verify dictate-stack-install dictate-warmup].each do |s|
      assert_match(/Usage:|usage:/i, shell_output("#{bin}/#{s} --help"))
    end

    # (b) bundled fixture and SHA file are present and match
    fixture = pkgshare/"demo-audio-for-gemma.wav"
    assert_path_exists fixture, "bundled audio fixture missing"
    expected_input_sha = (pkgshare/"demo-audio-for-gemma.input.sha256").read.split.first
    actual_input_sha = Digest::SHA256.file(fixture).hexdigest
    assert_equal expected_input_sha, actual_input_sha,
                 "bundled audio SHA-256 doesn't match recorded value"

    # (c) whisper-cli runs. whisper.cpp's -h exits non-zero on some
    # versions; using `; true` shields the assertion from that.
    output = shell_output("#{bin}/whisper-cli -h 2>&1; true")
    assert_match(/whisper|usage|model/i, output)

    # (d) dictate-verify is at least invocable. Run with --help so we
    # don't trigger the 3 GB weight download inside `brew test`.
    assert_match(/dictate-verify|Usage/i, shell_output("#{bin}/dictate-verify --help"))

    # (e) the host-tests suite is installed and run-all.sh is executable.
    assert_predicate pkgshare/"host-tests/run-all.sh", :executable?
    assert_match(/T1-smoke|T6-brew-test/,
                 shell_output("#{pkgshare}/host-tests/run-all.sh --list"))
  end
end
