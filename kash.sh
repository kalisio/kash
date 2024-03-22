#!/usr/bin/env bash

### Variables provided by this script
###   - TMP_DIR: a path where to write temp files
###   - OS_ID: debian or ubuntu or alpine ...
###   - OS_VERSION:
###   - CI: true or false
###   - CI_ID: github or gitlab or travis or empty (CI = false)

### Docs for CI systems:
###  - github actions: https://docs.github.com/en/actions/learn-github-actions/variables#default-environment-variables
###  - gitlab ci: https://docs.gitlab.com/ee/ci/variables/predefined_variables.html
###  - travis ci: https://docs.travis-ci.com/user/environment-variables/#default-environment-variables

### Host detection
###

. /etc/os-release

OS_ID=$ID
OS_VERSION=$VERSION_ID

echo "Running on ${OS_ID}-${OS_VERSION}"

CI=false
CI_ID=

if [ "${GITHUB_ACTIONS:-}" = true ]; then
    CI_ID="github"

    # Add ~/.local/bin to PATH
    mkdir -p "$HOME/.local/bin"
    export PATH=$PATH:$HOME/.local/bin

    # Make sure package lists are up to date
    # sudo apt-get update

elif [ "${GITLAB_CI:-}" = true ]; then
    CI_ID="gitlab"

    # Add ~/.local/bin to PATH
    mkdir -p "$HOME/.local/bin"
    export PATH=$PATH:$HOME/.local/bin
elif [  "${TRAVIS:-}" = true ]; then
    CI_ID="travis"
fi

if [ -n "$CI_ID" ]; then
    CI=true
    echo "Running in CI mode ($CI_ID)..."

    # Make sure we have the requirements to run kash functions
    case "$OS_ID" in
        debian | ubuntu)
            sudo apt --no-install-recommends --yes install sudo curl coreutils git
            ;;
        *)
            ;;
    esac

    # Emulate development k-mongo when running on CI
    cat <<EOF > ~/.local/bin/k-mongo
#!/usr/bin/env bash
mongod --dbpath /var/lib/mongo --logpath /var/log/mongodb/mongod.log --fork --port 27017
EOF
    chmod a+x ~/.local/bin/k-mongo

    # Most CI services understand ANSI colors
    export TERM=xterm-color
fi

# If nvm is present, make it available to script
if [ -d "$HOME/.nvm" ]; then
    . "$HOME/.nvm/nvm.sh"
fi

# Define a TMP_DIR to operate with temp files
if [ -n "${RUNNER_TEMP:-}" ]; then # RUNNER_TEMP is Github Action specific
    TMP_DIR="$RUNNER_TEMP"
else
    TMP_DIR="$(mktemp -d -p "${XDG_RUNTIME_DIR:-}" kalisio.XXXXXX)"
fi

### Requirements
###

YQ_VERSION=4.40.5
AGE_VERSION=1.1.1
SOPS_VERSION=3.8.1

NVM_VERSION=0.39.7
NODE16_VERSION=16.20.2
NODE18_VERSION=18.19.1
NODE20_VERSION=20.11.1

MONGODB4_VERSION=4.4.28
MONGODB5_VERSION=5.0.24
MONGODB6_VERSION=6.0.13
MONGODB7_VERSION=7.0.5

# Install yq in ~/.local/bin
# Arg1: a writable folder where to write downloaded files
install_yq() {
    local DL_ROOT=$1
    local DL_PATH="$DL_ROOT/yq"
    if [ ! -d "$DL_PATH" ]; then
        mkdir -p "$DL_PATH" && cd "$DL_PATH"
        curl -OLsS https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_amd64.tar.gz
        # checksum has to be extracted from custom file ...
        curl -OLsS https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/checksums
        curl -OLsS https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/checksums_hashes_order
        curl -OLsS https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/extract-checksum.sh
        chmod u+x extract-checksum.sh
        ./extract-checksum.sh "SHA-256" "yq_linux_amd64.tar.gz" | awk '{ print $2 " " $1}' | sha256sum --check
    fi
    cd "$DL_PATH"
    tar xf yq_linux_amd64.tar.gz
    mv yq_linux_amd64 ~/.local/bin/yq
    chmod u+x ~/.local/bin/yq
    cd ~-
}

# Install age in ~/.local/bin
# Arg1: a writable folder where to write downloaded files
install_age() {
    local DL_ROOT=$1
    local DL_PATH="$DL_ROOT/age"
    if [ ! -d "$DL_PATH" ]; then
        mkdir -p "$DL_PATH" && cd "$DL_PATH"
        curl -OLsS https://github.com/FiloSottile/age/releases/download/v${AGE_VERSION}/age-v${AGE_VERSION}-linux-amd64.tar.gz
        # no checksum ...
    fi
    cd "$DL_PATH"
    tar xf age-v${AGE_VERSION}-linux-amd64.tar.gz
    cp age/age ~/.local/bin
    cp age/age-keygen ~/.local/bin
    cd ~-
}

# Install sops in ~/.local/bin
# Arg1: a writable folder where to write downloaded files
install_sops() {
    local DL_ROOT=$1
    local DL_PATH="$DL_ROOT/sops"
    if [ ! -d "$DL_PATH" ]; then
        mkdir -p "$DL_PATH" && cd "$DL_PATH"
        curl -OLsS https://github.com/getsops/sops/releases/download/v${SOPS_VERSION}/sops-v${SOPS_VERSION}.linux.amd64
        curl -OLsS https://github.com/getsops/sops/releases/download/v${SOPS_VERSION}/sops-v${SOPS_VERSION}.checksums.txt
        sha256sum --ignore-missing --quiet -c sops-v${SOPS_VERSION}.checksums.txt
    fi
    cd "$DL_PATH"
    cp sops-v${SOPS_VERSION}.linux.amd64 ~/.local/bin/sops
    chmod u+x ~/.local/bin/sops
    cd ~-
}

# Install code climate test reporter in ~/.local/bin
# Arg1: a writable folder where to write downloaded files
install_cc_test_reporter() {
    local DL_ROOT=$1
    local DL_PATH="$DL_ROOT/cc"
    mkdir -p "$DL_PATH" && cd "$DL_PATH"
    curl -OLsS https://codeclimate.com/downloads/test-reporter/test-reporter-latest-linux-amd64
    curl -OLsS https://codeclimate.com/downloads/test-reporter/test-reporter-latest-linux-amd64.sha256
    sha256sum --ignore-missing --quiet -c test-reporter-latest-linux-amd64.sha256
    cp test-reporter-latest-linux-amd64 ~/.local/bin/cc-test-reporter
    chmod +x ~/.local/bin/cc-test-reporter
    cd ~-
}

# Sends test coverage to code climate
# Arg1: code climate identifier for authentication
send_coverage_to_cc() {
    local CC_TEST_REPORTER_ID=$1
    ~/.local/bin/cc-test-reporter format-coverage -t lcov coverage/lcov.info
    ~/.local/bin/cc-test-reporter upload-coverage -r $CC_TEST_REPORTER_ID
}

# Make sure nvm is installed
# Arg1: a writable folder where to write downloaded files
# NOTE: also define 'yarn' as a default package, ie. it'll be automatically
# installed with each node version
install_nvm() {
    local DL_ROOT=$1
    local DL_PATH="$DL_ROOT/nvm"
    mkdir -p "$DL_PATH" && cd "$DL_PATH"
    curl -OLsS https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_VERSION}/install.sh
    bash ./install.sh
    # We always use yarn as package manager, so tell nvm to install it with every node installation
    # cf. https://github.com/nvm-sh/nvm?tab=readme-ov-file#default-global-packages-from-file-while-installing
    bash -i -c 'echo yarn >> $NVM_DIR/default-packages'
    cd ~-
}

# Install node16, requires nvm to be installed
install_node16() {
    bash -i -c "nvm install ${NODE16_VERSION}"
}

# Install node18, requires nvm to be installed
install_node18() {
    bash -i -c "nvm install ${NODE18_VERSION}"
}

# Install node20, requires nvm to be installed
install_node20() {
    bash -i -c "nvm install ${NODE20_VERSION}"
}

# Install mongo4 in ~/.local/bin/mongo4
# Arg1: a writable folder where to write downloaded files
# NOTE: each mongo version is installed in a separate folder to support multiple versions
install_mongo4() {
    local DL_ROOT=$1
    local DL_PATH="$DL_ROOT/mongo4"
    mkdir -p "$DL_PATH" && cd "$DL_PATH"
    case "$OS_ID" in
        debian)
            curl -OLsS http://ftp.us.debian.org/debian/pool/main/o/openssl/libssl1.1_1.1.1w-0+deb11u1_amd64.deb
            DEBIAN_FRONTEND=noninteractive && dpkg -i libssl1.1_1.1.1w-0+deb11u1_amd64.deb
            local MONGODB_SUFFIX=debian10-${MONGODB4_VERSION}
            ;;
        ubuntu)
            DEBIAN_FRONTEND=noninteractive && sudo apt-get --no-install-recommends --yes install libssl1.1
            local MONGODB_SUFFIX=ubuntu2004-${MONGODB4_VERSION}
            ;;
        *)
    esac

    curl -OLsS "https://fastdl.mongodb.org/linux/mongodb-linux-x86_64-${MONGODB_SUFFIX}.tgz"
    tar xf "mongodb-linux-x86_64-${MONGODB_SUFFIX}.tgz"
    mkdir -p ~/.local/bin/mongo4
    cp -fR "mongodb-linux-x86_64-${MONGODB_SUFFIX}/bin/mongod" ~/.local/bin/mongo4
    sudo mkdir -p /var/lib/mongo4 && sudo mkdir -p /var/log/mongodb4
    sudo chmod a+rwx /var/lib/mongo4 && sudo chmod a+rwx /var/log/mongodb4
    cd ~-
}

# Install mongo5 in ~/.local/bin/mongo5
# Arg1: a writable folder where to write downloaded files
# NOTE: each mongo version is installed in a separate folder to support multiple versions
install_mongo5() {
    local DL_ROOT=$1
    local DL_PATH="$DL_ROOT/mongo5"
    mkdir -p "$DL_PATH" && cd "$DL_PATH"
    case "$OS_ID" in
        debian)
            curl -OLsS http://ftp.us.debian.org/debian/pool/main/o/openssl/libssl1.1_1.1.1w-0+deb11u1_amd64.deb
            DEBIAN_FRONTEND=noninteractive && dpkg -i libssl1.1_1.1.1w-0+deb11u1_amd64.deb
            local MONGODB_SUFFIX=debian11-${MONGODB5_VERSION}
            ;;
        ubuntu)
            DEBIAN_FRONTEND=noninteractive && sudo apt-get --no-install-recommends --yes install libssl1.1
            local MONGODB_SUFFIX=ubuntu2004-${MONGODB5_VERSION}
            ;;
        *)
    esac

    curl -OLsS "https://fastdl.mongodb.org/linux/mongodb-linux-x86_64-${MONGODB_SUFFIX}.tgz"
    tar xf "mongodb-linux-x86_64-${MONGODB_SUFFIX}.tgz"
    mkdir -p ~/.local/bin/mongo5
    cp -fR "mongodb-linux-x86_64-${MONGODB_SUFFIX}/bin/mongod" ~/.local/bin/mongo5
    sudo mkdir -p /var/lib/mongo5 && sudo mkdir -p /var/log/mongodb5
    sudo chmod a+rwx /var/lib/mongo5 && sudo chmod a+rwx /var/log/mongodb5
    cd ~-
}

# Install mongo6 in ~/.local/bin/mongo6
# Arg1: a writable folder where to write downloaded files
# NOTE: each mongo version is installed in a separate folder to support multiple versions
install_mongo6() {
    local DL_ROOT=$1
    local DL_PATH="$DL_ROOT/mongo6"
    mkdir -p "$DL_PATH" && cd "$DL_PATH"
    case "$OS_ID" in
        debian)
            curl -OLsS http://ftp.us.debian.org/debian/pool/main/o/openssl/libssl1.1_1.1.1w-0+deb11u1_amd64.deb
            DEBIAN_FRONTEND=noninteractive && dpkg -i libssl1.1_1.1.1w-0+deb11u1_amd64.deb
            local MONGODB_SUFFIX=debian11-${MONGODB6_VERSION}
            ;;
        ubuntu)
            local MONGODB_SUFFIX=ubuntu2204-${MONGODB6_VERSION}
            ;;
        *)
    esac

    curl -OLsS "https://fastdl.mongodb.org/linux/mongodb-linux-x86_64-${MONGODB_SUFFIX}.tgz"
    tar xf "mongodb-linux-x86_64-${MONGODB_SUFFIX}.tgz"
    mkdir -p ~/.local/bin/mongo6
    cp -fR "mongodb-linux-x86_64-${MONGODB_SUFFIX}/bin/mongod" ~/.local/bin/mongo6
    sudo mkdir -p /var/lib/mongo6 && sudo mkdir -p /var/log/mongodb6
    sudo chmod a+rwx /var/lib/mongo6 && sudo chmod a+rwx /var/log/mongodb6
    cd ~-
}

# Install mongo7 in ~/.local/bin/mongo7
# Arg1: a writable folder where to write downloaded files
# NOTE: each mongo version is installed in a separate folder to support multiple versions
install_mongo7() {
    local DL_ROOT=$1
    local DL_PATH="$DL_ROOT/mongo7"
    mkdir -p "$DL_PATH" && cd "$DL_PATH"
    case "$OS_ID" in
        debian)
            curl -OLsS http://ftp.us.debian.org/debian/pool/main/o/openssl/libssl1.1_1.1.1w-0+deb11u1_amd64.deb
            DEBIAN_FRONTEND=noninteractive && dpkg -i libssl1.1_1.1.1w-0+deb11u1_amd64.deb
            local MONGODB_SUFFIX=debian11-${MONGODB7_VERSION}
            ;;
        ubuntu)
            local MONGODB_SUFFIX=ubuntu2204-${MONGODB7_VERSION}
            ;;
        *)
    esac

    curl -OLsS "https://fastdl.mongodb.org/linux/mongodb-linux-x86_64-${MONGODB_SUFFIX}.tgz"
    tar xf "mongodb-linux-x86_64-${MONGODB_SUFFIX}.tgz"
    mkdir -p ~/.local/bin/mongo7
    cp -fR "mongodb-linux-x86_64-${MONGODB_SUFFIX}/bin/mongod" ~/.local/bin/mongo7
    sudo mkdir -p /var/lib/mongo7 && sudo mkdir -p /var/log/mongodb7
    sudo chmod a+rwx /var/lib/mongo7 && sudo chmod a+rwx /var/log/mongodb7
    cd ~-
}

# Install listed requirements
# Usage: install_reqs mongo7 nvm node16 yq
install_reqs() {
    mkdir -p "$TMP_DIR/dl"

    for REQ in "$@"; do
        echo "Installing $REQ ..."
        install_"$REQ" "$TMP_DIR/dl"
    done
}

# Select which node version is active (ie. which one is started when calling node)
use_node() {
    local VERSION=$1

    nvm use "$VERSION"
}

# Select which mongo version is active (ie. which one is started when calling mongod)
use_mongo() {
    local VERSION=$1

    if [ "$CI" = true ]; then
        # CI k-mongo will use whatever binary is in $HOME/.local/bin

        # Binaries
        ln -sf "$HOME/.local/bin/mongo$VERSION/mongod" ~/.local/bin
        # And working dirs
        sudo ln -sf "/var/lib/mongo$VERSION" /var/lib/mongo
        sudo ln -sf "/var/log/mongodb$VERSION" /var/log/mongodb

        echo "Now using mongo $VERSION:"
        "$HOME/.local/bin/mongod" --version
    else
        # Developer's k-mongo will use MONGO_VERSION
        export MONGO_VERSION="$VERSION"
    fi
}

### Utils
###

# Try to parse semver
# Define SEMVER variable as an array with [0] = major, [1] = minor, [2] = patch
parse_semver() {
    local REGEXP="^([0-9]+)\.([0-9]+)\.([0-9]+)"
    [[ "$1" =~ $REGEXP ]]
    SEMVER=(${BASH_REMATCH[1]} ${BASH_REMATCH[2]} ${BASH_REMATCH[3]})
}

### Git
###

# Returns the current git tag (or empty string if not on a tag)
# Arg1: the repository root
get_git_tag() {
    local REPO_ROOT="$1"
    cd "$REPO_ROOT"
    git tag --points-at

    # case "$CI_ID" in
    #     github)
    #         if [ "$GITHUB_REF_TYPE" = "tag" ]; then
    #            echo "$GITHUB_REF_NAME"
    #         fi
    #         ;;
    #     gitlab)
    #         echo "${CI_COMMIT_TAG:-}"
    #         ;;
    #     travis)
    #         echo "${TRAVIS_TAG:-}"
    #         ;;
    #     *)
    #         git tag --points-at
    #         ;;
    # esac
    cd ~-
}

# Returns the current git branch (might be empty string if on a tag and repo was checked out with --depth 1)
# Arg1: the repository root
get_git_branch() {
    local REPO_ROOT="$1"
    cd "$REPO_ROOT"
    git branch --show-current

    # case "$CI_ID" in
    #     github)
    #         if [ "$GITHUB_REF_TYPE" = "branch" ]; then
    #            echo "$GITHUB_REF_NAME"
    #         fi
    #         ;;
    #     gitlab)
    #         if [ -z "$CI_COMMIT_TAG" ]; then
    #             echo "$CI_COMMIT_REF_NAME"
    #         fi
    #         ;;
    #     travis)
    #         if [ -z "$TRAVIS_TAG" ]; then
    #             echo "$TRAVIS_BRANCH"
    #         fi
    #         ;;
    #     *)
    #         git branch --show-current
    #         ;;
    # esac
    cd ~-
}

# Returns the current git commit sha, always defined
# Arg1: the repository root
get_git_commit_sha() {
    local REPO_ROOT="$1"
    cd "$REPO_ROOT"
    git rev-parse HEAD

    # case "$CI_ID" in
    #     github)
    #         echo "$GITHUB_SHA"
    #         ;;
    #     gitlab)
    #         echo "$CI_COMMIT_SHA"
    #         ;;
    #     travis)
    #         echo "$TRAVIS_COMMIT"
    #         ;;
    #     *)
    #         git rev-parse HEAD
    #         ;;
    # esac
    cd ~-
}

# Returns the current git commit _short_ sha, always defined
# Arg1: the repository root
get_git_commit_short_sha() {
    local REPO_ROOT="$1"
    cd "$REPO_ROOT"
    git rev-parse --short HEAD
    cd ~-
}

# Returns the list of changed files between two commits
# Arg1: commit to (default to latest known)
# Arg2: commit from (defaults to the one before arg1)
# NOTE: requires git history to work (ie probably not with shallow clone)
# NOTE: needs to be called from inside a git repo
# get_git_changed_files() {
#     local COMMIT0=${1:-HEAD}
#     local COMMIT1=${2:-"$COMMIT0"^}

#     cd "$REPO_ROOT"
#     if [ -z "$CI_ID" ]; then
#         git diff --name-only "$COMMIT0" "$COMMIT1"
#     fi
#     cd ~-
# }

# Returns current commit message
# Arg1: the repository root
get_git_commit_message() {
    local REPO_ROOT="$1"
    cd "$REPO_ROOT"
    git show -s --pretty=%B
    cd ~-
}

# Returns current commit author name
# Arg1: the repository root
get_git_commit_author_name() {
    local REPO_ROOT="$1"
    cd "$REPO_ROOT"
    git show -s --pretty=%an
    cd ~-
}

# Returns current commit author email
# Arg1: the repository root
get_git_commit_author_email() {
    local REPO_ROOT="$1"
    cd "$REPO_ROOT"
    git show -s --pretty=%ae
    cd ~-
}

### Github
###

# Deploys generated documentation using github pages system.
# Arg1: the repository url
# Arg2: the folder where documentation has been generated
# Arg3: the author name to use when commiting the updated documentation.
# Arg4: the author email to use when commiting the updated documentation.
# Arg5: the commit message.
# Arg6: the branch where to commit the documentation (defaults to gh-pages)
deploy_gh_pages() {
    local REPO_URL="$1"
    local DOCS_DIR="$2"
    local COMMIT_AUTHOR_NAME="$3"
    local COMMIT_AUTHOR_EMAIL="$4"
    local COMMIT_MESSAGE="$5"
    local DOCS_BRANCH="${6:-gh-pages}"

    local WORK_DIR
    WORK_DIR="$(mktemp -d -p "$TMP_DIR" gh_pages.XXXXXX)"

    # Clone repo to a temp location
    git clone --depth 1 --branch "$DOCS_BRANCH" "$REPO_URL" "$WORK_DIR"
    # Copy built doc
    cp -fR "$DOCS_DIR"/* "$WORK_DIR"
    # Add new doc and commit (add a .nojekyll file to skip Github jekyll processing)
    cd "$WORK_DIR" && touch .nojekyll && git add --all && git -c user.name="$COMMIT_AUTHOR_NAME" -c user.email="$COMMIT_AUTHOR_EMAIL" commit --message "$COMMIT_MESSAGE"
    # Push
    git push origin "$DOCS_BRANCH"
}

### Log
###

KASH_TXT_B="\e["
KASH_TXT_E="m"
KASH_TXT_BOLD="${KASH_TXT_B}1${KASH_TXT_E}"
KASH_TXT_RESET="${KASH_TXT_B}0${KASH_TXT_E}"

# Creates a foldable log section in CI systems
# Arg1: the section title
# NOTE: foldable section must be terminated using end_group and the same $TITLE
begin_group() {
    local TITLE="$1"

    if [ "$CI_ID" = "github" ]; then
        # see https://docs.github.com/en/actions/using-workflows/workflow-commands-for-github-actions#grouping-log-lines
        echo "::group::$TITLE"
    elif [ "$CI_ID" = "gitlab" ]; then
        # see https://docs.gitlab.com/ee/ci/jobs/#custom-collapsible-sections
        echo -e "\e[0Ksection_start:$(date +%s):$TITLE\r\e[0KHeader of the 1st collapsible section"
    elif [ "$CI_ID" = "travis" ]; then
        # see
        echo "travis_fold:start:$TITLE"
    fi
}

# Terminates a foldable log section in CI systems
# Arg1: the section title
end_group() {
    local TITLE="$1"

    if [ "$CI_ID" = "github" ]; then
        echo "::endgroup::"
    elif [ "$CI_ID" = "gitlab" ]; then
        echo -e "\e[0Ksection_end:$(date +%s):$TITLE\r\e[0K"
    elif [ "$CI_ID" = "travis" ]; then
        echo "travis_fold:end:$TITLE"
    fi
}

### Slack
###

slack_send() {
    local PAYLOAD="$1"
    local URL="$2"

    curl -X POST -H "Content-type: application/json" --data "$PAYLOAD" "$URL"
}

# Push a simple message to a slack channel
# Arg1: the Slack webhook where to push the message
# Arg2: the message (can be markdown formatted)
slack_log() {
    local URL="$1"
    local MSG="$2"

    PAYLOAD="{ blocks: [ { \"type\": \"section\", \"text\": { \"type\": \"mrkdwn\", \"text\": \"$MSG\" } } ] }"
    slack_send "$PAYLOAD" "$URL"
}

# Push a colored message to a slack channel
# Arg1: the Slack webhook where to push the message
# Arg2: the message (can be markdown formatted)
# Arg3: the color to use (as and hex value)
slack_color_log() {
    local URL="$1"
    local MSG="$2"
    local COLOR="$3"

    PAYLOAD="{ attachments: [ { \"color\": \"$COLOR\", blocks: [ { \"type\": \"section\", \"text\": { \"type\": \"mrkdwn\", \"text\": \"$MSG\" } } ] } ] }"
    slack_send "$PAYLOAD" "$URL"
}

# Report ci job result to slack channel
# Expected usage is to do the following:
# trap 'slack_ci_report "$ROOT_DIR" "CI step name" "$?" "$SLACK_WEBHOOK_APPS"' EXIT
# Exit code 0 = success, anything else is failure
# Arg1: the repository root
# Arg2: the exit code of the ci job
# Arg3: the slack webhook where to push report
slack_ci_report() {
    local REPO_DIR="$1"
    local CI_STEP_NAME="$2"
    local RET_CODE="$3"
    local SLACK_WEBHOOK="$4"

    local STATUS="success"
    local COLOR="#2eb886"
    if [ "$RET_CODE" != "0" ]; then STATUS="failed"; COLOR="#a30200"; fi

    local MESSAGE
    case "$CI_ID" in
        github)
            MESSAGE=$(printf "*%s*: %s %s *@%s* (%s, <%s|repo>, <%s|commit>, <%s|run>)" \
                "$GITHUB_REPOSITORY" \
                "$CI_STEP_NAME" \
                "$STATUS" \
                "$GITHUB_REF_NAME" \
                "$GITHUB_ACTOR" \
                "$GITHUB_SERVER_URL/$GITHUB_REPOSITORY" \
                "$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/commit/$GITHUB_SHA" \
                "$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID")
            ;;
        *)
            ;;
    esac

    slack_color_log "$SLACK_WEBHOOK" "$MESSAGE" "$COLOR"
}

### SOPS
###

# Generates the decrypted filename for the given encrypted file
# Arg1: the encrypted filename
# NOTE: decrypted file will be XXXXX.dec.ext
enc2dec() {
    local ENC="$1"
    local BASENAME
    BASENAME="$(basename "$ENC")"
    local FILENAME="${BASENAME%%.*}"
    local EXTENSION="${BASENAME##*.}"
    local DEC
    DEC="$(dirname "$ENC")/${FILENAME}.dec.${EXTENSION}"
    echo "$DEC"
}

# Generates the encrypted filename for the given decrypted file
# Arg1: the decrypted filename
# NOTE: decrypted file will be XXXXX.dec.ext
dec2enc() {
    local DEC="$1"
    local BASENAME
    BASENAME="$(basename "$DEC")"
    local FILENAME="${BASENAME%%.*}"
    local EXTENSION="${BASENAME##*.}"
    local ENC
    ENC="$(dirname "$DEC")/${FILENAME}.enc.${EXTENSION}"
    echo "$ENC"
}

# Loads environment variables from encrypted env files
# Usage: load_env_files /path/to/file1.enc.env /path/to/file2.enc.env /path/to/file3.enc.env
# NOTE: requires SOPS_AGE_KEY or SOPS_AGE_KEY_FILE to be defined. If not, will defaults to $DEVELOPMENT_DIR/age/keys.txt
load_env_files() {
    # Use developer key unless one of SOPS_AGE_KEY or SOPS_AGE_KEY_FILE is already defined (eg. CI)
    if [ -z "${SOPS_AGE_KEY-}" ] && [ -z "${SOPS_AGE_KEY_FILE-}" ]; then
        export SOPS_AGE_KEY_FILE="$DEVELOPMENT_DIR/age/keys.txt"
    fi

    for ENC in "$@"; do
        if [ -f "$ENC" ]; then
            local DEC
            DEC="$(enc2dec "$ENC")"
            sops --decrypt --output "$DEC" "$ENC"
            set -a && . "$DEC" && set +a
        fi
    done
}

# Decrypt files containing secrets and define an environment variable pointing on the decrypted filename
# Usage: load_value_files /path/to/FOO_PASSWORD.enc.value /path/to/BLAH_SECRET.enc.value
# Will decrypt the files and define FOO_PASSWORD to the decrypted filename. It can be used to feed the decrypted value from stdin.
load_value_files() {
    # Use developer key unless one of SOPS_AGE_KEY or SOPS_AGE_KEY_FILE is already defined (eg. CI)
    if [ -z "${SOPS_AGE_KEY-}" ] && [ -z "${SOPS_AGE_KEY_FILE-}" ]; then
        export SOPS_AGE_KEY_FILE="$DEVELOPMENT_DIR/age/keys.txt"
    fi

    for ENC in "$@"; do
        if [ -f "$ENC" ]; then
            local DEC
            DEC="$(enc2dec "$ENC")"
            sops --decrypt --output "$DEC" "$ENC"

            local BASENAME
            BASENAME=$(basename "$DEC")
            local VAR_NAME="${BASENAME%%.*}"
            # Define (and export) $filename as env var with path to decrypted file as value
            declare -gx "$VAR_NAME"="$DEC"
        fi
    done
}

### Kalisio
###

# Gather information about an app
# Defines APP_INFOS variable as an array. This array contains the app name, the app version,
# the flavor based on the git tag and branch ...
# Arg1: the repository root
# Arg2: the folder where to search for kli files
# NOTE: the results should be extracted using get_app_xxx functions below.
init_app_infos() {
    local REPO_ROOT="$1"
    local KLI_BASE="$2"
    local APP_NAME
    APP_NAME=$(node -p -e "require(\"$REPO_ROOT/package.json\").name")
    local APP_VERSION
    APP_VERSION=$(node -p -e "require(\"$REPO_ROOT/package.json\").version")
    local APP_FLAVOR
    local APP_KLI

    local GIT_TAG
    GIT_TAG=$(get_git_tag "$REPO_ROOT")
    local GIT_BRANCH
    GIT_BRANCH=$(get_git_branch "$REPO_ROOT")

    local PROD_REGEX="^prod-v"
    local TEST_REGEX="^test-|-test$"

    if [[ "$GIT_TAG" =~ $PROD_REGEX ]]; then
        APP_FLAVOR=prod
        APP_KLI="$APP_NAME-$APP_VERSION"
    else
        if [[ "$GIT_BRANCH" =~ $TEST_REGEX ]]; then
            APP_FLAVOR="test"
            parse_semver "$APP_VERSION"
            APP_KLI="$APP_NAME-${SEMVER[0]}.${SEMVER[1]}"
        else
            APP_FLAVOR=dev
            APP_KLI="$APP_NAME"
            if [ -f "$KLI_BASE/$APP_NAME/$APP_FLAVOR/$APP_NAME-$GIT_BRANCH.js" ]; then
                APP_KLI="$APP_NAME-$GIT_BRANCH"
            fi
        fi
    fi

    APP_KLI="$KLI_BASE/$APP_NAME/$APP_FLAVOR/$APP_KLI.js"

    APP_INFOS=("$APP_NAME" "$APP_VERSION" "$APP_FLAVOR" "$GIT_TAG" "$GIT_BRANCH" "$APP_KLI")
}

# Extract app name from app infos
# NOTE: requires a call to init_app_infos first
get_app_name() {
    echo "${APP_INFOS[0]}"
}

# Extract app version from app infos
# NOTE: requires a call to init_app_infos first
get_app_version() {
    echo "${APP_INFOS[1]}"
}

# Extract app flavor from app infos
# NOTE: requires a call to init_app_infos first
get_app_flavor() {
    echo "${APP_INFOS[2]}"
}

# Extract app tag from app infos
# NOTE: requires a call to init_app_infos first
get_app_tag() {
    echo "${APP_INFOS[3]}"
}

# Extract app branch from app infos
# NOTE: requires a call to init_app_infos first
get_app_branch() {
    echo "${APP_INFOS[4]}"
}

# Extract app kli file from app infos
# NOTE: requires a call to init_app_infos first
get_app_kli_file() {
    echo "${APP_INFOS[5]}"
}

# Runs kli in a separate folder.
# Arg1: the folder where to install everything
# Arg2: the node version to use (16, 18 ...)
# Arg3: the kli file to use
# Arg4: 'klifull' to install and link using kli, anything else will only clone
run_kli() {
    local WORK_DIR="$1"
    local NODE_VERSION="$2"
    local KLI_FILE="$3"
    local KLI_RUN="${4:-klifull}"

    # Clone kli in venv if not there
    if [ ! -d "$WORK_DIR/kli" ]; then
        git clone --depth 1 "https://github.com/kalisio/kli.git" "$WORK_DIR/kli"
        cd "$WORK_DIR/kli" && nvm exec "$NODE_VERSION" yarn install && cd ~-
    fi

    cd "$WORK_DIR"
    nvm exec "$NODE_VERSION" node "$WORK_DIR/kli/index.js" "$KLI_FILE" --clone --shallow-clone
    if [ "$KLI_RUN" = klifull ]; then
        nvm exec "$NODE_VERSION" node "$WORK_DIR/kli/index.js" "$KLI_FILE" --install
        nvm exec "$NODE_VERSION" node "$WORK_DIR/kli/index.js" "$KLI_FILE" --link --link-folder "$WORK_DIR/yarn-links"
    fi
    cd ~-
}

# Gather information about an librarie
# Defines LIB_INFOS variable as an array. This array contains the lib name & the lib version
# Arg1: the repository root
# NOTE: the results should be extracted using get_lib_xxx functions below.
init_lib_infos() {
    local REPO_ROOT="$1"
    local LIB_NAME
    LIB_NAME=$(node -p -e "require(\"$REPO_ROOT/package.json\").name")
    local LIB_VERSION
    LIB_VERSION=$(node -p -e "require(\"$REPO_ROOT/package.json\").version")

    local GIT_TAG
    GIT_TAG=$(get_git_tag "$REPO_ROOT")
    local GIT_BRANCH
    GIT_BRANCH=$(get_git_branch "$REPO_ROOT")

    LIB_INFOS=("$LIB_NAME" "$LIB_VERSION" "$GIT_TAG" "$GIT_BRANCH")
}

# Extract lib name from lib infos
# NOTE: requires a call to init_lib_infos first
get_lib_name() {
    echo "${LIB_INFOS[0]}"
}

# Extract lib version from lib infos
# NOTE: requires a call to init_lib_infos first
get_lib_version() {
    echo "${LIB_INFOS[1]}"
}

# Extract lib tag from app infos
# NOTE: requires a call to init_lib_infos first
get_lib_tag() {
    echo "${LIB_INFOS[2]}"
}

# Extract app branch from app infos
# NOTE: requires a call to init_lib_infos first
get_lib_branch() {
    echo "${LIB_INFOS[3]}"
}
