# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).


## [0.0.11] - 2026-05-20

### Features

- replace character size fields with slider (#39)
- vertical scanlines with direction option (#38)
- add header and About link to options sheet (#31)
- CRT scanlines effect (#29)
- add editable Neo message lines option
- populate GitHub release notes from CHANGELOG.md
- add CHANGELOG and auto-update on release
- add custom character set option

### Bug Fixes

- restore CHANGELOG.md when reusing release branch
- avoid awk multiline var in release changelog step
- skip multi-screen sync delay in preview mode
- generate CHANGELOG from git log in release workflow (#35)
- right-align About link in options sheet header (#33)
- right-align About link in options sheet header (#32)
- sync number scene blackout and screen activation across displays
- set tag-prefix to empty string in changelog action
- address remaining and falsely-resolved Copilot review findings
- address Copilot review findings on custom character set
- shorten custom characters description to one-liner

## [0.0.9] - 2026-05-13

### Features

- Number scene redesign with Neo message, sync, and cursor polish (#23)
- Replace number scene fade-in with random character fill (#21)
- Add Neo message intro scene (#20)
- Add screen saver thumbnail images (#19)

## [0.0.8] - 2026-04-29

### Features

- Fade in number scene on start (#18)

### Bug Fixes

- Resolve animation freeze on external monitors

## [0.0.7] - 2026-04-25

### Bug Fixes

- Increase diffusion glow prominence slightly (#14)

## [0.0.6] - 2026-04-22

### Features

- Update character size defaults

## [0.0.5] - 2026-04-14

### Bug Fixes

- Minor fix

## [0.0.4] - 2026-04-10

### Features

- Bundle release installer

## [0.0.3] - 2026-04-07

### Bug Fixes

- Hide chrome in fullscreen saver (#5)

## [0.0.2] - 2026-04-04

### Features

- Add release workflow
- Improve saver options and renderer

### Bug Fixes

- Reuse release PR on reruns
