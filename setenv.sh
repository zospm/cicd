#!/bin/sh
#
# Set up environment variables and check secret env vars also set
#
export GIT_SERVER="github.com"
export GIT_OWNER="git"
export GIT_USER="zospm"
export REPO_LIST="zospm zospm-zhw zospm-eqa zospm-igy zospm-bgz zospm-fek zospm-git zospm-fel zospm-huh zospm-zwe"
export DEPLOY_SERVER="api.bintray.com"
export DEPLOY_USER="fultonm"
export DEPLOY_REPO_PREFIX="content/zospm/zospm/"
export DEPLOY_REPO_SUFFIX="/"
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

if [ -z "${DEPLOY_API_KEY}" ]; then
        echo "Need to export DEPLOY_API_KEY to deploy to ${DEPLOY_SERVER}"
fi
if [ -z "${SLACK_MSG_URL}" ]; then
        echo "Need to export SLACK_MSG_URL to deploy to ${DEPLOY_SERVER}"
fi

mkdir -p "${BUILD_ROOT}"
mkdir -p "${DEPLOY_ROOT}"

export BASE_PATH=".:/usr/bin:/bin:/usr/sbin:/rsusr/zoau/bin:/rsusr/ported/bin:/rsusr/rocket/bin"
