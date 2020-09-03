# zospm-cicd

This is the git repository for the zospm Continuous Integration and Continuous Deployment tool.
To run:
- clone the repo to _zospm-cicd-root_ on a z/OS 2.2 or higher system
- configure _zospm-cicd-root_/setenv.sh to point to the zospm git, bintray and slack channels you want to use
- ensure you have curl and git configured on your system
- run _headlesszospmCICD.sh_, which runs in a loop waiting for new changes to be committed to master 

Note: 
- periodically I find that the program has to be killed and restarted because the ssh cache expires
