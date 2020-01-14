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
		git clone "${GIT_OWNER}@${GIT_SERVER}:IBMZSoftware/${repo}.git" >"${repo}_gitclone.results" 2>&1
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
	git pull "${GIT_OWNER}@${GIT_SERVER}:IBMZSoftware/${repo}.git" >"gitpull.results" 2>&1
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
		artifact_url="https://na.artifactory.swg-devops.com/artifactory/webapp/#/artifacts/browse/tree/General/sys-mvsutils-${repo}-generic-local"
		rm -f ${out}
		paxfile="${repo}_${timestamp}.pax"
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
		curl -k -T "${DEPLOY_ROOT}/${paxfile}" -H "X-JFrog-Art-Api:${DEPLOY_API_KEY}" "https://${urldir}/${paxfile}" >>${out} 2>&1
		rc=$?
		if [ ${rc} -gt 0 ]; then
			echo "Unable to transfer pax file: ${DEPLOY_ROOT}/${paxfile} to: ${urldir}/${paxfile}" >>${out}
			return ${rc}
		fi
		curl -k -X POST -H "X-JFrog-Art-Api:${DEPLOY_API_KEY}" "https://${urldir}/publish" >>${out} 2>&1
		rc=$?
		if [ ${rc} -gt 0 ]; then
			echo "Unable to publish pax file: ${urldir}/${paxfile}" >>${out}
			return ${rc}
		fi
		StepMsg "PASS" "Repository ${repo} deploy git commit hash: ${hash} as ${artifact_url}/${timestamp}/${repo}_${timestamp}.pax " "${repo}" "${rc}" "${out}" "${log}" 1

	fi
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
				hash=`git ls-remote -q "${GIT_OWNER}@${GIT_SERVER}:IBMZSoftware/${r}"  | awk ' { if ($2 == "HEAD") { print $1; }}'`
				echo "Build repository: ${r} (${hash})"
				SlackMsg "${r}" "0" "Build started for git repository: ${r}" "" "${log}"         
				status=`RepoBuild ${r}`
				if [ "${status}" = "PASS" ]; then
					status=`RepoTest ${r}`
					if [ ${status} = "PASS" ]; then
						echo "Repository ${r} test passed"
						status=`RepoDeploy ${r} ${timestamp} ${hash}`
						if [ "${status}" = "PASS" ]; then
							echo "Repository ${r} deployment passed"
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
