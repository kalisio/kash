# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

  - support for mongo 8 (`install_mongo8`)
  - added `get_flavor_from_git_ref` `get_version_from_git_ref` `get_custom_from_git_ref` helpers to parse git ref names (tag or branch names).
  - added `install_sona_scanner_cli` to install SonarQube scanner cli tool

### Removed

  - support for mongo 4,5,6
  - helper to install k9s
  - support for node 16,18
  
### Changed

  - kubectl bumped to `1.28.13`
  - helm bumped to `3.14.4`
  - helmfile bumped to `0.167.1`
  - `build_docs` now takes a fourth parameter, the version of node to use to build the docs
  - `send_coverage_to_cc` now takes a second parameter, the prefix to add to files in coverage report
  - `run_kli` now uses the `--fail-on-error` kli flag
  - nvm bumped to `0.40.3`
  - node20 bumped to `20.19`
  - node22 bumped to `22.16`
  - mongodb7 bumped to `7.0.21`
  - mongodb8 bumped to `8.0.10`

### Fixed

  - do our best to determine `OS_VERSION` when `VERSION_ID` is not in /etc/os-release
  - `run_app_tests` now correctly upload code coverage if asked to
