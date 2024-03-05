#!/usr/bin/env bash
set -euo pipefail
set -x

THIS_FILE=$(readlink -f "${BASH_SOURCE[0]}")
THIS_DIR=$(dirname "$THIS_FILE")
ROOT_DIR=$(dirname "$THIS_DIR")

. "$ROOT_DIR/kash.sh"

### Github Actions

init_github() {
    install_reqs yq age sops nvm node16 node18 node20 mongo4 mongo5 mongo6
}

if [ "$CI" = true ]; then
    begin_group "Init $CI_ID"

    init_"${CI_ID}"

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

echo "Commiter is $(get_git_committer_infos "$ROOT_DIR" )"

git clone --depth 1 https://github.com/kalisio/feathers-s3.git "$TMP_DIR/feathers-s3.master"
git clone --depth 1 --branch v1.3.0 https://github.com/kalisio/feathers-s3.git "$TMP_DIR/feathers-s3.v1.3.0"

[ "$(get_git_branch "$TMP_DIR/feathers-s3.master" )" != "master" ] && exit 1
[ "$(get_git_branch "$TMP_DIR/feathers-s3.v1.3.0" )" != "" ] && exit 1

[ "$(get_git_tag "$TMP_DIR/feathers-s3.master" )" != "" ] && exit 1
[ "$(get_git_tag "$TMP_DIR/feathers-s3.v1.3.0" )" != "v1.3.0" ] && exit 1

[ "$(get_git_commit_sha "$TMP_DIR/feathers-s3.v1.3.0" )" != "e28f53c386a2f74de7bdee7231b97e7150177cc7" ] && exit 1

git clone --depth 1 https://github.com/kalisio/kApp.git "$TMP_DIR/kApp.master"
git clone --depth 1 --branch test-v1.0 https://github.com/kalisio/kApp.git "$TMP_DIR/kApp.v1.0"

[ "$(get_git_branch "$TMP_DIR/kApp.master" )" != "master" ] && exit 1
[ "$(get_git_branch "$TMP_DIR/kApp.v1.0" )" != "test-v1.0" ] && exit 1

[ "$(get_git_tag "$TMP_DIR/kApp.master" )" != "" ] && exit 1
[ "$(get_git_tag "$TMP_DIR/kApp.v1.0" )" != "" ] && exit 1

init_app_infos "$TMP_DIR/kApp.master" "$TMP_DIR/kli"

[ "$(get_app_name)" != "kapp" ] && exit 1
# [ "$(get_app_version)" != "kapp" ] && exit 1
[ "$(get_app_flavor)" != "dev" ] && exit 1

init_app_infos "$TMP_DIR/kApp.v1.0" "$TMP_DIR/kli"

[ "$(get_app_name)" != "kapp" ] && exit 1
[ "$(get_app_version)" != "1.0.0" ] && exit 1
[ "$(get_app_flavor)" != "test" ] && exit 1

exit 0
