# Overview

Setup a local hashicorp vault running as a docker container.

Add example showing how to write and read secrets from vault.
The examples should be in the form of bash and python commands which will authenticate to vault.
We should not use docker exec command when writing or reading secrets 

The secrets must persist across restarts

## Supporting Notes1

- For guidance on how `README.md` should be structured and maintained, consult [AGENTS_INFO/AGENTS_NOTES_ON_README.md](AGENTS_INFO/AGENTS_NOTES_ON_README.md).


When using python, use a local venv created using the uv command

When investigating and fixing issues, always prove the root cause with temporary test scripts before making changes to main code.
Once changes are made to the main code you must run an end to end test to confirm the fixes work.

# New requirement

Vault should run as a container on kubenetes.
I should be able to access vault from the host computer 
There should also be an example ubi container, called devpod which should be able to access vault.
The demonstration scripts for writing and reading secrets should work from the host machine and also from the devpod

## dev pod requirements
This will be a linux development environment that I will run remove vscode sesions on
It should have the latest available versions of 
- python 
- uv
- vscode remote server

It should run as user z4701038-779

