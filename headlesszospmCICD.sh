#!/bin/sh
#
# Run this program so that you won't be prompted for password except at start
#
(
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_rsa
nohup zospmCICD.sh >/tmp/zospm-cicd.out 2>&1 &
)
