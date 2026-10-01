# Homebrew tap payload

`Casks/matrix-screen-saver.rb` is ready to copy to a user-selected tap as
`Casks/matrix-screen-saver.rb`. No public tap is configured or live yet.

The payload uses Homebrew's native `screen_saver` artifact, not the local installer.
It retains the `dev.patsch.MatrixScreenSaver` preferences domain and has no zap
or preference-cleanup hook. Its published binary requires Apple Silicon (ARM64)
and macOS 15 (Sequoia) or newer.

Homebrew 7.0.7 ordinary mode supports the deprecated preflight/postflight blocks.
Developer mode rejects them. The narrow `Cask/InstallSteps` style exception is
intentional: initial-install-only settings launch needs the prior receipt snapshot.
Do not disable other audit checks or claim universal future Homebrew support.
