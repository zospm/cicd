#!/bin/sh
#
# Set up environment variables and check secret env vars also set
#
export GIT_SERVER="github.com"
export GIT_OWNER="git"
export GIT_USER="zospm"
export REPO_LIST="zospm zhw git fek fel igy zwe eqa bgz huh"
export DEPLOY_SERVER="api.bintray.com"
export DEPLOY_USER="fultonm"
export DEPLOY_REPO_PREFIX="content/zospm/zospm/"
export DEPLOY_REPO_SUFFIX="/"
export BASE_SRC_ROOT="${HOME}/zospm-basesrc"
export BASE_BIN_ROOT="${HOME}/zospm-basebin"
export BUILD_ROOT="${HOME}/zospm-build"
export DEPLOY_ROOT="${HOME}/zospm-deploy"
export DOWNLOAD_ROOT="${HOME}/zospm-download"
export ZOSPM_ZOS240_CSI='MVS.GLOBAL.CSI'
export ZOSPM_CEE240_CSI='MVS.GLOBAL.CSI'
export ZOSPM_BUILD_HLQ='ZBRB'
export ZOSPM_BUILD_ZFSROOT='/zbrb'
export ZOSPM_BUILD_WORKROOT="${BUILD_ROOT}"
export ZOSPM_DOWNLOAD_HLQ='ZBRD'
export ZOSPM_DOWNLOAD_ZFSROOT='/zbrd'
export ZOSPM_DOWNLOAD_WORKROOT="${DOWNLOAD_ROOT}"
export BASE_SRC_WORKROOT="${HOME}/zospm-basesrc/work"
export BASE_BIN_WORKROOT="${HOME}/zospm-basebin/work"

if [ -z "${DEPLOY_API_KEY}" ]; then
        echo "Need to export DEPLOY_API_KEY to deploy to ${DEPLOY_SERVER}" >&2
	exit 8
fi
if [ -z "${SLACK_MSG_URL}" ]; then
        echo "Need to export SLACK_MSG_URL to deploy to ${DEPLOY_SERVER}" >&2
	exit 8
fi

if ! [ -d "${BASE_SRC_ROOT}" ]; then
        echo "Need to have a base source version of zospm" >&2
	exit 8
fi

if ! [ -d "${BASE_BIN_ROOT}" ]; then
        echo "Need to have a base binary version of zospm" >&2
	exit 8
fi

mkdir -p "${BUILD_ROOT}"
mkdir -p "${DEPLOY_ROOT}"

export BASE_PATH=".:/usr/bin:/bin:/usr/sbin:/rsusr/zoau/bin:/rsusr/ported/bin:/rsusr/rocket/bin"
