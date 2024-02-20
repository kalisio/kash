#!/usr/bin/env bash
set -euo pipefail
set -x

THIS_FILE=$(readlink -f "${BASH_SOURCE[0]}")
THIS_DIR=$(dirname "$THIS_FILE")
ROOT_DIR=$(dirname "$THIS_DIR")

. "$ROOT_DIR/kash.sh"

git clone --depth 1 https://github.com/kalisio/feathers-s3.git "$TMP_DIR/feathers-s3.master"
git clone --depth 1 --branch v1.3.0 https://github.com/kalisio/feathers-s3.git "$TMP_DIR/feathers-s3.v1.3.0"

[ "$(get_git_branch "$TMP_DIR/feathers-s3.master" )" != "master" ] && exit 1
[ "$(get_git_branch "$TMP_DIR/feathers-s3.v1.3.0" )" != "" ] && exit 1

[ "$(get_git_tag "$TMP_DIR/feathers-s3.master" )" != "" ] && exit 1
[ "$(get_git_tag "$TMP_DIR/feathers-s3.v1.3.0" )" != "v1.3.0" ] && exit 1

exit 0
