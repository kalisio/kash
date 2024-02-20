#!/usr/bin/env bash

### Variables provided by this script
###   - TMP_PATH: a path where to write temp files
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
elif [ "${GITLAB_CI:-}" = true ]; then
    CI_ID="gitlab"
elif [  "${TRAVIS:-}" = true ]; then
    CI_ID="travis"
fi

if [ -n "$CI_ID" ]; then
    CI=true
    echo "Running in CI mode ($CI_ID)..."

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

install_node16() {
    bash -i -c "nvm install ${NODE16_VERSION}"
}

install_node18() {
    bash -i -c "nvm install ${NODE18_VERSION}"
}

install_node20() {
    bash -i -c "nvm install ${NODE20_VERSION}"
}

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
            curl -OLsS http://security.ubuntu.com/ubuntu/pool/main/o/openssl/libssl1.1_1.1.1f-1ubuntu2.21_amd64.deb
            DEBIAN_FRONTEND=noninteractive && sudo dpkg -i libssl1.1_1.1.1f-1ubuntu2.21_amd64.deb
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
            curl -OLsS http://security.ubuntu.com/ubuntu/pool/main/o/openssl/libssl1.1_1.1.1f-1ubuntu2.21_amd64.deb
            DEBIAN_FRONTEND=noninteractive && sudo dpkg -i libssl1.1_1.1.1f-1ubuntu2.21_amd64.deb
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

install_reqs() {
    mkdir -p "$TMP_DIR/dl"

    for REQ in "$@"; do
        echo "Installing $REQ ..."
        install_"$REQ" "$TMP_DIR/dl"
    done
}

use_node() {
    local VERSION=$1

    nvm use "$VERSION"
}

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

parse_semver() {
    local REGEXP="^([0-9]+)\.([0-9]+)\.([0-9]+)"
    [[ "$1" =~ $REGEXP ]]
    SEMVER=(${BASH_REMATCH[1]} ${BASH_REMATCH[2]} ${BASH_REMATCH[3]})
}

### Git
###

get_git_tag() {
    local REPO_ROOT="$1"
    cd "$REPO_ROOT"
    case "$CI_ID" in
        github)
            if [ "$GITHUB_REF_TYPE" = "tag" ]; then
               echo "$GITHUB_REF_NAME"
            fi
            ;;
        gitlab)
            echo "${CI_COMMIT_TAG:-}"
            ;;
        travis)
            echo "${TRAVIS_TAG:-}"
            ;;
        *)
            git tag --points-at
            ;;
    esac
    cd ~-
}

get_git_branch() {
    local REPO_ROOT="$1"
    cd "$REPO_ROOT"
    case "$CI_ID" in
        github)
            if [ "$GITHUB_REF_TYPE" = "branch" ]; then
               echo "$GITHUB_REF_NAME"
            fi
            ;;
        gitlab)
            if [ -z "$CI_COMMIT_TAG" ]; then
                echo "$CI_COMMIT_REF_NAME"
            fi
            ;;
        travis)
            if [ -z "$TRAVIS_TAG" ]; then
                echo "$TRAVIS_BRANCH"
            fi
            ;;
        *)
            git branch --show-current
            ;;
    esac
    cd ~-
}

get_git_commit_sha() {
    local REPO_ROOT="$1"
    cd "$REPO_ROOT"
    case "$CI_ID" in
        github)
            echo "$GITHUB_SHA"
            ;;
        gitlab)
            echo "$CI_COMMIT_SHA"
            ;;
        travis)
            echo "$TRAVIS_COMMIT"
            ;;
        *)
            git rev-parse HEAD
            ;;
    esac
    cd ~-
}

get_git_changed_files() {
    local COMMIT0=${1:-HEAD}
    local COMMIT1=${2:-"$COMMIT0"^}

    cd "$REPO_ROOT"
    if [ -z "$CI_ID" ]; then
        git diff --name-only "$COMMIT0" "$COMMIT1"
    fi
    cd ~-
}

### Github
###

deploy_gh_pages() {
    local REPO_URL="$1"
    local DOCS_DIR="$2"
    local AUTHOR_NAME="$3"
    local AUTHOR_EMAIL="$4"
    local COMMIT_MESSAGE="$5"
    local DOCS_BRANCH="${6:-gh-pages}"

    local WORK_DIR
    WORK_DIR="$(mktemp -d -p "$TMP_DIR" gh_pages.XXXXXX)"

    # Clone repo to a temp location
    git clone --depth 1 --branch "$DOCS_BRANCH" "$REPO_URL" "$WORK_DIR"
    # Setup local commiter
    git config user.name "$AUTHOR_NAME"
    git config user.email "$AUTHOR_EMAIL"
    # Copy built doc
    cp -fR "$DOCS_DIR"/* "$WORK_DIR"
    # Add new doc and commit (add a .nojekyll file to skip Github jekyll processing)
    cd "$WORK_DIR" && touch .nojekyll && git add --all && git commit -m "$COMMIT_MESSAGE"
    # Push
    git push origin "$BRANCH"
}

### Log
###

KASH_TXT_B="\e["
KASH_TXT_E="m"
KASH_TXT_BOLD="${KASH_TXT_B}1${KASH_TXT_E}"
KASH_TXT_RESET="${KASH_TXT_B}0${KASH_TXT_E}"

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

slack_log() {
    local URL="$1"
    local MSG="$2"

    PAYLOAD="{ blocks: [ { \"type\": \"section\", \"text\": { \"type\": \"mrkdwn\", \"text\": \"$MSG\" } } ] }"
    curl -X POST -H "Content-type: application/json" --data "$PAYLOAD" "$URL"
}

slack_color_log() {
    local URL="$1"
    local MSG="$2"
    local COLOR="$3"

    PAYLOAD="{ attachments: [ { \"color\": \"$COLOR\", blocks: [ { \"type\": \"section\", \"text\": { \"type\": \"mrkdwn\", \"text\": \"$MSG\" } } ] } ] }"
    curl -X POST -H "Content-type: application/json" --data "$PAYLOAD" "$URL"
}

### SOPS
###

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

# Loads environment variables from an encrypted env file
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

# Decrypt files containing secrets and define an environment variable
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
    if [[ "$GIT_TAG" =~  prod-v* ]]; then
        APP_FLAVOR=prod
        APP_KLI="$APP_NAME-$APP_VERSION"
    else
        if [[ "$GIT_BRANCH" =~ ^test-*|*-test$ ]]; then
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

    APP_INFOS=("$APP_NAME" "$APP_VERSION" "$APP_FLAVOR" "GIT_TAG" "GIT_BRANCH" "$APP_KLI")
}

get_app_name() {
    echo "${APP_INFOS[0]}"
}

get_app_version() {
    echo "${APP_INFOS[1]}"
}

get_app_flavor() {
    echo "${APP_INFOS[2]}"
}

get_app_tag() {
    echo "${APP_INFOS[3]}"
}

get_app_branch() {
    echo "${APP_INFOS[4]}"
}

get_app_kli_file() {
    echo "${APP_INFOS[5]}"
}

run_kli() {
    local WORK_DIR="$1"
    local KLI_FILE="$2"
    local NODE_VERSION="$3"

    # Clone kli in venv if not there
    if [ ! -d "$WORK_DIR/kli" ]; then
        git clone --depth 1 "https://github.com/kalisio/kli.git" "$WORK_DIR/kli"
        cd "$WORK_DIR/kli" && nvm exec "$NODE_VERSION" yarn install && cd ~-
    fi

    cd "$WORK_DIR"
    nvm exec "$NODE_VERSION" node "$WORK_DIR/kli/index.js" "$KLI_FILE" --clone --shallow-clone
    nvm exec "$NODE_VERSION" node "$WORK_DIR/kli/index.js" "$KLI_FILE" --install
    nvm exec "$NODE_VERSION" node "$WORK_DIR/kli/index.js" "$KLI_FILE" --link --link-folder "$WORK_DIR/yarn-links"
    cd ~-
}
