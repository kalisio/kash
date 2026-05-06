# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
  - added `publish_charts_s3` to publish several charts from a folder to s3
  - added `publish_charts_oci` to publish several charts from a folder to harbor
  - added `package_chart` to package chart Helm ( update, lint and package)
  - added `git_tag_exists` to know if a tag already exit or no
  - added `get_yaml_value` to extract values from YAML files
  - added `install_rclone` to install rclone 
  - added `get_toml_value` to extract values from TOML fields
  - support for mongo 8 (`install_mongo8`)
  - added `get_flavor_from_git_ref` `get_version_from_git_ref` `get_custom_from_git_ref` helpers to parse git ref names (tag or branch names).
  - added `install_sona_scanner_cli` to install SonarQube scanner cli tool
  - added `build_krawler_job` to adapt to monorepo

### Removed

  - support for mongo 4,5,6
  - helper to install k9s
  - support for node 16,18
  - support for Code Climate
  
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
  - allow `_` character in custom fields (see `get_custom_from_git_ref`)
  - run_app_tests now run lint on whole project repo (using `yarn lint`)

### Fixed

  - do our best to determine `OS_VERSION` when `VERSION_ID` is not in /etc/os-release
  - `run_app_tests` now correctly upload code coverage if asked to
