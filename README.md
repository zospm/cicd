# zbrew-cicd
This is the git repository for the zbrew Continuous Integration and Continuous Deployment tool.
To run:
-clone the repo to <zbrew-cicd-root> on a z/OS 2.2 or higher system
-configure <zbrew-cicd-root>/setenv.sh to point to the zbrew git, bintray and slack channels you want to use
-ensure you have curl and git configured on your system
-run headlesszbrewCICD.sh, which runs in a loop waiting for new changes to be committed to master 

Note: 
-periodically I find that the program has to be killed and restarted because the ssh cache expires
