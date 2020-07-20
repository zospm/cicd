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
	sw=$1
	repo=$2
	gitout=gitrefresh.$sw.out
	giterr=gitrefresh.$sw.err
 	if ! [ -d ${repo}/.git ]; then
 		git clone "${GIT_OWNER}@${GIT_SERVER}:${GIT_USER}/${repo}.git" >"${gitout}" 2>&1
		rc=$?
		if [ $rc -gt 0 ]; then
			cat ${gitout} >&2
			echo "ERROR"
			return $rc
		else
			rm -f ${gitout}
			echo "PULL"
			return 0
		fi
	fi  
	(
		export PATH=$BASE_SRC_ROOT/zospm/bin:$PATH; 
		export ZOSPM_REPOROOT=$BUILD_ROOT;
		zospm -w $BASE_SRC_WORKROOT refresh ${sw} >${gitout} 2>${giterr}
	)
	rc=$?
	if [ $rc -gt 0 ]; then
		echo "ERROR"
		cat ${gitout} >&2
		cat ${giterr} >&2
		return $rc
	fi
	grep -q 'Already up-to-date' ${gitout}
	rc=$?
	rm -f ${gitout} ${giterr}
	if [ $rc -eq 0 ]; then
		echo "CURRENT"
	else
		echo "PULL"
	fi
	return 0
}

function RepoBuild {
	repo=$1
	out="RepoBuild.results"

	if ${verbose}; then
		SlackMsg "RepoBuild ${repo}"
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
	sw=$1
	repo=$2
	timestamp=$3
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
	sw=$1
	repo=$2
        paxfile=$3
 	artifact_url=$4

	curlout="curl.out"
	paxout="pax.out"
	out="RepoDownload.out"
	
	if ${verbose}; then
		SlackMsg "RepoDownload ${sw}"
	fi
	rm -rf "${DOWNLOAD_ROOT}/${repo}"

	binout=binrefresh.out
	binerr=binrefresh.err
	(
		export PATH=$BASE_BIN_ROOT/zospm/bin:$PATH; 
		export ZOSPM_REPOROOT=$DOWNLOAD_ROOT;
		zospm -w $BASE_BIN_WORKROOT refresh ${sw} >${binout} 2>${binerr}
	)

	DOWNLOAD_ZOSPM="${DOWNLOAD_ROOT}/zospm/bin/zospm"
	if [ "${repo}" = "zospm" ]; then
		expected="ZHW110 1234-AB5 ZOSPM Hello World Unit Test Software V1.1"
		result=`zospm search zhw 2>&1` 
		if [ "${result}" != "${expected}" ]; then
			echo "RepoDownload: zospm failed to run search for zhw. Results: ${result}"
			return 16
		else
			return 0
		fi
	else
		if [ -f ${DOWNLOAD_ZOSPM} ]; then
			prods=`zospm search ${sw} | awk '{ print $1; }'`

			for prod in ${prods}; do
				if ${verbose}; then
					SlackMsg "uninstall, install, configure ${prod}"
				fi
				# remove previous download builds
				zospm deconfigure ${prod} >"${out}" 2>&1
				rc=$?
				if [ $rc -gt 0 ]; then
					echo "RepoDownload: Failed to deconfigure ${prod} from download. rc:$rc"
					return $rc
				fi
				zospm uninstall ${prod} >"${out}" 2>&1
				rc=$?
				if [ $rc -gt 0 ]; then
					echo "RepoDownload: Failed to uninstall ${prod} from download. rc:$rc"
					return $rc
				fi
				cat /dev/null >"${out}"
				if [ "${prod}" = "ZHW110" ]; then

					install_verbs="prodreq smpconfig smpreceive smpcrdddef proddsalloc smpapplycheck smpapply smpacceptcheck smpaccept"
				else
					install_verbs="prodreq smpconfig smpreceive smpcrdddef proddsalloc smpapplycheck smpapply smpacceptcheck smpaccept archive"
				fi
				smpverbs="smpapplycheck smpapply smpacceptcheck smpaccept"
				for verb in ${install_verbs}; do
					zospm ${verb} ${prod} >>"${out}" 2>&1
					rc=$?
					if [ $rc -eq 4 ]; then
                                          case $smpverbs in
                                          *$verb*)
                                                  SlackMsg "RepoDownload: Warning for install/update ${prod} from download. rc:$rc"
                                                  rc=0
                                                  ;;
                                          *)
                                                  ;;
                                          esac

					fi
					if [ $rc -gt 0 ]; then
                                                echo "RepoDownload: Failed to install ${prod} from download. rc:$rc" 2>&1
                                                return $rc
					fi
				done
				if [ "${prod}" = "ZHW110" ]; then
					zospm smpreceiveptf ${prod} "MCSPTF2" >>"${out}" 2>&1
					zospm update ${prod} >>"${out}" 2>&1
					rc=$?
				fi

				if [ $rc -gt 0 ]; then
					echo "RepoDownload: Failed to install/update ${prod} from download. rc:$rc"
					return $rc
				fi

				zospm archive ${prod} >>"${out}" 2>&1 
				rc=$? 


				if [ $rc -gt 0 ]; then
					echo "RepoDownload: Failed to install/update ${prod} from download. rc:$rc"
					return $rc
				fi

				zospm configure ${prod} >>"${out}" 2>&1
				rc=$?
				if [ $rc -gt 0 ]; then
					echo "RepoDownload: Failed to configure ${prod} from download. rc:$rc"
					return $rc
				fi
				zospm deconfigure ${prod} >>"${out}" 2>&1
				rc=$?
				if [ $rc -gt 0 ]; then
					echo "RepoDownload: Failed to deconfigure ${prod} from download. rc:$rc"
					return $rc
				fi
				zospm uninstall ${prod} >>"${out}" 2>&1
			done
			rm -f "${out}"
		fi
	fi
	return 0
}

#
# Start of mainline 'loop forever'
# The loop builds everything first and then proceeds to test, deploy, download anything it built.
# This two-step approach is required because zospm and zospm-zhw have dependencies on each other.
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

	export ZOSPM_SRC_HLQ="${ZOSPM_BUILD_HLQ}S."
	export ZOSPM_TGT_HLQ="${ZOSPM_BUILD_HLQ}T."
	export ZOSPM_SRC_ZFSROOT="${ZOSPM_BUILD_ZFSROOT}s/"
	export ZOSPM_TGT_ZFSROOT="${ZOSPM_BUILD_ZFSROOT}t/"
	export ZOSPM_WORKROOT="${ZOSPM_BUILD_WORKROOT}"
	export PATH="${BASE_PATH}:${BUILD_ROOT}/zospm/bin"

	rc=0	
	builtrepos=''
	for sr in ${REPO_LIST}; do
		if [ "${sr}" = "zospm" ]; then
			r='zospm'
		else 
			r="zospm-${sr}"
		fi
		mkdir -p "${BUILD_ROOT}/${r}"
		rc=$?
		if [ ${rc} -gt 0 ]; then
			echo "Unable to	create repository directory: ${BUILD_ROOT}/${r}"
			exit ${rc}
		fi
		cd "${BUILD_ROOT}"
		status=`RepoStatus ${sr} ${r}`
	
		if [ ${status} = "CURRENT" ]; then
			continue
		fi
		if [ ${status} != "PULL" ]; then
			echo "Repository ${r} is out of sync. Investigate!"
			continue
		fi
		echo "Build repository: ${r}"
		SlackMsg "Build started for git repository: ${r}"

		cd "${BUILD_ROOT}/${r}"
		status=`RepoBuild ${r}`
		rc=$?
		if [ $rc -gt 0 ]; then
			SlackMsg "*${status}*"
			continue
		fi
		builtrepos="${builtrepos} ${sr}"
	done

	rm -rf ${ZOSPM_WORKROOT}/props
	mkdir -p ${ZOSPM_WORKROOT}/props
	cp ${BUILD_ROOT}/zospm/zospmglobalprops_ADCDV24.json ${ZOSPM_WORKROOT}/props/zospmglobalprops.json

	testrepos=''	
	for sr in ${builtrepos}; do
		if [ "${sr}" = "zospm" ]; then
			r='zospm'
		else 
			r="zospm-${sr}"
		fi
		cd "${BUILD_ROOT}/${r}"
		SlackMsg "Test started for git repository: ${r}"

		status=`RepoTest ${r}`
		rc=$?
		if [ $rc -gt 0 ]; then
			SlackMsg "*${status}*"
			continue
		fi
		testrepos="${testrepos} ${sr}"
	done

	deployrepos=''	
	for sr in ${testrepos}; do
		if [ "${sr}" = "zospm" ]; then
			r='zospm'
		else 
			r="zospm-${sr}"
		fi
		cd "${BUILD_ROOT}/${r}"
		SlackMsg "Deploy started for git repository: ${r}"

		paxfile="${r}_${timestamp}.pax"
		artifact_url="https://dl.bintray.com/zospm/zospm/${paxfile}"
		status=`RepoDeploy ${sr} ${r} ${timestamp} ${paxfile} ${artifact_url}`
		rc=$?
		if [ $rc -gt 0 ]; then
			SlackMsg "*${status}*"
			continue
		fi
		deployrepos="${deployrepos} ${sr}"
	done

	export ZOSPM_SRC_HLQ="${ZOSPM_DOWNLOAD_HLQ}S."
	export ZOSPM_TGT_HLQ="${ZOSPM_DOWNLOAD_HLQ}T."
	export ZOSPM_SRC_ZFSROOT="${ZOSPM_DOWNLOAD_ZFSROOT}s/"
	export ZOSPM_TGT_ZFSROOT="${ZOSPM_DOWNLOAD_ZFSROOT}t/"
	export ZOSPM_WORKROOT="${ZOSPM_DOWNLOAD_WORKROOT}"
	export PATH="${BASE_PATH}:${DOWNLOAD_ROOT}/zospm/bin"

	rm -rf ${ZOSPM_WORKROOT}/props
	mkdir ${ZOSPM_WORKROOT}/props
	cp ${BUILD_ROOT}/zospm/zospmglobalprops_ADCDV24.json ${ZOSPM_WORKROOT}/props/zospmglobalprops.json

	for sr in ${deployrepos}; do
		if [ "${sr}" = "zospm" ]; then
			r='zospm'
		else 
			r="zospm-${sr}"
		fi
		SlackMsg "Download started for git repository: ${r}"

		paxfile="${r}_${timestamp}.pax"
		artifact_url="https://dl.bintray.com/zospm/zospm/${paxfile}"
		status=`RepoDownload ${sr} ${r} ${paxfile} ${artifact_url}`
		rc=$?
		if [ $rc -gt 0 ]; then
			SlackMsg "*${status}*"
		else
			SlackMsg "Build, test, deploy, download of ${r} passed. Code deployed to: ${artifact_url}"
		fi
	done
done
