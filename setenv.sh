#!/bin/sh
#
# Set up environment variables and check secret env vars also set
#
export GIT_SERVER="github.ibm.com"
export GIT_OWNER="git"
export REPO_LIST="zbrew zbrew-zhw zbrew-eqa zbrew-igy zbrew-bgz"
export DEPLOY_SERVER="na.artifactory.swg-devops.com"
export DEPLOY_REPO_PREFIX="artifactory/zbrew-"
export DEPLOY_REPO_SUFFIX="-generic-local/"
export DEPLOY_USER="fultonm"
export BUILD_ROOT="${HOME}/zbrew-build
export DEPLOY_ROOT="${HOME}/zbrew-deploy
if [ -z "${DEPLOY_API_KEY}" ]; then
        echo "Need to export DEPLOY_API_KEY to deploy to ${DEPLOY_SERVER}"
fi
if [ -z "${SLACK_MSG_URL}" ]; then
        echo "Need to export SLACK_MSG_URL_MVSCOMMAND to deploy to ${DEPLOY_SERVER}"
fi

export PATH=${BUILD_ROOT}/zbrew/bin:$PATH
