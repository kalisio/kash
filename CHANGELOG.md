# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

  - kubectl bumped to `1.28.13`
  - helm bumped to `3.14.4`
  - helmfile bumped to `0.167.1`
  - `build_docs` now takes a fourth parameter, the version of node to use to build the docs

### Fixed

  - `run_app_tests` now correctly upload code coverage if asked to
