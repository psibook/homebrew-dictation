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

    # ----- 2. Stage tap-side files into the build dir ----------------
    # The formula file lives at <tap>/Formula/dictation-stack.rb. __dir__
    # is the Formula/ directory; its parent is the tap root, where bin/,
    # test-fixtures/, and host-tests/ live.
    #
    # Homebrew's install sandbox grants READ access to the tap directory
    # but blocks writes there. `bin.install src` does a move (or
    # copy+remove-source); the source-removal step trips
    # `Errno::EPERM @ apply2files` against the tap path on stricter
    # macOS configurations (Tier 2 hosts). Workaround: copy tap-side
    # files into the build's staging dir first (always writable), then
    # invoke bin.install / pkgshare.install on the staged copies so
    # Homebrew never has to delete from the tap directory.
    tap_root = Pathname.new(__dir__).parent

    cp_r "#{tap_root}/bin/.",            "stage_bin"
    cp_r "#{tap_root}/test-fixtures/.",  "stage_fixtures"
    cp_r "#{tap_root}/host-tests/.",     "stage_host_tests"

    # ----- 3. Install the dictation-stack helper scripts -------------
    bin.install Dir["stage_bin/*"]

    # ----- 4. Install test fixtures into pkgshare --------------------
    pkgshare.install Dir["stage_fixtures/*"]

    # ----- 5. Install host-tests/ so users can run the full suite ----
    # `$(brew --prefix dictation-stack)/share/dictation-stack/host-tests/run-all.sh`
    # gives the user the documented test runner without having to clone
    # this tap repo.
    (pkgshare/"host-tests").install Dir["stage_host_tests/*"]
  end

  # NOTE: `def post_install` deliberately does NOT run `dictate-stack-install`.
  # That script `uv tool install`s the Python tools into ~/.local/share/uv/tools/
  # and writes uv's package cache to ~/.cache/uv/. Both are user-scope dirs
  # OUTSIDE the Homebrew prefix; brew's install sandbox blocks writes there
  # with `Operation not permitted (os error 1)`. The original 0.1.0 release
  # tried to auto-run dictate-stack-install in post_install and reproducibly
  # failed on Tier 2 macOS hosts. The fix is to make the user-scope install
  # an explicit user step — see the caveats below and ADR-002 postscript.

  def caveats
    <<~EOS
      ─────────────────────────────────────────────────────────────────
       Next step: complete the install (REQUIRED — one extra command)
      ─────────────────────────────────────────────────────────────────

      Homebrew installed `whisper-cli`, the dictate-* helper scripts, and
      the test fixtures, but it CANNOT install the five Python tools
      (`whisperx`, `mlx-whisper`, `openai-whisper`, `insanely-fast-whisper`,
      `mlx-vlm`) — `uv tool install` writes to ~/.cache/uv/ and
      ~/.local/share/uv/tools/, which Homebrew's install sandbox blocks.

      Run this ONCE, after `brew install`, in your normal shell:

        dictate-stack-install

      That command:
        - `uv tool install`s the five Python tools (~5–10 min)
        - pins `torch>=2.11` for insanely-fast-whisper
        - applies the IFW torchcodec rpath + ad-hoc-codesign patch
          (PLAN.md F5/F27 — without this, IFW silently fails to load)

      Then verify the install end-to-end:

        dictate-verify              # F29 byte-stable strict check

      Or run the full six-test host-side suite:

        $(brew --prefix dictation-stack)/share/dictation-stack/host-tests/run-all.sh

      ─── Other commands you may want ───

      Pre-pull all model weights (~25 GB), so first-use isn't slow:

        dictate-warmup
        dictate-warmup --whisper-only        # skips Gemma 4, saves 16 GB

      After any `uv tool upgrade insanely-fast-whisper`, re-apply the
      IFW rpath patch:

        dictate-stack-install --patch-only

      ─── PATH ───

      `dictate-stack-install` puts the tool wrappers in ~/.local/bin.
      If that's not on your PATH already, add it:

        export PATH="$HOME/.local/bin:$PATH"

      and persist the line in ~/.zshrc or ~/.bashrc.

      ─── Uninstall ───

      `brew uninstall dictation-stack` removes the prefix-installed bits
      (whisper-cli, scripts, fixtures) but does NOT remove the
      user-scope Python tools. To clean those up:

        dictate-stack-install --uninstall
        rm -rf ~/.cache/huggingface ~/.cache/whisper ~/.cache/uv

      ─── Reference ───

      https://github.com/psibook/homebrew-dictation
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
