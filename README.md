# zospm-cicd

This is the git repository for the zospm Continuous Integration and Continuous Deployment tool.

Initial setup:
- clone the zospm-cicd repo to _zospm-cicd-root_ on a z/OS 2.2 or higher system
- configure _zospm-cicd-root_/setenv.sh to point to the zospm git, bintray and slack channels you want to use
- create _$BASE_SRC_WORKROOT_ and _$BASE_BIN_WORKROOT_ directories
- clone the zospm repo into _$BASE_SRC_WORKROOT_
- copy the zospm artifactory repo in _$BASE_BIN_WORKROOT_ (easiest way is to run deploy.sh on the _$BASE_SRC_WORKROOT_/zospm into your _$BASE_BIN_WORKROOT_/zospm
- set up your order and props directories in both _$BASE_SRC_WORKROOT_ and _$BASE_BIN_WORKROOT_ (easiest way is to have symbolic links for order directory to common order directory and to just copy the ADCD common props file
- ensure you have curl and git configured on your system

To run:

- run _headlesszospmCICD.sh_, which runs in a loop waiting for new changes to be committed to master 

Note: 
- periodically I find that the program has to be killed and restarted because the ssh cache expires
