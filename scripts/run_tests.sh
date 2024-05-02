#!/usr/bin/env bash
set -euo pipefail
set -x

THIS_FILE=$(readlink -f "${BASH_SOURCE[0]}")
THIS_DIR=$(dirname "$THIS_FILE")
ROOT_DIR=$(dirname "$THIS_DIR")

. "$ROOT_DIR/kash.sh"

### Github Actions

init_github() {
    install_reqs yq age sops nvm node16 node18 node20 mongo4 mongo5 mongo6 mongo7 cc_test_reporter
}

if [ "$CI" = true ]; then
    begin_group "Init $CI_ID"

    # Make sure installing stuff doesnt mess with cwd
    CURRENT_DIR=$(pwd)
    init_"${CI_ID}"
    [ "$CURRENT_DIR" != "$(pwd)" ] && exit 1

    end_group "Init $CI_ID"
fi

case "$CI_ID" in
    github)
        [ "$(get_git_branch "$ROOT_DIR" )" != "$GITHUB_REF_NAME" ] && exit 1
        ;;
    gitlab)
        [ "$(get_git_branch "$ROOT_DIR" )" != "$CI_COMMIT_REF_NAME" ] && exit 1
        ;;
    *)
        ;;
esac

echo "Committer is $(get_git_commit_author_name "$ROOT_DIR") <$(get_git_commit_author_email "$ROOT_DIR")>"
echo "Commit message is $(get_git_commit_message "$ROOT_DIR")"

git_shallow_clone https://github.com/kalisio/feathers-s3.git "$TMP_DIR/feathers-s3.master"
git_shallow_clone https://github.com/kalisio/feathers-s3.git "$TMP_DIR/feathers-s3.v1.3.0" v1.3.0

[ "$(get_git_branch "$TMP_DIR/feathers-s3.master" )" != "master" ] && exit 1
[ "$(get_git_branch "$TMP_DIR/feathers-s3.v1.3.0" )" != "" ] && exit 1

[ "$(get_git_tag "$TMP_DIR/feathers-s3.master" )" != "" ] && exit 1
[ "$(get_git_tag "$TMP_DIR/feathers-s3.v1.3.0" )" != "v1.3.0" ] && exit 1

[ "$(get_git_commit_sha "$TMP_DIR/feathers-s3.v1.3.0" )" != "e28f53c386a2f74de7bdee7231b97e7150177cc7" ] && exit 1

git_shallow_clone https://github.com/kalisio/kApp.git "$TMP_DIR/kApp.master"
git_shallow_clone https://github.com/kalisio/kApp.git "$TMP_DIR/kApp.v1.3" test-v1.3
git_shallow_clone https://github.com/kalisio/kApp.git "$TMP_DIR/kApp.v1.3.0" prod-v1.3.0

[ "$(get_git_branch "$TMP_DIR/kApp.master" )" != "master" ] && exit 1
[ "$(get_git_branch "$TMP_DIR/kApp.v1.3" )" != "test-v1.3" ] && exit 1

[ "$(get_git_tag "$TMP_DIR/kApp.master" )" != "" ] && exit 1
[ "$(get_git_tag "$TMP_DIR/kApp.v1.3" )" != "" ] && exit 1
[ "$(get_git_tag "$TMP_DIR/kApp.v1.3.0" )" != "prod-v1.3.0" ] && exit 1

# Setup a fake workspace with additional dependencies
mkdir -p "$TMP_DIR/fake"
setup_workspace "$TMP_DIR/fake" "https://github.com/kalisio/kApp.git" \
    "https://github.com/kalisio/feathers-s3.git" \
    "https://github.com/kalisio/feathers-import-export.git"

# And check everything expected is in there
[ ! -d "$TMP_DIR/fake/development" ] && exit 1
[ ! -d "$TMP_DIR/fake/feathers-s3" ] && exit 1
[ ! -d "$TMP_DIR/fake/feathers-import-export" ] && exit 1

## App helpers

init_app_infos "$TMP_DIR/kApp.master" "$TMP_DIR/kli"

[ "$(get_app_name)" != "kapp" ] && exit 1
# [ "$(get_app_version)" != "kapp" ] && exit 1
[ "$(get_app_flavor)" != "dev" ] && exit 1

init_app_infos "$TMP_DIR/kApp.v1.3" "$TMP_DIR/kli"

[ "$(get_app_name)" != "kapp" ] && exit 1
[ "$(get_app_version)" != "1.3.0" ] && exit 1
[ "$(get_app_flavor)" != "test" ] && exit 1

init_app_infos "$TMP_DIR/kApp.v1.3.0" "$TMP_DIR/kli"

[ "$(get_app_name)" != "kapp" ] && exit 1
[ "$(get_app_version)" != "1.3.0" ] && exit 1
[ "$(get_app_flavor)" != "prod" ] && exit 1

## Lib helpers

# git clone --depth 1 https://github.com/kalisio/feathers-s3.git "$TMP_DIR/feathers-s3.master"

init_lib_infos "$TMP_DIR/feathers-s3.master"

[ "$(get_lib_name)" != "@kalisio/feathers-s3" ] && exit 1

## Job helpers

git_shallow_clone https://github.com/kalisio/k-icos.git "$TMP_DIR/k-icos.master"

init_job_infos "$TMP_DIR/k-icos.master"

[ "$(get_job_name)" != "k-icos" ] && exit 1

exit 0
