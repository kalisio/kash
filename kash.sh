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
    set +e
    command -v curl >/dev/null 2>&1 && command -v git >/dev/null 2>&1 && command -v sha256sum >/dev/null 2>&1
    RC=$?
    set -e

    if [ "$RC" -ne 0 ]; then
        case "$OS_ID" in
            debian | ubuntu)
                if [ "$(id -u)" -eq 0 ]; then
                    apt-get update && apt-get --no-install-recommends --yes install sudo curl ca-certificates coreutils git
                else
                    sudo apt-get update && sudo apt-get --no-install-recommends --yes install curl ca-certificates coreutils git
                fi
                ;;
            alpine)
                apk update && apk add curl ca-certificates coreutils git
                ;;
            *)
                ;;
        esac
    fi

    # Emulate development k-mongo when running on CI
    cat <<EOF > ~/.local/bin/k-mongo
#!/usr/bin/env bash
mongod --dbpath /var/lib/mongo --logpath /var/log/mongodb/mongod.log --fork --port 27017
EOF
    chmod a+x ~/.local/bin/k-mongo

    # Most CI services understand ANSI colors
    export TERM=xterm-color

    # Allow nvm to work on alpine distro (downloads an unofficial build targeting musl libc)
    # See:
    #   - https://github.com/nvm-sh/nvm/issues/1102#issuecomment-1112898778
    #   - https://github.com/nvm-sh/nvm/pull/3212
    if [ "$OS_ID" = "alpine" ]; then
        export NVM_NODEJS_ORG_MIRROR="https://unofficial-builds.nodejs.org/download/release" # Set up unofficial builds
    fi
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

# https://github.com/mikefarah/yq/releases
YQ_VERSION=4.40.5
# https://github.com/FiloSottile/age/releases
AGE_VERSION=1.1.1
# https://github.com/getsops/sops/releases
SOPS_VERSION=3.8.1

# https://github.com/kubernetes/kubernetes/tree/master/CHANGELOG
KUBECTL_VERSION=1.28.13
# https://github.com/helm/helm/releases
HELM_VERSION=3.14.4
# https://github.com/helmfile/helmfile/releases
HELMFILE_VERSION=0.167.1
# https://github.com/derailed/k9s/releases
K9S_VERSION=0.32.4

# https://github.com/nvm-sh/nvm/releases
NVM_VERSION=0.39.7
# https://nodejs.org/en/about/previous-releases#looking-for-latest-release-of-a-version-branch
NODE16_VERSION=16.20.2
NODE18_VERSION=18.19.1
NODE20_VERSION=20.11.1
NODE22_VERSION=22.3.0

# https://www.mongodb.com/try/download/community
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
        ./extract-checksum.sh "SHA-256" "yq_linux_amd64.tar.gz" | awk '{ print $2 " " $1}' | sha256sum --check --quiet
        cd ~-
    fi
    cd "$DL_PATH"
    tar xf yq_linux_amd64.tar.gz
    mv yq_linux_amd64 ~/.local/bin/yq
    chmod u+x ~/.local/bin/yq
    cd ~-
}

# Call this to ensure yq is available
ensure_yq() {
    set +e
    command -v yq >/dev/null 2>&1
    local RC=$?
    set -e

    if [ "$RC" -ne  0 ]; then
        mkdir -p "$TMP_DIR/dl"
        install_yq "$TMP_DIR/dl"
    fi
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
        cd ~-
    fi
    cd "$DL_PATH"
    tar xf age-v${AGE_VERSION}-linux-amd64.tar.gz
    cp age/age ~/.local/bin
    cp age/age-keygen ~/.local/bin
    cd ~-
}

# Call this to ensure age is available
ensure_age() {
    set +e
    command -v age >/dev/null 2>&1
    local RC=$?
    set -e

    if [ "$RC" -ne  0 ]; then
        mkdir -p "$TMP_DIR/dl"
        install_age "$TMP_DIR/dl"
    fi
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
        cd ~-
    fi
    cd "$DL_PATH"
    cp sops-v${SOPS_VERSION}.linux.amd64 ~/.local/bin/sops
    chmod u+x ~/.local/bin/sops
    cd ~-
}

# Call this to ensure sops is available
ensure_sops() {
    set +e
    command -v sops >/dev/null 2>&1
    local RC=$?
    set -e

    if [ "$RC" -ne  0 ]; then
        mkdir -p "$TMP_DIR/dl"
        install_sops "$TMP_DIR/dl"
    fi
}

# Install code climate test reporter in ~/.local/bin
# Arg1: a writable folder where to write downloaded files
install_cc_test_reporter() {
    local DL_ROOT=$1
    local DL_PATH="$DL_ROOT/cc"
    if [ ! -d "$DL_PATH" ]; then
        mkdir -p "$DL_PATH" && cd "$DL_PATH"
        curl -OLsS https://codeclimate.com/downloads/test-reporter/test-reporter-latest-linux-amd64
        curl -OLsS https://codeclimate.com/downloads/test-reporter/test-reporter-latest-linux-amd64.sha256
        sha256sum --ignore-missing --quiet -c test-reporter-latest-linux-amd64.sha256
        cd ~-
    fi
    cd "$DL_PATH"
    cp test-reporter-latest-linux-amd64 ~/.local/bin/cc-test-reporter
    chmod +x ~/.local/bin/cc-test-reporter
    cd ~-
}

# Sends test coverage to code climate
# Arg1: code climate identifier for authentication
# Arg2: prefix to use when using format-coverage (can be empty)
send_coverage_to_cc() {
    local CC_TEST_REPORTER_ID=$1
    local CC_PREFIX=${2:-}
    ~/.local/bin/cc-test-reporter format-coverage -t lcov --add-prefix "$CC_PREFIX" coverage/lcov.info
    ~/.local/bin/cc-test-reporter upload-coverage -r "$CC_TEST_REPORTER_ID"
}

# Make sure nvm is installed
# Arg1: a writable folder where to write downloaded files
# NOTE: also define 'yarn' as a default package, ie. it'll be automatically
# installed with each node version
install_nvm() {
    local DL_ROOT=$1
    local DL_PATH="$DL_ROOT/nvm"

    # Node builds for alpine x64/musl required libstdc++
    # See. https://github.com/nvm-sh/nvm/issues/1102#issuecomment-550572252
    if [ "$OS_ID" = "alpine" ] && [ "$CI" = true ]; then
        apk add libstdc++
    fi

    mkdir -p "$DL_PATH" && cd "$DL_PATH"
    curl -OLsS https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_VERSION}/install.sh
    # Make sure current user has a .bashrc where nvm installer will setup things since we mandate bash as execution shell
    if [ ! -f "$HOME/.bashrc" ]; then touch "$HOME/.bashrc"; fi
    bash ./install.sh
    # We always use yarn as package manager, so tell nvm to install it with every node installation
    # cf. https://github.com/nvm-sh/nvm?tab=readme-ov-file#default-global-packages-from-file-while-installing
    bash -i -c 'echo yarn >> $NVM_DIR/default-packages'
    cd ~-
}

# Install node16, requires nvm to be installed
install_node16() {
    bash -i -c "nvm install $NODE16_VERSION"
}

# Install node18, requires nvm to be installed
install_node18() {
    bash -i -c "nvm install $NODE18_VERSION"
}

# Install node20, requires nvm to be installed
install_node20() {
    bash -i -c "nvm install $NODE20_VERSION"
}

# Install node22, requires nvm to be installed
install_node22() {
    bash -i -c "nvm install $NODE22_VERSION"
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
            # NOTE: this assumes ubuntu 22.04
            curl -OLss http://launchpadlibrarian.net/715615335/libssl1.1_1.1.1f-1ubuntu2.22_amd64.deb
            DEBIAN_FRONTEND=noninteractive && sudo dpkg -i libssl1.1_1.1.1f-1ubuntu2.22_amd64.deb
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
            # NOTE: this assumes ubuntu 22.04
            curl -OLss http://launchpadlibrarian.net/715615335/libssl1.1_1.1.1f-1ubuntu2.22_amd64.deb
            DEBIAN_FRONTEND=noninteractive && sudo dpkg -i libssl1.1_1.1.1f-1ubuntu2.22_amd64.deb
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

# Install kubectl in ~/.local/bin
# Expected args:
#  1. a writable folder where to write downloaded files
install_kubectl() {
    local DL_ROOT=$1
    local DL_PATH="$DL_ROOT/kubectl"
    if [ ! -d "$DL_PATH" ]; then
        mkdir -p "$DL_PATH" && cd "$DL_PATH"
        curl -OLsS https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl && \
        curl -OLsS https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl.sha256 && \
        echo "$(cat kubectl.sha256) kubectl" | sha256sum --check
        cd ~-
    fi
    cd "$DL_PATH"
    mv kubectl ~/.local/bin/kubectl
    chmod u+x ~/.local/bin/yq
    cd ~-
}

# Install helm in ~/.local/bin
# Expected args:
#  1. a writable folder where to write downloaded files
install_helm() {
    local DL_ROOT=$1
    local DL_PATH="$DL_ROOT/helm"
    if [ ! -d "$DL_PATH" ]; then
        mkdir -p "$DL_PATH" && cd "$DL_PATH"
        curl -OLsS https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz
        curl -OLsS https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz.sha256sum
        sha256sum --ignore-missing --quiet -c helm-v${HELM_VERSION}-linux-amd64.tar.gz.sha256sum
        cd ~-
    fi
    cd "$DL_PATH"
    tar xf helm-v${HELM_VERSION}-linux-amd64.tar.gz
    cp linux-amd64/helm ~/.local/bin
    cd ~-
}

# Install helmfile in ~/.local/bin
# Expected args:
#  1. a writable folder where to write downloaded files
install_helmfile() {
    local DL_ROOT=$1
    local DL_PATH="$DL_ROOT/helmfile"
    if [ ! -d "$DL_PATH" ]; then
        mkdir -p "$DL_PATH" && cd "$DL_PATH"
        curl -OLsS https://github.com/helmfile/helmfile/releases/download/v${HELMFILE_VERSION}/helmfile_${HELMFILE_VERSION}_linux_amd64.tar.gz
        curl -OLsS https://github.com/helmfile/helmfile/releases/download/v${HELMFILE_VERSION}/helmfile_${HELMFILE_VERSION}_checksums.txt
        sha256sum --ignore-missing --quiet -c helmfile_${HELMFILE_VERSION}_checksums.txt
        cd ~-
    fi
    cd "$DL_PATH"
    tar xf helmfile_${HELMFILE_VERSION}_linux_amd64.tar.gz
    cp helmfile ~/.local/bin
    cd ~-
}

# Install k9s in ~/.local/bin
# Expected args:
#  1. a writable folder where to write downloaded files
install_k9s() {
    local DL_ROOT=$1
    local DL_PATH="$DL_ROOT/k9s"
    if [ ! -d "$DL_PATH" ]; then
        mkdir -p "$DL_PATH" && cd "$DL_PATH"
        curl -OLsS https://github.com/derailed/k9s/releases/download/v${K9S_VERSION}/k9s_Linux_amd64.tar.gz
        curl -OLsS https://github.com/derailed/k9s/releases/download/v${K9S_VERSION}/checksums.sha256
        sha256sum --ignore-missing --quiet -c checksums.sha256
        cd ~-
    fi
    cd "$DL_PATH"
    tar xf k9s_Linux_amd64.tar.gz
    cp k9s ~/.local/bin
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

get_json_value() {
    local JSON_SRC="$1"
    local JSON_FIELD="$2"

    ensure_yq
    yq --output-format=yaml ".$JSON_FIELD" "$JSON_SRC"
}

### Git
###

# Returns the current git tag (or empty string if not on a tag)
# Arg1: the repository root
get_git_tag() {
    case "$CI_ID" in
        gitlab)
            echo "${CI_COMMIT_TAG:-}"
            ;;
    #     github)
    #         if [ "$GITHUB_REF_TYPE" = "tag" ]; then
    #            echo "$GITHUB_REF_NAME"
    #         fi
    #         ;;
    #     travis)
    #         echo "${TRAVIS_TAG:-}"
    #         ;;
        *)
            local REPO_ROOT="$1"
            cd "$REPO_ROOT"
            git tag --points-at
            cd ~-
            ;;
    esac
}

# Returns the current git branch (might be empty string if on a tag and repo was checked out with --depth 1)
# Arg1: the repository root
get_git_branch() {
    case "$CI_ID" in
        gitlab)
            if [ -z "${CI_COMMIT_TAG:-}" ]; then
                echo "$CI_COMMIT_REF_NAME"
            fi
            ;;
    #     github)
    #         if [ "$GITHUB_REF_TYPE" = "branch" ]; then
    #            echo "$GITHUB_REF_NAME"
    #         fi
    #         ;;
    #     travis)
    #         if [ -z "$TRAVIS_TAG" ]; then
    #             echo "$TRAVIS_BRANCH"
    #         fi
    #         ;;
        *)
            local REPO_ROOT="$1"
            cd "$REPO_ROOT"
            git branch --show-current
            cd ~-
            ;;
    esac
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

# Shallow clone a repo (with no history), will also (shallow) clone submodules.
# Expected args:
# 1. the url of the repo to clone
# 2. the directory where to clone the repo
# 3. the ref to clone (branch or tag)
git_shallow_clone() {
    local REPO_URL=$1
    local REPO_DIR=$2
    local REPO_REF=${3:-}

    local GIT_OPS="--depth 1 --recurse-submodules --shallow-submodules"
    if [ -n "$REPO_REF" ]; then
        GIT_OPS="$GIT_OPS --branch $REPO_REF"
    fi

    git clone $GIT_OPS "$REPO_URL" "$REPO_DIR"
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

    if [ "$CI" = true ]; then
        if [ "$CI_ID" = "github" ]; then
            # see https://docs.github.com/en/actions/using-workflows/workflow-commands-for-github-actions#grouping-log-lines
            echo "::group::$TITLE"
        elif [ "$CI_ID" = "gitlab" ]; then
            # see https://docs.gitlab.com/ee/ci/jobs/#custom-collapsible-sections
            local SECTION
            SECTION=$(echo "$TITLE" | tr ' .:-' '_')
            echo -e "section_start:$(date +%s):$SECTION\r\e[0K\e[95m$TITLE\e[0m"
        elif [ "$CI_ID" = "travis" ]; then
            # see
            echo "travis_fold:start:$TITLE"
        fi
    else
        echo "%< --- $TITLE ------"
    fi
}

# Terminates a foldable log section in CI systems
# Arg1: the section title
end_group() {
    local TITLE="$1"

    if [ "$CI" = true ]; then
        if [ "$CI_ID" = "github" ]; then
            echo "::endgroup::"
        elif [ "$CI_ID" = "gitlab" ]; then
            local SECTION
            SECTION=$(echo "$TITLE" | tr ' .:-' '_')
            echo -e "section_end:$(date +%s):$SECTION\r\e[0K"
        elif [ "$CI_ID" = "travis" ]; then
            echo "travis_fold:end:$TITLE"
        fi
    else
        echo "------ $TITLE --- >%"
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

    local PAYLOAD="{ blocks: [ { \"type\": \"section\", \"text\": { \"type\": \"mrkdwn\", \"text\": \"$MSG\" } } ] }"
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

    local PAYLOAD="{ attachments: [ { \"color\": \"$COLOR\", blocks: [ { \"type\": \"section\", \"text\": { \"type\": \"mrkdwn\", \"text\": \"$MSG\" } } ] } ] }"
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

# Report e2e test result to slack channel
# Arg1: the app name
# Arg2: the exit code of the tests
# Arg3: the slack webhook where to push report
# Arg4: link to chrome logs
# Arg5: link to screenshots
slack_e2e_report() {
    local APP="$1"
    local RET_CODE="$2"
    local SLACK_WEBHOOK="$3"
    local CHROME_LOGS_LINK="$4"
    local SCREEN_LINK="$5"

    local STATUS="success"
    local COLOR="#2eb886"
    if [ "$RET_CODE" != "0" ]; then STATUS="failed"; COLOR="#a30200"; fi

    local MESSAGE
    MESSAGE=$(printf "*%s*: run_e2e_tests %s" \
        "$APP" \
        "$STATUS")
    if [ -n "$CHROME_LOGS_LINK" ] && [ -n "$SCREEN_LINK" ]; then
        MESSAGE+=" (<${CHROME_LOGS_LINK}|chrome logs> | <${SCREEN_LINK}|screenshots>)"
    elif [ -n "$CHROME_LOGS_LINK" ]; then
        MESSAGE+=" (<${CHROME_LOGS_LINK}|chrome logs>"
    elif [ -n "$SCREEN_LINK" ]; then
        MESSAGE+=" (<${SCREEN_LINK}|screenshots>)"
    fi

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

# Returns the kalisio flavor (prod, test, dev) according to current branch/tag name
# Expected args:
# 1. the repository root folder
get_flavor_from_git() {
    local REPO_DIR=$1
    # Matches 'test' but also 'test-v1.2'
    local TEST_FLAVOR_REGEX="^test(-v[0-9]+\.[0-9]+)?$"
    # Only matches 'prod-v1.2.3'
    local PROD_FLAVOR_REGEX="^prod-v[0-9]+\.[0-9]+\.[0-9]+$"

    local GIT_TAG
    GIT_TAG=$(get_git_tag "$REPO_DIR")
    local GIT_BRANCH
    GIT_BRANCH=$(get_git_branch "$REPO_DIR")

    if [[ "$GIT_TAG" =~ $PROD_FLAVOR_REGEX ]]; then
        printf "prod"
    elif [[ "$GIT_BRANCH" =~ $TEST_FLAVOR_REGEX ]]; then
        printf "test"
    else
        printf "dev"
    fi
}

# Returns the git ref that produced the given container tag.
# Eg.
#   - container tag is 2.2.0-test => git ref = test-v2.2
#   - container tag is 2.2.2-prod => git ref = prod-v2.2.2
#   - container tag is 2.2.2-dev => git ref = master
# Expected args:
# 1. the container tag
get_git_ref_from_container_tag() {
    local CONTAINER_TAG=$1
    local CONTAINER_TAG_REGEX="^([0-9]+\.[0-9]+\.[0-9]+)-(.*)$"
    if [[ "$CONTAINER_TAG" =~ $CONTAINER_TAG_REGEX ]]; then
        if [ "${BASH_REMATCH[2]}" = "prod" ]; then
            # Prod container => tag is prod-v1.2.3
            printf "%s-v%s" "${BASH_REMATCH[2]}" "${BASH_REMATCH[1]}"
        elif [ "${BASH_REMATCH[2]}" = "test" ]; then
            # Test container => branch is test-v1.2 (or just test)
            printf "%s-v%s" "${BASH_REMATCH[2]}" "${BASH_REMATCH[1]%.*}"
        else
            # Dev container => branch is master
            printf "master"
        fi
    fi

    # Also possible to find just 'test' or 'dev' as container tags
    if [ "$CONTAINER_TAG" = "test" ]; then
        printf "test"
    elif [ "$CONTAINER_TAG" = "dev" ]; then
        printf "master"
    fi
}

# Runs kli in a separate folder.
# Expected args:
# 1. the folder where to install everything
# 2. the node version to use (16, 18 ...)
# 3. the kli file to use
# 4. 'klifull' to install and link using kli, anything else will only clone
# NOTE: you should probably 'undef' environment variables before calling this
# like KALISIO_DEVELOPMENT_DIR ...
run_kli() {
    local WORK_DIR="$1"
    local NODE_VERSION="$2"
    local KLI_FILE="$3"
    local KLI_RUN="${4:-klifull}"

    # Clone kli in venv if not there
    if [ ! -d "$WORK_DIR/kli" ]; then
        git_shallow_clone "https://github.com/kalisio/kli.git" "$WORK_DIR/kli"
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

# Setup the workspace for a 'simple' project.
# A 'simple' project has no kli file, but require a 'development' repo.
# It can also depend on other repo but they must be specified as additional args
# Expected args:
# 1. the workspace directory
# 2. the url of the 'development' repository
# ... additional repo url to pull. Those additional repository will be cloned in the
# workspace directory, using the basename of the repo url as repo directory.
setup_workspace() {
    local WORKSPACE_DIR="$1"
    local DEVELOPMENT_REPO_URL="$2"

    # Clone development repo
    git_shallow_clone "$DEVELOPMENT_REPO_URL" "$WORKSPACE_DIR/development"

    shift 2
    # And then additional dependencies
    for DEPENDENCY_URL in "$@"; do
        git_shallow_clone "$DEPENDENCY_URL" "$WORKSPACE_DIR/$(basename "$DEPENDENCY_URL" .git)"
    done
}

# Setup a suitable workspace for the given app.
# Expected args:
# 1. the app repository dir
# 2. the workspace dir
# 3. the url to use to clone the corresponding 'development' repository
# 4. the node version to use to setup the workspace (matter because we run kli using this node version)
# 5. the directory in which we'll find kli files relative to the 'development' repository root directory
# 6. the kind of kli we want to run (nokli, kli or klifull => cf. run_kli())
# 7. (only in dev mode) the ref (ie. tag or branch) to checkout in the workspace
setup_app_workspace() {
    ensure_yq

    local REPO_DIR="$1"
    local WORKSPACE_DIR="$2"
    local DEVELOPMENT_REPO_URL="$3"
    local NODE_VER="$4"
    local KLI_BASE="$5"
    local KLI_RUN="${6:-klifull}"

    # clone development in $WORKSPACE_DIR
    local DEVELOPMENT_DIR="$WORKSPACE_DIR/development"
    git_shallow_clone "$DEVELOPMENT_REPO_URL" "$DEVELOPMENT_DIR"

    # fetch app name and ref (tag or branch) required
    local APP_NAME
    APP_NAME=$(yq --output-format=yaml '.name' "$REPO_DIR/package.json")
    local GIT_REF=""
    if [ "$CI" = true ]; then
        # fetch ref using git on local repo
        GIT_REF=$(get_git_tag "$REPO_DIR")
        if [ -z "$GIT_REF" ]; then
            GIT_REF=$(get_git_branch "$REPO_DIR")
        fi
    else
        # fetch ref from argument
        GIT_REF="$7"
    fi

    if [ -z "$KLI_BASE" ]; then
        KLI_BASE="$DEVELOPMENT_DIR/$APP_NAME"
    else
        KLI_BASE="$DEVELOPMENT_DIR/$KLI_BASE/$APP_NAME"
    fi

    # determine associated kli file
    local KLI_FILE
    local PROD_REGEX="^prod-v([0-9]+\.[0-9]+\.[0-9]+)$"
    local TEST_REGEX="^test-v([0-9]+\.[0-9]+)$"
    if [[ "$GIT_REF" =~ $PROD_REGEX ]]; then
        KLI_FILE="$KLI_BASE/prod/$APP_NAME-${BASH_REMATCH[1]}.js"
    elif [[ "$GIT_REF" =~ $TEST_REGEX ]]; then
        KLI_FILE="$KLI_BASE/test/$APP_NAME-${BASH_REMATCH[1]}.js"
    else
        KLI_FILE="$KLI_BASE/dev/$APP_NAME-$GIT_REF.js"
        if [ ! -f "$KLI_FILE" ]; then
            KLI_FILE="$KLI_BASE/dev/$APP_NAME.js"
        fi
    fi

    # run kli !
    if [ "$KLI_RUN" = kli ] || [ "$KLI_RUN" = klifull ]; then
        echo "About to populate workspace using $KLI_FILE ..."
        # if [ "$CI" != true ]; then
        #     unset KALISIO_DEVELOPMENT_DIR
        # fi
        run_kli "$WORKSPACE_DIR" "$NODE_VER" "$KLI_FILE" "$KLI_RUN"
    fi
}

# Gather information about an app
# Defines APP_INFOS variable as an array. This array contains the app name, the app version,
# the flavor based on the git tag and branch ...
# Arg1: the repository root
# Arg2: the folder where to search for kli files
# NOTE: the results should be extracted using get_app_xxx functions below.
init_app_infos() {
    ensure_yq

    local REPO_ROOT="$1"
    local KLI_BASE="$2"

    local APP_NAME
    APP_NAME=$(yq --output-format=yaml '.name' "$REPO_ROOT/package.json")
    local APP_VERSION
    APP_VERSION=$(yq --output-format=yaml '.version' "$REPO_ROOT/package.json")

    KLI_BASE="$KLI_BASE/$APP_NAME"

    local GIT_TAG
    GIT_TAG=$(get_git_tag "$REPO_ROOT")
    local GIT_BRANCH
    GIT_BRANCH=$(get_git_branch "$REPO_ROOT")

    local GIT_REF="${GIT_TAG:-$GIT_BRANCH}"

    local APP_FLAVOR
    local KLI_FILE
    local PROD_REGEX="^prod-v([0-9]+\.[0-9]+\.[0-9]+)$"
    local TEST_REGEX="^test-v([0-9]+\.[0-9]+)$"
    if [[ "$GIT_REF" =~ $PROD_REGEX ]]; then
        APP_FLAVOR="prod"
        KLI_FILE="$KLI_BASE/$APP_FLAVOR/$APP_NAME-${BASH_REMATCH[1]}.js"
    elif [[ "$GIT_REF" =~ $TEST_REGEX ]]; then
        APP_FLAVOR="test"
        KLI_FILE="$KLI_BASE/$APP_FLAVOR/$APP_NAME-${BASH_REMATCH[1]}.js"
    else
        APP_FLAVOR="dev"
        KLI_FILE="$KLI_BASE/$APP_FLAVOR/$APP_NAME-$GIT_REF.js"
        if [ ! -f "$KLI_FILE" ]; then
            KLI_FILE="$KLI_BASE/$APP_FLAVOR/$APP_NAME.js"
        fi
    fi

    APP_INFOS=("$APP_NAME" "$APP_VERSION" "$APP_FLAVOR" "$GIT_TAG" "$GIT_BRANCH" "$KLI_FILE")
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

# Run backend tests for the given app.
# Expected arguments:
# 1. the app repository directory
# 2. the directory in which we'll find kli files relative to the 'development' repository root directory
# 3. wether to publish code coverage results (boolean)
# 4. the node version to use (16, 18, ...)
# 5. the mongo version to use (5, 6, ...). Mongo will not be started if not provided
run_app_tests() {
    local REPO_DIR="$1"
    local KLI_BASE="$2"
    local CODE_COVERAGE="$3"
    local NODE_VER="$4"
    local MONGO_VER="$5"
    local WORKSPACE_DIR
    WORKSPACE_DIR="$(dirname "$REPO_DIR")"

    init_app_infos "$REPO_DIR" "$WORKSPACE_DIR/development/$KLI_BASE"

    local APP
    APP=$(get_app_name)
    local VERSION
    VERSION=$(get_app_version)
    local FLAVOR
    FLAVOR=$(get_app_flavor)

    echo "About to run tests for $APP v$VERSION-$FLAVOR ..."

    ## Start mongo
    ##

    if [ -n "$MONGO_VER" ]; then
        begin_group "Starting mongo $MONGO_VER ..."

        use_mongo "$MONGO_VER"
        k-mongo

        end_group "Starting mongo $MONGO_VER ..."
    fi

    ## Run tests
    ##

    pushd "$REPO_DIR/api"

    use_node "$NODE_VER"
    yarn test

    ## Publish code coverage
    ##

    if [ "$CODE_COVERAGE" = true ]; then
        send_coverage_to_cc "$CC_TEST_REPORTER_ID" "api"
    fi

    popd
}

# Setup the workspace for a lib project.
# A lib project has no kli file, but require a 'development' repo.
# It can also depend on other repo but they must be specified as additional args
# Expected args:
# 1. the workspace directory
# 2. the url of the 'development' repository
# ... additional repo url to pull. Those additional repository will be cloned in the
# workspace directory, using the basename of the repo url as repo directory.
setup_lib_workspace() {
    setup_workspace $@
}

# Gather information about a library
# Defines LIB_INFOS variable as an array. This array contains the lib name & the lib version
# Arg1: the repository root
# NOTE: the results should be extracted using get_lib_xxx functions below.
init_lib_infos() {
    ensure_yq

    local REPO_ROOT="$1"
    local LIB_NAME
    LIB_NAME=$(yq --output-format=yaml '.name' "$REPO_ROOT/package.json")
    local LIB_VERSION
    LIB_VERSION=$(yq --output-format=yaml '.version' "$REPO_ROOT/package.json")

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

# Extract lib tag from lib infos
# NOTE: requires a call to init_lib_infos first
get_lib_tag() {
    echo "${LIB_INFOS[2]}"
}

# Extract lib branch from lib infos
# NOTE: requires a call to init_lib_infos first
get_lib_branch() {
    echo "${LIB_INFOS[3]}"
}

# Run tests for a library module
# Expected arguments
# 1. Root directory
# 2. true to publish code coverage to code climate (CC_TEST_REPORTER_ID env var should be defined in this case)
# 3. node version to be used
# 4. mongo version to be used if required by tests
run_lib_tests () {
    local ROOT_DIR="$1"
    local CODE_COVERAGE="$2"
    local NODE_VER="$3"
    local MONGO_VER="$4"
    local WORKSPACE_DIR
    WORKSPACE_DIR="$(dirname "$ROOT_DIR")"

    init_lib_infos "$ROOT_DIR"

    local LIB
    LIB=$(get_lib_name)
    local VERSION
    VERSION=$(get_lib_version)
    local GIT_TAG
    GIT_TAG=$(get_lib_tag)

    echo "About to run tests for $LIB v$VERSION..."

    ## Start mongo
    ##

    if [ -n "$MONGO_VER" ]; then
        begin_group "Starting mongo $MONGO_VER ..."

        use_mongo "$MONGO_VER"
        k-mongo

        end_group "Starting mongo $MONGO_VER ..."
    fi

    ## Run tests
    ##

    use_node "$NODE_VER"
    yarn && yarn test

    ## Publish code coverage
    ##

    if [ "$CODE_COVERAGE" = true ]; then
        send_coverage_to_cc "$CC_TEST_REPORTER_ID"
    fi
}

# Setup the workspace for a krawler job project.
# Cf. setup_lib_workspace
setup_job_workspace() {
    setup_workspace $@
}

# Gather information about a job
# Defines JOB_INFOS variable as an array. This array contains the job name & the job version along with the krawler version
# Arg1: the repository root
# NOTE: the results should be extracted using get_job_xxx functions below.
init_job_infos() {
    ensure_yq

    local REPO_ROOT="$1"
    local JOB_NAME
    JOB_NAME=$(yq --output-format=yaml '.name' "$REPO_ROOT/package.json")
    local JOB_VERSION
    JOB_VERSION=$(yq --output-format=yaml '.version' "$REPO_ROOT/package.json")
    local KRAWLER_VERSION
    KRAWLER_VERSION=$(yq --output-format=yaml '.peerDependencies["@kalisio/krawler"]' "$REPO_ROOT/package.json")

    local GIT_TAG
    GIT_TAG=$(get_git_tag "$REPO_ROOT")
    local GIT_BRANCH
    GIT_BRANCH=$(get_git_branch "$REPO_ROOT")

    JOB_INFOS=("$JOB_NAME" "$JOB_VERSION" "$GIT_TAG" "$GIT_BRANCH" "$KRAWLER_VERSION")
}

# Extract job name from job infos
# NOTE: requires a call to init_job_infos first
get_job_name() {
    echo "${JOB_INFOS[0]}"
}

# Extract job version from job infos
# NOTE: requires a call to init_job_infos first
get_job_version() {
    echo "${JOB_INFOS[1]}"
}

# Extract job tag from job infos
# NOTE: requires a call to init_job_infos first
get_job_tag() {
    echo "${JOB_INFOS[2]}"
}

# Extract job branch from job infos
# NOTE: requires a call to init_job_infos first
get_job_branch() {
    echo "${JOB_INFOS[3]}"
}

# Extract krawler version from job infos
# NOTE: requires a call to init_job_infos first
get_job_krawler_version() {
    echo "${JOB_INFOS[4]}"
}

# Build a krawler job container.
# Expected args
# 1. the job repository directory
# 2. the prefix to use before the image name (ie. kalisio, some_other_namespace, ...)
# 3. the job variant to build (or empty if no variant)
# 4. the registry url where to push the built container
# 5. the registry username to use
# 6. the file containing the registry password
# 7. true to push the built container on the registry
build_job() {
    local REPO_DIR="$1"
    local IMAGE_PREFIX="$2"
    local JOB_VARIANT="$3"
    local REGISTRY_URL="$4"
    local REGISTRY_USERNAME="$5"
    local REGISTRY_PASSWORD_FILE="$6"
    local PUBLISH="$7"

    ## Init workspace
    ##

    init_job_infos "$REPO_DIR"

    local JOB
    JOB=$(get_job_name)
    local VERSION
    VERSION=$(get_job_version)
    local KRAWLER_VERSION
    KRAWLER_VERSION=$(get_job_krawler_version)
    local GIT_TAG
    GIT_TAG=$(get_job_tag)

    if [ -z "$GIT_TAG" ]; then
        echo "About to build $JOB development version based on krawler development version..."
    else
        echo "About to build $JOB v$VERSION based on krawler $KRAWLER_VERSION..."
    fi

    ## Build container
    ##

    local DOCKERFILE="dockerfile"
    local IMAGE_NAME="$REGISTRY_URL/$IMAGE_PREFIX/$JOB"
    local IMAGE_TAG="latest"
    local KRAWLER_TAG="latest"

    # If building from a tag, make a tagged image and use specified krawler
    if [ -n "$GIT_TAG" ]; then
        IMAGE_TAG="$VERSION"
        KRAWLER_TAG="$KRAWLER_VERSION"
    fi

    # In case of job variant, update image name and source dockerfile
    if [ -n "$JOB_VARIANT" ]; then
        IMAGE_TAG="$JOB_VARIANT-$IMAGE_TAG"
        DOCKERFILE="$DOCKERFILE.$JOB_VARIANT"
    fi

    begin_group "Building $IMAGE_NAME:$IMAGE_TAG ..."

    docker login --username "$REGISTRY_USERNAME" --password-stdin "$REGISTRY_URL" < "$REGISTRY_PASSWORD_FILE"
    # DOCKER_BUILDKIT is here to be able to use Dockerfile specific dockerginore (job.Dockerfile.dockerignore)
    DOCKER_BUILDKIT=1 docker build \
        --build-arg KRAWLER_TAG="$KRAWLER_TAG" \
        -f "$DOCKERFILE" \
        -t "$IMAGE_NAME:$IMAGE_TAG" \
        "$REPO_DIR"

    if [ "$PUBLISH" = true ]; then
        docker push "$IMAGE_NAME:$IMAGE_TAG"
    fi

    docker logout "$REGISTRY_URL"

    end_group "Building $IMAGE_NAME:$IMAGE_TAG ..."
}

# Build vitepress docs and possibly publish it on github pages
# Expected arguments
# 1. Root directory
# 2. Repository name like kalisio/krawler
# 3. true to publish result on github pages
build_docs () {
    local ROOT_DIR="$1"
    local REPOSITORY="$2"
    local PUBLISH="$3"
    local WORKSPACE_DIR
    WORKSPACE_DIR="$(dirname "$ROOT_DIR")"
    local ORGANISATION="$(dirname $REPOSITORY)"

    begin_group "Building docs for $REPOSITORY ..."

    # Build process requires node 18
    use_node 18

    rm -f .postcssrc.js && cd docs && yarn install && yarn build

    if [ "$PUBLISH" = true ]; then
        # Extract organisation from token and get load corresponding env (filename is uppercase)
        load_env_files "$WORKSPACE_DIR/development/common/${ORGANISATION^^}_GH_PAGES_PUSH_TOKEN.enc.env"

        local COMMIT_SHA
        COMMIT_SHA=$(get_git_commit_sha "$ROOT_DIR")
        local COMMIT_AUTHOR_NAME
        COMMIT_AUTHOR_NAME=$(get_git_commit_author_name "$ROOT_DIR")
        local COMMIT_AUTHOR_EMAIL
        COMMIT_AUTHOR_EMAIL=$(get_git_commit_author_email "$ROOT_DIR")
        deploy_gh_pages \
            "https://oauth2:$GH_PAGES_PUSH_TOKEN@github.com/$REPOSITORY.git" \
            "$ROOT_DIR/docs/.vitepress/dist" \
            "$COMMIT_AUTHOR_NAME" \
            "$COMMIT_AUTHOR_EMAIL" \
            "Docs built from $COMMIT_SHA"
    fi

    end_group "Building docs for $REPOSITORY ..."
}

# Build e2e tests
# Expected arguments
# 1. Root directory
# 2: true to publish result on harbor
build_e2e_tests () {
    local ROOT_DIR="$1"
    local PUBLISH="$2"

    ## Init workspace
    ##

    local WORKSPACE_DIR
    WORKSPACE_DIR="$(dirname "$ROOT_DIR")"
    init_app_infos "$ROOT_DIR" "$WORKSPACE_DIR/development/workspaces/apps"

    local APP
    APP=$(get_app_name)
    local VERSION
    VERSION=$(get_app_version)
    local FLAVOR
    FLAVOR=$(get_app_flavor)

    echo "About to build ${APP} v${VERSION}-$FLAVOR ..."

    load_env_files "$WORKSPACE_DIR/development/common/kalisio_harbor.enc.env"
    load_value_files "$WORKSPACE_DIR/development/common/KALISIO_HARBOR_PASSWORD.enc.value"

    ## Build container
    ##

    local IMAGE_NAME="$KALISIO_HARBOR_URL/kalisio/$APP-e2e-tests"
    local IMAGE_TAG="$VERSION-$FLAVOR"

    begin_group "Building container ..."

    docker login --username "$KALISIO_HARBOR_USERNAME" --password-stdin "$KALISIO_HARBOR_URL" < "$KALISIO_HARBOR_PASSWORD"
    # DOCKER_BUILDKIT is here to be able to use Dockerfile specific dockerginore (e2e-tests.Dockerfile.dockerignore)
    DOCKER_BUILDKIT=1 docker build \
        --build-arg APP="$APP" \
        --build-arg NODE_APP_INSTANCE="$FLAVOR" \
        --build-arg SUBDOMAIN="$FLAVOR.kalisio.xyz" \
        --build-arg HEADLESS=true \
        -f "$ROOT_DIR/e2e-tests.Dockerfile" \
        -t "$IMAGE_NAME:$IMAGE_TAG" \
        "$WORKSPACE_DIR"
    docker tag "$IMAGE_NAME:$IMAGE_TAG" "$IMAGE_NAME:$FLAVOR"

    if [ "$PUBLISH" = true ]; then
        docker push "$IMAGE_NAME:$IMAGE_TAG"
        docker push "$IMAGE_NAME:$FLAVOR"
    fi

    docker logout "$KALISIO_HARBOR_URL"

    end_group "Building container ..."
}

# Run e2e tests
# Specific error handling: set -uo pipefail to bypass errors
# Expected arguments
# 1. Root directory
# 2: the app name
# 3: the slack webhook apps
run_e2e_tests () {
    local ROOT_DIR="$1"
    local APP="$2"
    local SLACK_WEBHOOK_APPS="$3"

    ## Run tests & redirect output to a log file
    ##

    # Chrome
    mkdir -p "$ROOT_DIR/test/run/chrome"
    yarn test:client > "$ROOT_DIR/test/run/chrome/chrome_logs.txt" 2>&1
    local RET_CODE=$?

    # Firefox
    # PUPPETEER_PRODUCT=firefox yarn add puppeteer
    # yarn link "@kalisio/kdk" --link-folder /opt/kalisio/yarn-links
    # export BROWSER="firefox"bucket
    # mkdir -p "$ROOT_DIR/test/run/firefox"
    # yarn test:client  > "$ROOT_DIR/test/run/chrome/firefox_logs.txt" 2>&1

    ## Upload logs & screenshots to S3
    ##

    local CURRENT_DATE
    CURRENT_DATE=$(date +"%d-%m-%Y")
    local CHROME_LOGS_LINK=""
    local SCREEN_LINK=""

    zip -r "$TMP_DIR/screenshots.zip" "$ROOT_DIR/test/run"

    rclone copy "$ROOT_DIR/test/run/chrome/chrome_logs.txt" "ovh-s3:/dev/e2e-tests/$APP/$CURRENT_DATE"
    CHROME_LOGS_LINK=$(rclone link "ovh-s3:/dev/e2e-tests/$APP/$CURRENT_DATE/chrome_logs.txt")

    rclone copy "$TMP_DIR/screenshots.zip" "ovh-s3:/dev/e2e-tests/$APP/$CURRENT_DATE"
    SCREEN_LINK=$(rclone link "ovh-s3:/dev/e2e-tests/$APP/$CURRENT_DATE/screenshots.zip")

    ## Report outcome to slack
    ##

    slack_e2e_report "$APP" "$RET_CODE" "$SLACK_WEBHOOK_APPS" "$CHROME_LOGS_LINK" "$SCREEN_LINK"
}
