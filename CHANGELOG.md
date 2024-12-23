# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

  - support for mongo 8 (`install_mongo8`)

### Removed

  - support for mongo 4,5,6
  
### Changed

  - kubectl bumped to `1.28.13`
  - helm bumped to `3.14.4`
  - helmfile bumped to `0.167.1`
  - `build_docs` now takes a fourth parameter, the version of node to use to build the docs
  - `send_coverage_to_cc` now takes a second parameter, the prefix to add to files in coverage report

### Fixed

  - do our best to determine `OS_VERSION` when `VERSION_ID` is not in /etc/os-release
  - `run_app_tests` now correctly upload code coverage if asked to
