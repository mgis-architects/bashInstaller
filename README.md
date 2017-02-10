# bashInstaller

## Install

Install the shell script providing a URI to a host specific parameter file

`sudo ./mgisInstaller.sh install http://localhost:80/hostSpecificOParameterFile.ini`

## Start the installation

`sudo ./mgisInstaller.sh start`

## Remove

`sudo ./mgisInstaller.sh deinstall`


## SCRIPT: bashInstaller.sh

This script

- is designed to orchestrate the installation of multiple software components

- must be executed as root (or under sudo)

Using the install option, the script installs itself as a service
  - This is to allow reboots during the installation
  - After installation as a service, the service is started and the initial script execution exits

The script reads an INI_FILE section by section
  - each section is checkpointed *prior* to execution of the section's install script
  - in the event of reboot, checkpointed sections will be skipped

The INI_FILE should have multiple sections of the following format

     [section_name]
     zipFile=<mandatory http(s) url to zip file containing all install files>
     scriptFile=<mandatory full path to install script within the zipFile structure>
     iniFile=<optionally null http(s) url to ini file to drive the installation>

 e.g.

     [sw1]
     zipFile=http://localhost/sw1.zip
     scriptFile=sw1/bin/configure_sw1.sh
     iniFile=

If an install script fails, it should return a non zero return code
On receipt of a non zero return code, processing of this script will halt
