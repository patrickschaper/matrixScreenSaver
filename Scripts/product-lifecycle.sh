#!/bin/bash
# Installs/removes the pair and restores a missing saver from its app's recovery payload.
# The installed copy survives Finder removal of the app; install-saver APP never quits it.
set -euo pipefail
umask 077

LABEL=dev.patsch.MatrixWallpaper.cleanup
SUPPORT="$HOME/Library/Application Support/MatrixWallpaper"
STATE="$SUPPORT/Installation"
RECORD="$STATE/installation.plist"
AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"
LOCK="$SUPPORT/.installation-lock"
DOMAIN="gui/$(id -u)"
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
APP_ID=dev.patsch.MatrixWallpaper
SAVER_ID=dev.patsch.MatrixScreenSaver
LOCKED=0
ACTION="${1:-}"

fail() { echo "Matrix installation: $*" >&2; exit 1; }
value() { /usr/libexec/PlistBuddy -c "Print :$2" "$1"; }

# Reject redirects before any destructive operation, including symlinked ancestors.
safe_path() {
  local path="$1" part
  [[ "$path" == /* && "$path" != / && "$path" != *$'\n'* ]] || fail "Unsafe path: $path"
  case "$path/" in *'/../'*|*'/./'*|*'//'*) fail "Non-canonical path: $path";; esac
  part="$path"
  while [[ "$part" != / ]]; do
    [[ ! -L "$part" ]] || fail "Refusing symlink: $part"
    part="$(dirname "$part")"
  done
}

verify_bundle() {
  local bundle="$1" identifier="$2" executable="$3"
  safe_path "$bundle"
  [[ -d "$bundle" && -x "$bundle/Contents/MacOS/$executable" ]] &&
    [[ "$(value "$bundle/Contents/Info.plist" CFBundleIdentifier)" == "$identifier" ]] &&
    codesign --verify --deep --strict "$bundle"
}

validate_pair() {
  verify_bundle "$1" "$APP_ID" MatrixWallpaper || fail "Invalid wallpaper bundle: $1"
  verify_bundle "$2" "$SAVER_ID" MatrixScreenSaver || fail "Invalid screen saver bundle: $2"
  local key first second
  for key in CFBundleShortVersionString CFBundleVersion; do
    first="$(value "$1/Contents/Info.plist" "$key")"
    second="$(value "$2/Contents/Info.plist" "$key")"
    [[ -n "$first" && "$first" == "$second" ]] || fail "Both bundles must have matching $key values."
  done
}

unlock() {
  if [[ "$LOCKED" == 1 ]]; then rm -f "$LOCK"; LOCKED=0; fi
}

# Serialized Homebrew hooks may borrow the lock held by their common parent process.
is_ancestor() {
  local target="$1" pid="$PPID"
  while [[ "$pid" =~ ^[0-9]+$ && "$pid" -gt 1 ]]; do
    [[ "$pid" != "$target" ]] || return 0
    pid="$(/bin/ps -p "$pid" -o ppid= | tr -d ' ')"
  done
  return 1
}

lock() {
  safe_path "$SUPPORT"
  safe_path "$STATE"
  safe_path "$RECORD"
  safe_path "$AGENT"
  safe_path "$LOCK"
  mkdir -p "$SUPPORT"
  local pid
  # PID locks span Homebrew hooks that cannot share an open file descriptor.
  if ! /usr/bin/shlock -p "$$" -f "$LOCK"; then
    pid="$(cat "$LOCK")"
    [[ "$pid" =~ ^[0-9]+$ ]] || fail "Invalid installation lock."
    if kill -0 "$pid" 2>/dev/null; then
      case "$ACTION" in
        register|unregister|suspend) if is_ancestor "$pid"; then return; fi ;;
      esac
      fail "Installation is busy."
    fi
    fail "Installation is busy; retry after the other operation finishes."
  fi
  LOCKED=1
  trap unlock EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
}

read_record() {
  safe_path "$RECORD"
  APP="$(value "$RECORD" app)"
  SAVER="$(value "$RECORD" saver)"
  OWNER="$(value "$RECORD" owner)"
  safe_path "$APP"
  safe_path "$SAVER"
  [[ "$(basename "$APP")" == 'Matrix Wallpaper.app' && "$(basename "$SAVER")" == MatrixScreenSaver.saver ]] || fail "Invalid installation destinations."
  [[ "$OWNER" == local || "$OWNER" == homebrew ]] || fail "Invalid installation owner."
}

# Retains the recorded owner and destinations; reports the conflicting installation on mismatch.
check_destinations() {
  local app="$1" saver="$2" owner="$3"
  safe_path "$app"; safe_path "$saver"
  [[ "$(basename "$app")" == 'Matrix Wallpaper.app' && "$(basename "$saver")" == MatrixScreenSaver.saver ]] || fail "Invalid installation destinations."
  if [[ -e "$RECORD" ]]; then
    read_record
    [[ "$APP" == "$app" && "$SAVER" == "$saver" && "$OWNER" == "$owner" ]] ||
      fail "Uninstall the existing managed installation first. Owner: $OWNER; app: $APP; screen saver: $SAVER."
  fi
  APP="$app"; SAVER="$saver"; OWNER="$owner"
}

unload() {
  if launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1; then
    launchctl bootout "$DOMAIN/$LABEL"
  fi
}

# Writes the owned installation and cleanup agent using XML-safe paths.
# Pass homebrew to defer launchctl until app launch or login; cask hooks are sandboxed.
register() {
  mkdir -p "$STATE" "$(dirname "$AGENT")"
  local record="$STATE/installation.new.plist" agent="$STATE/agent.new.plist"
  for path in "$record" "$agent" "$STATE/product-lifecycle.sh" "$STATE/cleanup.log" "$STATE/missing-since"; do safe_path "$path"; done
  /usr/bin/plutil -create xml1 "$record"
  /usr/bin/plutil -insert app -string "$APP" "$record"
  /usr/bin/plutil -insert saver -string "$SAVER" "$record"
  /usr/bin/plutil -insert owner -string "$OWNER" "$record"
  /usr/bin/plutil -create xml1 "$agent"
  /usr/bin/plutil -insert Label -string "$LABEL" "$agent"
  /usr/bin/plutil -insert ProgramArguments -array "$agent"
  /usr/bin/plutil -insert ProgramArguments.0 -string /bin/bash "$agent"
  /usr/bin/plutil -insert ProgramArguments.1 -string "$STATE/product-lifecycle.sh" "$agent"
  /usr/bin/plutil -insert ProgramArguments.2 -string check "$agent"
  /usr/bin/plutil -insert RunAtLoad -bool YES "$agent"
  /usr/bin/plutil -insert StartInterval -integer 60 "$agent"
  /usr/bin/plutil -insert StandardErrorPath -string "$STATE/cleanup.log" "$agent"
  if [[ "${1:-}" != homebrew ]]; then unload; fi
  if [[ "$SELF" != "$STATE/product-lifecycle.sh" ]]; then cp "$SELF" "$STATE/product-lifecycle.sh"; fi
  chmod 700 "$STATE/product-lifecycle.sh"
  mv "$record" "$RECORD"
  mv "$agent" "$AGENT"
  rm -f "$STATE/missing-since"
  if [[ "${1:-}" != homebrew ]]; then launchctl bootstrap "$DOMAIN" "$AGENT"; fi
}

unregister() {
  # The running check unloads itself only after all filesystem work has completed.
  rm -f "$AGENT" "$RECORD" "$STATE/missing-since" "$STATE/product-lifecycle.sh" "$STATE/cleanup.log"
  rmdir "$STATE" 2>/dev/null || true
}

quit_wallpaper() {
  osascript -l JavaScript <<'JXA'
ObjC.import('AppKit');
const apps = $.NSRunningApplication.runningApplicationsWithBundleIdentifier('dev.patsch.MatrixWallpaper');
for (let i = 0; i < apps.count; i++) {
    if (!apps.objectAtIndex(i).terminate) throw new Error('Matrix Wallpaper refused to quit.');
}
const deadline = Date.now() + 5000;
for (let i = 0; i < apps.count; i++) {
    while (!apps.objectAtIndex(i).terminated) {
        if (Date.now() >= deadline) throw new Error('Matrix Wallpaper did not quit within five seconds.');
        $.NSRunLoop.currentRunLoop.runUntilDate($.NSDate.dateWithTimeIntervalSinceNow(0.1));
    }
}
JXA
}

stop_saver() {
  # Never signal another user's screen saver host.
  local name
  for name in ScreenSaverEngine legacyScreenSaver legacyScreenSaver-x86_64; do
    pkill -u "$(id -u)" -x "$name" 2>/dev/null || true
  done
}

install_pair() {
  local source_app="$1" source_saver="$2"
  source_app="$(cd "$(dirname "$source_app")" && pwd -P)/$(basename "$source_app")"
  source_saver="$(cd "$(dirname "$source_saver")" && pwd -P)/$(basename "$source_saver")"
  validate_pair "$source_app" "$source_saver"
  lock
  check_destinations "$HOME/Applications/Matrix Wallpaper.app" "$HOME/Library/Screen Savers/MatrixScreenSaver.saver" local
  local legacy="$(dirname "$APP")/MatrixWallpaper.app" stage saver_stage committed=0 app_promoted=0 saver_promoted=0 backup_ready=0 registration_changed=0
  for bundle in "$APP" "$SAVER"; do
    if [[ -e "$bundle" ]]; then
      if [[ "$bundle" == "$APP" ]]; then verify_bundle "$bundle" "$APP_ID" MatrixWallpaper;
      else verify_bundle "$bundle" "$SAVER_ID" MatrixScreenSaver; fi || fail "Refusing to replace unrecognized bundle: $bundle"
    fi
  done
  quit_wallpaper || fail "Quit Matrix Wallpaper and try again."
  mkdir -p "$(dirname "$APP")" "$(dirname "$SAVER")"
  stage="$(mktemp -d "$(dirname "$APP")/.MatrixWallpaper-install.XXXXXX")"
  saver_stage="$(mktemp -d "$(dirname "$SAVER")/.MatrixSaver-install.XXXXXX")"
  rollback() {
    local result=$? restored=1
    trap - EXIT
    if [[ "$committed" == 0 && "$backup_ready" == 1 ]]; then
      [[ "$app_promoted" == 0 ]] || rm -rf "$APP" || restored=0
      [[ "$saver_promoted" == 0 ]] || rm -rf "$SAVER" || restored=0
      # Never let mv nest a recovery bundle inside a destination we could not remove.
      if [[ -d "$stage/previous.app" ]]; then
        if [[ -e "$APP" || -L "$APP" ]] || ! mv "$stage/previous.app" "$APP"; then restored=0; fi
      fi
      if [[ -d "$stage/legacy.app" ]]; then
        if [[ -e "$legacy" || -L "$legacy" ]] || ! mv "$stage/legacy.app" "$legacy"; then restored=0; fi
      fi
      if [[ -d "$saver_stage/previous.saver" ]]; then
        if [[ -e "$SAVER" || -L "$SAVER" ]] || ! mv "$saver_stage/previous.saver" "$SAVER"; then restored=0; fi
      fi
      if [[ "$registration_changed" == 1 ]]; then
        unload || restored=0
        rm -rf "$STATE"
        rm -f "$AGENT"
        if [[ -d "$stage/registration" ]]; then cp -R "$stage/registration" "$STATE" || restored=0; fi
        if [[ -f "$stage/agent.plist" ]]; then
          cp "$stage/agent.plist" "$AGENT" && launchctl bootstrap "$DOMAIN" "$AGENT" || restored=0
        fi
      fi
    fi
    if [[ "$restored" == 1 ]]; then rm -rf "$stage" "$saver_stage";
    else echo "Restore failed; backups preserved at $stage and $saver_stage" >&2; result=1; fi
    unlock
    exit "$result"
  }
  trap rollback EXIT
  [[ ! -d "$STATE" ]] || cp -R "$STATE" "$stage/registration"
  [[ ! -f "$AGENT" ]] || cp "$AGENT" "$stage/agent.plist"
  backup_ready=1
  ditto "$source_app" "$stage/Matrix Wallpaper.app"
  ditto "$source_saver" "$saver_stage/MatrixScreenSaver.saver"
  validate_pair "$stage/Matrix Wallpaper.app" "$saver_stage/MatrixScreenSaver.saver"
  cmp "$source_app/Contents/MacOS/MatrixWallpaper" "$stage/Matrix Wallpaper.app/Contents/MacOS/MatrixWallpaper"
  cmp "$source_saver/Contents/MacOS/MatrixScreenSaver" "$saver_stage/MatrixScreenSaver.saver/Contents/MacOS/MatrixScreenSaver"
  [[ ! -d "$APP" ]] || mv "$APP" "$stage/previous.app"
  [[ ! -d "$SAVER" ]] || mv "$SAVER" "$saver_stage/previous.saver"
  if [[ ! -L "$legacy" && -d "$legacy" ]] && verify_bundle "$legacy" "$APP_ID" MatrixWallpaper >/dev/null 2>&1; then
    mv "$legacy" "$stage/legacy.app"
  fi
  mv "$stage/Matrix Wallpaper.app" "$APP"; app_promoted=1
  mv "$saver_stage/MatrixScreenSaver.saver" "$SAVER"; saver_promoted=1
  registration_changed=1
  register
  committed=1
  stop_saver
  echo "Installed Matrix Wallpaper and MatrixScreenSaver. Open $APP to start the wallpaper."
  exit 0
}

# Restores a missing or incomplete saver, preserving an existing owner's destination and registration.
# Takes the running app bundle path. Its sealed archive/helper are the only accepted payloads.
# Failures roll back this operation's changes; incomplete rollback retains staging for recovery.
install_saver() {
  local source_app="$1" archive helper stage committed=0 promoted=0 registration_changed=0 identity=""
  local marker marker_identity="" marker_owned=0 retry=0
  source_app="$(cd "$(dirname "$source_app")" && pwd -P)/$(basename "$source_app")"
  verify_bundle "$source_app" "$APP_ID" MatrixWallpaper || fail "Invalid wallpaper bundle: $source_app"
  lock
  if [[ -e "$RECORD" ]]; then
    read_record
    [[ "$APP" == "$source_app" ]] || fail "Open the installed Matrix Wallpaper app and try again."
  else
    check_destinations "$source_app" "$HOME/Library/Screen Savers/MatrixScreenSaver.saver" local
  fi
  marker="$SAVER.installing"
  safe_path "$marker"
  if [[ -e "$marker" ]]; then
    [[ -f "$marker" ]] || fail "Invalid screen saver recovery marker: $marker"
    marker_identity="$(cat "$marker")"
    [[ "$marker_identity" =~ ^[0-9]+:[0-9]+$ ]] && printf '%s' "$marker_identity" | cmp -s - "$marker" ||
      fail "Invalid screen saver recovery marker: $marker"
    if [[ -d "$SAVER" && ! -L "$SAVER" && "$(stat -f '%d:%i' "$SAVER")" == "$marker_identity" ]]; then
      retry=1
      identity="$marker_identity"
      marker_owned=1
    fi
  fi
  if [[ ( -e "$SAVER" || -L "$SAVER" ) && "$retry" == 0 ]]; then
    verify_bundle "$SAVER" "$SAVER_ID" MatrixScreenSaver || fail "The screen saver destination is occupied. Move the conflicting item and try again."
    echo "MatrixScreenSaver is already installed."
    return
  fi
  if [[ "$retry" == 0 ]]; then
    archive="$source_app/Contents/Resources/ScreenSaver/MatrixScreenSaver.zip"
    helper="$source_app/Contents/MacOS/MatrixScreenSaverInstaller"
    safe_path "$archive"; safe_path "$helper"
    [[ -f "$archive" && -x "$helper" ]] || fail "The recovery payload is missing. Reinstall Matrix Wallpaper."
    "$helper" validate-archive "$archive"
  fi
  mkdir -p "$(dirname "$SAVER")" || fail "Cannot write to the screen saver folder. Check its permissions and try again."
  stage="$(mktemp -d "$(dirname "$SAVER")/.MatrixSaver-install.XXXXXX")"

  # Removes only our promoted inode; a replacement created by another installer is never deleted.
  restore_saver_rollback() {
    local result=$? restored=1
    trap - EXIT
    if [[ "$committed" == 0 ]]; then
      if [[ "$promoted" == 1 ]]; then
        if [[ ! -L "$SAVER" && -d "$SAVER" && "$(stat -f '%d:%i' "$SAVER")" == "$identity" ]]; then
          rm -rf "$SAVER" || restored=0
        else
          restored=0
        fi
      fi
      if [[ "$registration_changed" == 1 ]]; then
        unload || restored=0
        rm -rf "$STATE" || restored=0
        rm -f "$AGENT" || restored=0
        if [[ -d "$stage/registration" ]]; then cp -R "$stage/registration" "$STATE" || restored=0; fi
        if [[ -f "$stage/agent.plist" ]]; then
          cp "$stage/agent.plist" "$AGENT" && launchctl bootstrap "$DOMAIN" "$AGENT" || restored=0
        fi
      fi
      # Retain the receipt when registration rollback fails, even if our bundle was removed.
      if [[ "$restored" == 1 && "$marker_owned" == 1 ]] &&
         [[ ! -d "$SAVER" || -L "$SAVER" || "$(stat -f '%d:%i' "$SAVER")" != "$identity" ]]; then
        rm -f "$marker" || restored=0
      fi
    fi
    if [[ "$restored" == 1 ]] && ! rm -rf "$stage"; then restored=0; fi
    if [[ "$restored" != 1 ]]; then
      echo "Restore failed; recovery files preserved at $stage" >&2
      result=1
    fi
    unlock
    exit "$result"
  }
  trap restore_saver_rollback EXIT
  if [[ "$retry" == 0 ]]; then
    ditto -x -k "$archive" "$stage"
    validate_pair "$source_app" "$stage/MatrixScreenSaver.saver"
    identity="$(stat -f '%d:%i' "$stage/MatrixScreenSaver.saver")"
    # A validated stale marker with no matching target cannot block a new recovery attempt.
    rm -f "$marker"
    (set -C; printf '%s' "$identity" > "$marker") || fail "Cannot create the screen saver recovery marker."
    marker_owned=1
    "$helper" promote "$stage/MatrixScreenSaver.saver" "$SAVER"
  fi
  promoted=1
  validate_pair "$source_app" "$SAVER"
  if [[ -n "$marker_identity" || ! -e "$RECORD" || ! -f "$AGENT" ]] || ! launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1; then
    [[ ! -d "$STATE" ]] || cp -R "$STATE" "$stage/registration"
    [[ ! -f "$AGENT" ]] || cp "$AGENT" "$stage/agent.plist"
    registration_changed=1
    register
  fi
  rm -f "$marker" || fail "Cannot finish the screen saver recovery. Check folder permissions and retry."
  committed=1
  echo "Installed MatrixScreenSaver. Select it in System Settings to use it."
  exit 0
}

case "${1:-}" in
  validate) [[ $# == 3 ]] || fail "validate requires both bundles"; validate_pair "$2" "$3" ;;
  install) [[ $# == 3 ]] || fail "install requires both bundles"; install_pair "$2" "$3" ;;
  install-saver) [[ $# == 2 ]] || fail "install-saver requires the wallpaper app"; install_saver "$2" ;;
  activate)
    # Only the recorded app may activate deferred cleanup outside Homebrew's sandbox.
    [[ $# == 2 ]] || fail "activate requires the wallpaper app"
    lock
    [[ -f "$RECORD" ]] || exit 0
    read_record
    [[ "$APP" == "$2" ]] || exit 0
    verify_bundle "$APP" "$APP_ID" MatrixWallpaper || fail "Invalid wallpaper bundle: $APP"
    if ! launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1; then register; fi
    ;;
  register)
    [[ $# == 4 ]] || fail "register requires app, saver, and owner"
    validate_pair "$2" "$3"
    lock
    check_destinations "$2" "$3" "$4"
    register "$OWNER"
    # Native artifacts and cleanup registration are now committed together.
    LOCKED=1
    unlock
    ;;
  suspend)
    # Hold the shared lock across Homebrew's separate native-artifact operations.
    lock
    [[ $# == 4 ]] || fail "suspend requires installation destinations and owner"
    check_destinations "$2" "$3" "$4"
    pid="$PPID"; brew_pid=""
    while [[ "$pid" =~ ^[0-9]+$ && "$pid" -gt 1 ]]; do
      command="$(/bin/ps -p "$pid" -o command=)"
      case "$command" in *Homebrew*|*/brew*) brew_pid="$pid";; esac
      pid="$(/bin/ps -p "$pid" -o ppid= | tr -d ' ')"
    done
    [[ -n "$brew_pid" ]] || fail "Cannot identify the Homebrew transaction."
    safe_path "$LOCK.next"
    echo "$brew_pid" > "$LOCK.next"
    mv "$LOCK.next" "$LOCK"
    LOCKED=0
    ;;
  unregister)
    [[ $# == 1 || ( $# == 2 && "$2" == homebrew ) ]] || fail "unregister accepts only homebrew"
    lock
    # Homebrew's native launchctl uninstall directive owns service removal.
    if [[ "${2:-}" != homebrew ]]; then unload; fi
    unregister
    ;;
  check)
    lock
    [[ -f "$RECORD" ]] || exit 0
    read_record
    if [[ -e "$APP" ]]; then rm -f "$STATE/missing-since"; exit 0; fi
    now="$(date +%s)"
    safe_path "$STATE/missing-since"
    if [[ ! -f "$STATE/missing-since" ]]; then echo "$now" > "$STATE/missing-since"; exit 0; fi
    since="$(cat "$STATE/missing-since")"
    [[ "$since" =~ ^[0-9]+$ ]] || fail "Invalid removal timestamp."
    (( now >= since && now - since >= 300 )) || exit 0
    [[ ! -e "$APP" ]] || exit 0
    if [[ -e "$SAVER" ]]; then
      verify_bundle "$SAVER" "$SAVER_ID" MatrixScreenSaver || fail "Refusing to remove unrecognized saver."
    fi
    quit_wallpaper || fail "Quit Matrix Wallpaper to finish automatic removal."
    stop_saver
    rm -rf "$SAVER"
    unregister
    unlock
    unload
    ;;
  uninstall)
    lock
    [[ -f "$RECORD" ]] || fail "No managed installation found."
    read_record
    [[ "$OWNER" == local ]] || fail "Use brew uninstall --cask matrix-screen-saver for this installation."
    if [[ -e "$APP" ]]; then
      verify_bundle "$APP" "$APP_ID" MatrixWallpaper || fail "Refusing to remove unrecognized app."
      quit_wallpaper
      "$APP/Contents/MacOS/MatrixWallpaper" --unregister-login-item
    fi
    if [[ -e "$SAVER" ]]; then verify_bundle "$SAVER" "$SAVER_ID" MatrixScreenSaver || fail "Refusing to remove unrecognized saver."; fi
    unload
    stop_saver
    rm -rf "$APP" "$SAVER"
    unregister
    ;;
  *) fail "Usage: $0 {install|validate} APP SAVER | {install-saver|activate} APP | register APP SAVER OWNER | suspend | unregister [homebrew] | check | uninstall" ;;
esac
