#!/bin/sh
. ./setenv.sh
#set -x

verbose=false

function SlackMsg {
	msg=$1

	url="${SLACK_MSG_URL}"
	curl -ks -X POST -H "'Content-type: application/json'" --data "{\"text\":\"${msg}\"}" "${url}" >/dev/null 2>&1
	rc=$?
	if [ $rc -gt 0 ]; then
		echo "curl failed to post message to slack url: ${url}" >&2
	fi

	return 0
}

function RepoStatus {
	repo=$1
	gitout=gitfetch${repo}.out
	if [ -d .git ]; then
		git fetch >"${gitout}" 2>&1
		if [ $? -eq 0 ]; then
			rm -f ${gitout}
		fi
		REMOTE=`git rev-parse @{u}`
		LOCAL=`git rev-parse HEAD`

		if [ $LOCAL = $REMOTE ]; then
		    echo "CURRENT"
		else
		    echo "PULL"
		fi
	else 
		cd ../
		git clone "${GIT_OWNER}@${GIT_SERVER}:${GIT_USER}/${repo}.git" >"${gitout}" 2>&1
		if [ $? -eq 0 ]; then
			rm -f ${gitout}
		fi
		cd ${repo}
		echo "PULL"
	fi
	return 0
}

function RepoBuild {
	repo=$1
	gitout=gitpull.out
	out="RepoBuild.results"

	if ${verbose}; then
		SlackMsg "RepoBuild ${repo}"
	fi
	git pull "${GIT_OWNER}@${GIT_SERVER}:${GIT_USER}/${repo}.git" >"${gitout}" 2>&1
	rc=$?
	if [ ${rc} -ne 0 ]; then
		echo "RepoBuild: git pull ${repo} failed with rc:$rc"
		return ${rc}
	else
		rm -f "${gitout}"
	fi

	./build.sh >${out} 2>&1
	rc=$?
	if [ ${rc} -ne 0 ]; then
		echo "RepoBuild: ${repo} build failed with rc:$rc"
	fi
	return $rc
}

function RepoTest {
	repo=$1
	out="RepoTest.results"

	if ${verbose}; then
		SlackMsg "RepoTest ${repo}"
	fi
	./test.sh >${out} 2>&1
	rc=$?
	if [ ${rc} -ne 0 ]; then
		echo "RepoTest: ${repo} test failed with rc: $rc"
	else
		rm -f ${out}
	fi
	return $rc
}

function RepoDeploy {
	repo=$1
	timestamp=$2
	hash=$3
	paxfile=$4
	artifact_url=$5

	if ${verbose}; then
		SlackMsg "RepoDeploy ${repo}"
	fi
	out="RepoDeploy.results"
	curlout="curl.out"
	rm -rf "${DEPLOY_ROOT}/${repo}"

	mkdir -p "${DEPLOY_ROOT}/${repo}"
	rc=$?
	if [ ${rc} -gt 0 ]; then
		echo "RepoDeploy: Unable to create deploy directory: ${DEPLOY_ROOT}/${repo}. rc:$rc"
		return ${rc}
	fi
	./deploy.sh "${DEPLOY_ROOT}/${repo}" >${out} 2>&1
	rc=$?
	if [ ${rc} -ne 0 ]; then
		echo "RepoDeploy: ${repo} deploy failed with rc:${rc}"
		return ${rc}
	else
		rm -f ${out}
	fi 

	paxout="${DEPLOY_ROOT}/${repo}_pax.out"
	( 
	cd "${DEPLOY_ROOT}/${repo}"; 
	files=`ls -A`
	pax -x pax -wvf "${DEPLOY_ROOT}/${paxfile}" ${files} >"${paxout}" 2>&1
	)
	rc=$?
	if [ ${rc} -gt 0 ]; then
		echo "RepoDeploy: Unable to create pax file: ${DEPLOY_ROOT}/${paxfile}. rc:$rc" 
		return ${rc}
	else 
		rm -f "${paxout}"	
	fi

	# Tagging binary is required so the file is not autoconverted on curl transfer
	chtag -b "${DEPLOY_ROOT}/${paxfile}" 
	urldir="${DEPLOY_SERVER}/${DEPLOY_REPO_PREFIX}${repo}${DEPLOY_REPO_SUFFIX}${timestamp}"

	if ${verbose}; then
		SlackMsg "RepoDeploy: curl -I -s -k -T ${DEPLOY_ROOT}/${paxfile} -u${DEPLOY_USER}:${DEPLOY_API_KEY} -H X-JFrog-Art-Api:${DEPLOY_API_KEY} https://${urldir}/${paxfile}"
	fi

	curl -I -s -k -T "${DEPLOY_ROOT}/${paxfile}" -u${DEPLOY_USER}:${DEPLOY_API_KEY} -H "X-JFrog-Art-Api:${DEPLOY_API_KEY}" "https://${urldir}/${paxfile}" >${curlout} 2>&1
	rc=$?
	if [ ${rc} -gt 0 ]; then
		echo "RepoDeploy: Unable to transfer pax file: ${DEPLOY_ROOT}/${paxfile} to: ${urldir}/${paxfile}. rc:$rc"
		return ${rc}
	else
		grep "HTTP/1.1" ${curlout} | grep -q '201'
		rc=$?
		if [ ${rc} -gt 0 ]; then
			echo "RepoDeploy: Unexpected HTTP Error Uploading pax file to ${urldir}/${paxfile}."    
			return $rc
		else
			rm -f ${DEPLOY_ROOT}/${paxfile}
			rm -f "${curlout}"
		fi
	fi

	curl -I -s -k -X POST -u${DEPLOY_USER}:${DEPLOY_API_KEY} -H "X-JFrog-Art-Api:${DEPLOY_API_KEY}" "https://${urldir}/publish" >${curlout} 2>&1
	rc=$?
	if [ ${rc} -gt 0 ]; then
		echo "RepoDeploy: Unable to publish pax file: ${urldir}/${paxfile}"
		return ${rc}
	else
		grep "HTTP/1.1" ${curlout} | grep -q '200'
		rc=$?
		if [ ${rc} -gt 0 ]; then
			echo "RepoDeploy: Unexpected HTTP Error publishing pax file to ${urldir}/${paxfile}."   	
			return $rc
		else	
			rm -f "${curlout}"
		fi
	fi
	return 0
}

function RepoDownload {
	repo=$1
        paxfile=$2
 	artifact_url=$3

	curlout="curl.out"
	paxout="pax.out"
	out="RepoDownload.out"
	
	if ${verbose}; then
		SlackMsg "RepoDownload ${repo}"
	fi
	rm -rf "${DOWNLOAD_ROOT}/${repo}"
        mkdir -p "${DOWNLOAD_ROOT}/${repo}"
	rc=$?
        if [ ${rc} -gt 0 ]; then
	        echo "RepoDownload: Unable to create deploy directory: ${DOWNLOAD_ROOT}/${repo}. rc:$rc"
	        return ${rc}
	fi
	cd "${DOWNLOAD_ROOT}/${repo}"
	curl -ks -u${DEPLOY_USER}:${DEPLOY_API_KEY} ${artifact_url} -o ${paxfile} >${curlout} 2>&1
	rc=$?
        if [ ${rc} -gt 0 ]; then
	        echo "RepoDownload: Unable to download: ${DOWNLOAD_ROOT}/${repo}/${paxfile}"
	        return ${rc}
	else
		rm -f "${curlout}"
	fi
	pax -rf ${paxfile} >${paxout} 2>&1
	rc=$?
        if [ ${rc} -gt 0 ]; then
	        echo "RepoDownload: Unable to unpax: ${DOWNLOAD_ROOT}/${repo}/${paxfile}. rc:$rc"
	        return ${rc}
	else
		rm -f "${paxout}"
	fi
	DOWNLOAD_ZBREW="../zbrew/bin/zbrew"
	if [ "${repo}" = "zbrew" ]; then
		return 0
	else
		if [ -f ${DOWNLOAD_ZBREW} ]; then
			suffix=${repo##*-} 
			prods=`${DOWNLOAD_ZBREW} search ${suffix} | awk '{ print $1; }'`
			# msf - hack...
			export CEE240_CSI='MVS.GLOBAL.CSI'
			export ZBREW_HLQ='ZBRDL.'
			export ZFSROOT='/zbrdl/'

			for prod in ${prods}; do
				if ${verbose}; then
					SlackMsg "uninstall, install, configure ${prod}"
				fi
				# remove previous download builds
				${DOWNLOAD_ZBREW} uninstall ${prod} >"${out}" 2>&1
				if [ $rc -gt 0 ]; then
					echo "RepoDownload: Failed to uninstall ${prod} from download. rc:$rc" 
					return $rc
				fi
				${DOWNLOAD_ZBREW} install ${prod} >"${out}" 2>&1
				if [ $rc -gt 0 ]; then
					echo "RepoDownload: Failed to install ${prod} from download. rc:$rc"
					return $rc
				fi
				${DOWNLOAD_ZBREW} configure ${prod} >"${out}" 2>&1
				if [ $rc -gt 0 ]; then
					echo "RepoDownload: Failed to configure ${prod} from download. rc:$rc" 
					return $rc
				fi
			done
			rm -f "${out}"
		fi
	fi
	return 0
}

#
# Start of mainline 'loop forever'
#
first=true
while true; do 
	
	if $first; then     
		first=false
	else
		sleep 5m
	fi

	mkdir -p "${BUILD_ROOT}"
	rc=$?
	if [ ${rc} -gt 0 ]; then
		echo "Unable to create build root directory: ${BUILD_ROOT}"
		exit ${rc}
	fi
	mkdir -p "${DEPLOY_ROOT}"
	rc=$?
	if [ ${rc} -gt 0 ]; then
		echo "Unable to create deploy root directory: ${DEPLOY_ROOT}"
		exit ${rc}
	fi

	cd "${BUILD_ROOT}"
	timestamp=`date '+%Y%m%d%H%M'`
	
	for r in ${REPO_LIST}; do
		mkdir -p "${BUILD_ROOT}/${r}"
		rc=$?
		if [ ${rc} -gt 0 ]; then
			echo "Unable to	create repository directory: ${BUILD_ROOT}/${r}"
			exit ${rc}
		fi
		cd "${BUILD_ROOT}/${r}"
		status=`RepoStatus ${r}`
	
		log="cicd.log"
		if [ ${status} = "CURRENT" ]; then
			continue
		fi
		if [ ${status} != "PULL" ]; then 
			echo "Repository ${r} is out of sync. Investigate!"
			continue
		fi
		hash=`git ls-remote -q "${GIT_OWNER}@${GIT_SERVER}:${GIT_USER}/${r}"  | awk ' { if ($2 == "HEAD") { print $1; }}'`
		echo "Build repository: ${r} (${hash})"
		SlackMsg "Build started for git repository: ${r}"

		status=`RepoBuild ${r}`
		rc=$?
		if [ $rc -gt 0 ]; then
			SlackMsg "${status}"
			continue
		fi
		
		status=`RepoTest ${r}`
		rc=$?
		if [ $rc -gt 0 ]; then
			SlackMsg "${status}"
			continue
		fi

		paxfile="${r}_${timestamp}.pax"
		artifact_url="https://dl.bintray.com/zbrew/zbrew/${paxfile}"
		status=`RepoDeploy ${r} ${timestamp} ${hash} ${paxfile} ${artifact_url}`
		rc=$?
		if [ $rc -gt 0 ]; then
			SlackMsg "${status}"
			continue
		fi

		status=`RepoDownload ${r} ${paxfile} ${artifact_url}`
		rc=$?
		if [ $rc -gt 0 ]; then
			SlackMsg "${status}"
		else
			SlackMsg "Build, test, deploy, download of ${r} passed. Code deployed to: ${artifact_url}"
		fi
	done
done
