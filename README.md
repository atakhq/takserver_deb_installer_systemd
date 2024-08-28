# takserver_deb_installer_systemd

This script will modify the TAK Server .deb installer file, so it uses systemd services instead of init.d.


## How to run script

Clone this repo, edit `apply_systemd_takserver_deb_installer.sh` and enter your google drive file id and file name (without the file extention)

```
DEB_GDRIVE_ID="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
DEB_FILE_NAME="takserver_5.2-RELEASE16_all"
```


Then make it executable and launch it:

`sudo chmod +x apply_systemd_takserver_deb_installer.sh && sudo ./apply_systemd_takserver_deb_installer.sh`

## What it does

1. Works in /tmp/ so files are erased on next reboot (auto-cleanup)
2. Downloads the target TAK Server deb intaller from your google drive
3. Depacks the .deb installer
4. Creates systemd Service files:
  a. takserver.service
  b. takserver-api.service
  c. takserver-messaging.service
  d. takserver-plugins.service (Optional to be running)
  e. takserver-retention.service (Optional to be running)
5. Removes init.d files
6. Modify the `postinst` script to support the systemd updates
7. Saves your new smaller .deb installer in `/tmp/<tak_release_full>_systemd_mod.deb`

### Install the new deb file

