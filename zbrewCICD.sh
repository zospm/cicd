#!/bin/sh
. ./setenv.sh
#set -x

verbose=0

function SlackMsg {
	repo=$1
	rc=$2
	msg=$3
	file=$4
	log=$5

	url="${SLACK_MSG_URL}"
	rm -f "${log}"
	curl -k -X POST -H "'Content-type: application/json'" --data "{\"text\":\"${msg}\"}" "${url}" >${log} 2>&1

	return 0
}

function RepoStatus {
	repo=$1
	if [ -d .git ]; then
		git fetch >"${repo}_gitfetch.results" 2>&1
		REMOTE=`git rev-parse @{u}`
		LOCAL=`git rev-parse HEAD`

		if [ $LOCAL = $REMOTE ]; then
		    echo "CURRENT"
		else
		    echo "PULL"
		fi
	else 
		cd ../
		git clone "${GIT_OWNER}@${GIT_SERVER}:${GIT_USER}/${repo}.git" >"${repo}_gitclone.results" 2>&1
		cd ${repo}
		echo "PULL"
	fi
	return 0
}

function StepMsg {
	status=$1
	step=$2
        repo=$3
	rc=$4
	file=$5
	log=$6
	slack=$7

	if [ ${slack} -gt 0 ]; then 
		SlackMsg "${repo}" "${rc}" "${step} ${status} with rc: ${rc}" "${file}" "${log}"
	fi
	echo "${status}"
}

function RepoBuild {
	repo=$1
	out="RepoBuild.results"
	log="build.log"
	rm -f ${out}
	touch ${out}
	git pull "${GIT_OWNER}@${GIT_SERVER}:${GIT_USER}/${repo}.git" >"gitpull.results" 2>&1
	rc=$?
	if [ ${rc} -ne 0 ]; then
		echo "FAIL"
		return ${rc}
	fi
	./build.sh >>${out} 2>&1
	rc=$?
	if [ ${rc} -ne 0 ]; then
		StepMsg "FAIL" "Repository Build" "${repo}" "${rc}" "${out}" "${log}" 1
	else 
		StepMsg "PASS" "Repository Build" "${repo}" "${rc}" "${out}" "${log}" ${verbose}
	fi
	return 0
}


function RepoTest {
	repo=$1
	out="RepoTest.results"
	log="curl_test.log"
	rm -f ${out}
	touch ${out}
	./test.sh >${out} 2>&1
	rc=$?
	if [ ${rc} -ne 0 ]; then
		StepMsg "FAIL" "Repository Test" "${repo}" "${rc}" "${out}" "${log}" 1
	else 
		StepMsg "PASS" "Repository Test" "${repo}" "${rc}" "${out}" "${log}" ${verbose}
	fi
	return 0
}

function RepoDeploy {
	out="RepoDeploy.results"
	log="curl_deploy.log"
	rm -f ${out}
	touch ${out}
	repo=$1
	timestamp=$2
	hash=$3
	paxfile=$4
	artifact_url=$5
	rm -rf "${DEPLOY_ROOT}/${repo}"
	mkdir -p "${DEPLOY_ROOT}/${repo}"
	rc=$?
	if [ ${rc} -gt 0 ]; then
		echo "Unable to create deploy directory: ${DEPLOY_ROOT}/${repo}" >>${out}
		return ${rc}
	fi
	./deploy.sh "${DEPLOY_ROOT}/${repo}" >>${out} 2>&1
	rc=$?
	if [ ${rc} -ne 0 ]; then
		StepMsg "FAIL" "Repository Deploy" "${repo}" "${rc}" "${out}" "${log}" 1
	else 
		rm -f ${out}
		( 
		cd "${DEPLOY_ROOT}/${repo}"; 
		files=`ls -A`
		pax -x pax -wvf "${DEPLOY_ROOT}/${paxfile}" ${files} >"../${repo}pax.out" 2>&1
		)
		rc=$?
		if [ ${rc} -gt 0 ]; then
			echo "Unable to create pax file: ${DEPLOY_ROOT}/${paxfile}" >>${out}
			return ${rc}
		fi
		# Tagging binary is required so the file is not autoconverted on curl transfer
		chtag -b "${DEPLOY_ROOT}/${paxfile}" 
		urldir="${DEPLOY_SERVER}/${DEPLOY_REPO_PREFIX}${repo}${DEPLOY_REPO_SUFFIX}/${timestamp}"
		curl -k -T "${DEPLOY_ROOT}/${paxfile}" -u${DEPLOY_USER}:${DEPLOY_API_KEY} -H "X-JFrog-Art-Api:${DEPLOY_API_KEY}" "https://${urldir}/${paxfile}" >>${out} 2>&1
		rc=$?
		if [ ${rc} -gt 0 ]; then
			echo "Unable to transfer pax file: ${DEPLOY_ROOT}/${paxfile} to: ${urldir}/${paxfile}" >>${out}
			return ${rc}
		fi
		curl -k -X POST -u${DEPLOY_USER}:${DEPLOY_API_KEY} -H "X-JFrog-Art-Api:${DEPLOY_API_KEY}" "https://${urldir}/publish" >>${out} 2>&1
		rc=$?
		if [ ${rc} -gt 0 ]; then
			echo "Unable to publish pax file: ${urldir}/${paxfile}" >>${out}
			return ${rc}
		fi
		StepMsg "PASS" "Repository ${repo} deploy git commit hash: ${hash} as ${artifact_url} " "${repo}" "${rc}" "${out}" "${log}" 1
	fi
	return 0
}

function RepoDownload {
	out="RepoDownload.results"
	log="curl_download.log"
	rm -f ${out}
	touch ${out}
	repo=$1
        paxfile=$2
 	artifact_url=$3
	rm -rf "${DOWNLOAD_ROOT}/${repo}"
        mkdir -p "${DOWNLOAD_ROOT}/${repo}"
	rc=$?
        if [ ${rc} -gt 0 ]; then
	        echo "Unable to create deploy directory: ${DOWNLOAD_ROOT}/${repo}" >>${out}
	        return ${rc}
	fi
	cd "${DOWNLOAD_ROOT}/${repo}"
	curl -k -u${DEPLOY_USER}:${DEPLOY_API_KEY} ${artifact_url} -o ${paxfile} >${log} 2>&1
	rc=$?
        if [ ${rc} -gt 0 ]; then
	        echo "Unable to download : ${DOWNLOAD_ROOT}/${repo}/${paxfile}" >>${out}
	        return ${rc}
	fi
	pax -rf ${paxfile} >>${out}
	rc=$?
        if [ ${rc} -gt 0 ]; then
	        echo "Unable to unpax : ${DOWNLOAD_ROOT}/${repo}/${paxfile}" >>${out}
	        return ${rc}
	fi
	DOWNLOAD_ZBREW="../zbrew/bin/zbrew"
	if [ "${repo}" = "zbrew" ]; then
		echo "Warning: zbrew itself is not tested directly in download testing" >>${out}
		StepMsg "PASS" "Download Test" "${repo}" "${rc}" "${out}" "${log}" ${verbose}
		return 0
	else
		if [ -f ${DOWNLOAD_ZBREW} ]; then
			suffix=${repo##*-} 
			prods=`${DOWNLOAD_ZBREW} search ${suffix} | awk '{ print $1; }'`
			# msf - hack...
			export CEE240_CSI='MVS.GLOBAL.CSI'
			export ZBREW_HLQ='ZBRDL.'
			export ZFSROOT='/zbrdl/'

			# forcibly remove previous builds
			zfs=`df | grep ${ZFSROOT} | sort -r | awk ' { print $1; }'` 
			for z in $zfs; do
				unmount  $z
			done
			drm -f "${ZBREW_HLQ}*"
			for prod in ${prods}; do
				${DOWNLOAD_ZBREW} install ${prod}
				if [ $rc -gt 0 ]; then
					echo "Failed to install ${prod} from download" >>${out}
					return $rc
				fi
				${DOWNLOAD_ZBREW} configure ${prod}
				if [ $rc -gt 0 ]; then
					echo "Failed to configure ${prod} from download" >>${out}
					return $rc
				fi
			done
		else
			echo "Warning... zbrew does not exist yet so download testing skipped for ${repo}" >>${out}
		fi
	fi
	StepMsg "PASS" "Download Test" "${repo}" "${rc}" "${out}" "${log}" ${verbose}
	return 0

}

#
# Start of mainline 'loop forever'
#
while true; do 
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
		mkdir -p "${r}"
		rc=$?
		if [ ${rc} -gt 0 ]; then
			echo "Unable to	create repository directory: ${BUILD_ROOT}/${r}"
			exit ${rc}
		fi
		cd ${r}
		status=`RepoStatus ${r}`
	
		log="curl_build.log"
		if [ ${status} = "CURRENT" ]; then
			if [ ${verbose} -eq 1 ]; then
				echo "Repository: ${r} current";
			fi
		else
			if [ ${status} = "PULL" ]; then 
				hash=`git ls-remote -q "${GIT_OWNER}@${GIT_SERVER}:${GIT_USER}/${r}"  | awk ' { if ($2 == "HEAD") { print $1; }}'`
				echo "Build repository: ${r} (${hash})"
				SlackMsg "${r}" "0" "Build started for git repository: ${r}" "" "${log}"         
				status=`RepoBuild ${r}`
				if [ "${status}" = "PASS" ]; then
					status=`RepoTest ${r}`
					if [ ${status} = "PASS" ]; then
						echo "Repository ${r} test passed"
						paxfile="${repo}_${timestamp}.pax"
						artifact_url="https://dl.bintray.com/fultonm/zbrew/${paxfile}"
						status=`RepoDeploy ${r} ${timestamp} ${hash} ${paxfile} ${artifact_url}`
						if [ "${status}" = "PASS" ]; then
							echo "Repository ${r} deployment passed"
							status=`RepoDownload ${r} ${paxfile} ${artifact_url}`
							if [ "${status}" = "PASS" ]; then
								echo "Download of ${r} test passed"
							else
								echo "Download of ${r} test failed"
							fi
					
						else
							echo "Repository ${r} deployment failed"
						fi
					else 
						echo "Repository ${r} test failed"
					fi
				else 
					echo "Build of repository: ${r} failed"
				fi
			else 
				echo "Repository ${r} is out of sync. Investigate!"
			fi
		fi
		cd ../
	done
	sleep 5m
done
