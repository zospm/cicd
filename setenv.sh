#!/bin/sh
#
# Set up environment variables and check secret env vars also set
#
export GIT_SERVER="github.com"
export GIT_OWNER="git"
export GIT_USER="zbrewdev"
export REPO_LIST="zbrew zbrew-zhw zbrew-eqa zbrew-igy zbrew-bgz zbrew-fek"
export DEPLOY_SERVER="api.bintray.com"
export DEPLOY_USER="fultonm"
export DEPLOY_REPO_PREFIX="content/zbrew/zbrew/"
export DEPLOY_REPO_SUFFIX="/"
export BUILD_ROOT="${HOME}/zbrew-build"
export DEPLOY_ROOT="${HOME}/zbrew-deploy"
export DOWNLOAD_ROOT="${HOME}/zbrew-download"
export ZBREW_ZOS240_CSI='MVS.GLOBAL.CSI'
export ZBREW_CEE240_CSI='MVS.GLOBAL.CSI'
export ZBREW_HLQ='ZBRDL.'
export ZBREW_ZFSROOT='/zbrdl/'

if [ -z "${DEPLOY_API_KEY}" ]; then
        echo "Need to export DEPLOY_API_KEY to deploy to ${DEPLOY_SERVER}"
fi
if [ -z "${SLACK_MSG_URL}" ]; then
        echo "Need to export SLACK_MSG_URL to deploy to ${DEPLOY_SERVER}"
fi

mkdir -p "${BUILD_ROOT}"
mkdir -p "${DEPLOY_ROOT}"

export BASE_PATH=".:/usr/bin:/bin:/usr/sbin:/rsusr/zoau/bin:/rsusr/ported/bin:/rsusr/rocket/bin"
export PATH="${BUILD_ROOT}/zbrew/bin:${BASE_PATH}"
