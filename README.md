## Introduction
This is an interactive Linux shell script, that makes an SAP kernel patch process easier.

## Quick start
1. Download the script from the Releases section.
2. Upload it to your Linux/Unix server.
3. Set executable permissions for root.
4. Run the script: ./sap_kernel_patch.sh

## How it works
Prompts for an SID and checks if it is valid:

<img src="./screenshots/1-enter-sid.png" width="50%">

Prompts for a path with extracted kernel files:

<img src="./screenshots/2-enter-path.png" width="50%">

Checks if there are runnging processes, and waits for you to stop them:

<img src="./screenshots/3-check-processes.png" width="50%">

Displays a summary of collected data and lists the next steps:

<img src="./screenshots/4-summary.png" width="50%">

Executes the steps:

<img src="./screenshots/5-process.png" width="50%">

After successful completion, asks you to restart the host:

<img src="./screenshots/6-restart.png" width="50%">
