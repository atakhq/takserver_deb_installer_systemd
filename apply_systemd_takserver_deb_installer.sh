#!/bin/bash

# Update .deb installer to use systemd and remove init.d crap
# THIS MUST BE RUN WITH SUDO


# Work in tmp so files erase on reboot after done (auto-cleanup)
cd /tmp/

#Download the deb
DEB_GDRIVE_ID="xxxxxxxx"
DEB_FILE_NAME="takserver_5.2-RELEASE16_all"

# Check if the file already exists
if [ -f "${DEB_FILE_NAME}.deb" ]; then
    echo "File ${DEB_FILE_NAME}.deb already exists. Skipping download."
else
    echo "Downloading ${DEB_FILE_NAME}.deb from Google Drive..."
    sudo curl -L "https://drive.usercontent.google.com/download?id=${DEB_GDRIVE_ID}&confirm=xxx" -o "/tmp/${DEB_FILE_NAME}.deb"
    echo "Download completed."
fi


# decompress the .deb (-R raw to preserve file/folder perms)
DEPACK_DIR="/tmp/tak_deb_depacked"
sudo dpkg-deb -R "${DEB_FILE_NAME}.deb" "${DEPACK_DIR}"

####################################

# System D Support changes below

####################################

# Create the new systemd service files

####################################

# Define the directory where the systemd files will be written
DEB_DEPACKED_SYSTEMD_DIR="/tmp/tak_deb_depacked/etc/systemd/system"

# Create the directory if it doesn't exist
sudo mkdir -p "$DEB_DEPACKED_SYSTEMD_DIR"


# Write the takserver-api.service file
sudo cat <<EOL > "$DEB_DEPACKED_SYSTEMD_DIR/takserver-api.service"
[Unit]
Description=TAK Server API Service
Requires=takserver-messaging.service
DefaultDependencies=no

[Service]
User=tak
Group=tak
WorkingDirectory=/opt/tak
ExecStart=/opt/tak/takserver-api.sh 
ExecStartPost=/usr/bin/timeout 240 sh -c 'while ! ss -Htln sport = :8443 | grep -q "^LISTEN.*:8443"; do sleep 1; done'
ExecStop=kill -9 \`pgrep -f "spring.profiles.active=api"\`
KillMode=mixed
KillSignal=9
Restart=on-failure
Type=exec

[Install]
WantedBy=multi-user.target
EOL

# Write the takserver-config.service file
sudo cat <<EOL > "$DEB_DEPACKED_SYSTEMD_DIR/takserver-config.service"
[Unit]
Description=TAK Server Config Service
After=mulit-user.target
Before=takserver-messaging.service

[Service]
User=tak
Group=tak
WorkingDirectory=/opt/tak
ExecStart=/opt/tak/takserver-config.sh 
ExecStartPost=/usr/bin/timeout 60 sh -c 'while ! ss -Htln sport = :47100 | grep -q "^LISTEN.*:47100"; do sleep 1; done'
ExecStop=kill -9 \`pgrep -f "spring.profiles.active=config"\`
KillMode=mixed
KillSignal=9
Restart=on-failure
Type=exec

[Install]
WantedBy=multi-user.target
EOL

# Write the takserver-messaging.service file
sudo cat <<EOL > "$DEB_DEPACKED_SYSTEMD_DIR/takserver-messaging.service"
[Unit]
Description=TAK Server Messaging Service
Requires=takserver-config.service
Before=takserver-api.service
DefaultDependencies=no

[Service]
User=tak
Group=tak
WorkingDirectory=/opt/tak
ExecStart=/opt/tak/takserver-messaging.sh
ExecStartPost=/usr/bin/timeout 120 sh -c 'while ! ss -Htln sport = :18089 | grep -q "^LISTEN.*:18089"; do sleep 1; done'
ExecStop=kill -9 \`pgrep -f "spring.profiles.active=messaging"\`
KillMode=mixed
KillSignal=9
Restart=on-failure
RestartPreventExitStatus=255
Type=exec

[Install]
WantedBy=multi-user.target
EOL

# Write the takserver-plugin.service file
sudo cat <<EOL > "$DEB_DEPACKED_SYSTEMD_DIR/takserver-plugin.service"
[Unit]
Description=TAK Server Plugin Service
Requires=takserver-api.service
DefaultDependencies=no

[Service]
User=tak
Group=tak
WorkingDirectory=/opt/tak
ExecStart=/opt/tak/takserver-plugins.sh
ExecStop=kill -9 \`pgrep -f "plugins"\`
KillMode=mixed
KillSignal=9
Restart=on-failure
Type=exec

[Install]
WantedBy=multi-user.target
EOL

# Write the takserver-retention.service file
sudo cat <<EOL > "$DEB_DEPACKED_SYSTEMD_DIR/takserver-retention.service"
[Unit]
Description=TAK Server Retention Service
Requires=takserver-plugin.service
DefaultDependencies=no

[Service]
User=tak
Group=tak
WorkingDirectory=/opt/tak
ExecStart=/opt/tak/takserver-retention.sh
ExecStop=kill -9 \`pgrep -f "retention"\`
KillMode=mixed
KillSignal=9
Restart=on-failure
Type=exec

[Install]
WantedBy=multi-user.target
EOL


######################

# Modify the postinst script to support our new files

#####################

# TO DO: 
### CODE HERE TO DELETE $DEPACK_DIR/DEBIAN/postinst
sudo rm "${DEPACK_DIR}/DEBIAN/postinst"

## CODE HERE TO WRITE NEW FILE IN $DEPACK_DIR/DEBIAN/postinst

# Create the postinst file with the specified content
sudo tee "${DEPACK_DIR}/DEBIAN/postinst" > /dev/null << 'EOL'
#!/bin/sh -e

ec() {
    echo "$@" >&2
    "$@"
}

case "$1" in
    configure)
        
        echo "takserver-package takserver: postinstall $1 $2"

export tak_full_version=5.2-RELEASE-16

# Set ownership and permissions for necessary TAK directories and files
chown tak:tak /opt/tak

chmod 644 /opt/tak/logging-restrictsize.xml
chmod 544 /opt/tak/*.bat
chmod 544 /opt/tak/*.sh

# Copy systemd service files to the correct location
cp /etc/systemd/system/takserver-config.service /etc/systemd/system/
cp /etc/systemd/system/takserver-messaging.service /etc/systemd/system/
cp /etc/systemd/system/takserver-api.service /etc/systemd/system/
cp /etc/systemd/system/takserver-plugin.service /etc/systemd/system/
cp /etc/systemd/system/takserver-retention.service /etc/systemd/system/

# Set correct permissions on systemd service files
chmod 644 /etc/systemd/system/takserver-config.service
chmod 644 /etc/systemd/system/takserver-messaging.service
chmod 644 /etc/systemd/system/takserver-api.service
chmod 644 /etc/systemd/system/takserver-plugin.service
chmod 644 /etc/systemd/system/takserver-retention.service

# Enable systemd services
systemctl daemon-reload
systemctl enable takserver-config.service
systemctl enable takserver-messaging.service
systemctl enable takserver-api.service
systemctl enable takserver-plugin.service
systemctl enable takserver-retention.service


# Restore retention config files if necessary
if [ -f /opt/tak/conf/retention/retention-policy_bak.yml ]; then
    echo "Restoring retention policy configuration from backup"
    mv /opt/tak/conf/retention/retention-policy_bak.yml /opt/tak/conf/retention/retention-policy.yml
fi

if [ -f /opt/tak/conf/retention/retention-service_bak.yml ]; then
    echo "Restoring retention service configuration from backup"
    mv /opt/tak/conf/retention/retention-service_bak.yml /opt/tak/conf/retention/retention-service.yml
fi

if [ -f /opt/tak/conf/retention/mission-archiving-config_bak.yml ]; then
    echo "Restoring existing mission archive configuration from backup"
    mv /opt/tak/conf/retention/mission-archiving-config_bak.yml /opt/tak/conf/retention/mission-archiving-config.yml
fi

if [ -f /opt/tak/mission-archive/mission-store_bak.yml ]; then
    echo "Restoring existing mission store from backup"
    mv /opt/tak/mission-archive/mission-store_bak.yml /opt/tak/mission-archive/mission-store.yml
fi

chown -fR tak:tak /opt/tak/conf
chown -fR tak:tak /opt/tak/mission-archive

# Set up directories and permissions for logs and other files
chmod 755 /opt/tak/utils
mkdir -p /opt/tak/logs
chown tak:tak /opt/tak/logs
chmod 755 /opt/tak/logs

if [ -f "/opt/tak/TAKIgniteConfig.xml" ]; then
    chown -f tak:tak /opt/tak/TAKIgniteConfig.xml 2>/dev/null
fi

if [ -f "/opt/tak/CoreConfig.xml" ]; then
    chown -f tak:tak /opt/tak/CoreConfig.xml 2>/dev/null
fi

mkdir -p /opt/tak/iconsets
chown -fR tak:tak /opt/tak/iconsets
mkdir -p /opt/tak/webcontent/webtak-plugins/plugins

if [ ! -f /opt/tak/webcontent/webtak-plugins/webtak-manifest.json ]; then 
    echo -e "{\n\t\"plugins\": [], \n\t\"iconSets\": []\n}" > /opt/tak/webcontent/webtak-plugins/webtak-manifest.json
fi

chown -fR tak:tak /opt/tak/webcontent
mkdir -p /opt/tak/logs
chown tak:tak /opt/tak/logs
mkdir -p /opt/tak/lib
chown tak:tak /opt/tak/lib

cp /opt/tak/certs-tmp/cert-metadata.sh /opt/tak/certs/. 2>/dev/null || :
cp /opt/tak/certs-tmp/config.cfg /opt/tak/certs/. 2>/dev/null || :
rm -rf /opt/tak/certs-tmp

# Rename old tomcat if it exists
if [ -f "/opt/tak/apache-tomcat" ]; then
    mv /opt/tak/apache-tomcat /opt/tak/apache-tomcat_NO_LONGER_USED >/dev/null 2>&1
fi

# Extract takserver.war on Debian-based installs
if [ -f /etc/debian_version ]; then
    sh /opt/tak/setup-for-extracted-war.sh
fi

# License and instructions
cat <<- "EOF"
TAK SERVER SOFTWARE LICENSE AGREEMENT

Distribution Statement A: Approved for public release; distribution is unlimited.

----

By default, TAK Server requires a keystore and truststore (X.509 certificates). Follow the instructions in Appendix B of the configuration guide to create these certificates.

After generating certificates, use the following command to register an admin account:
> sudo java -jar /opt/tak/utils/UserManager.jar certmod -A /opt/tak/certs/files/admin.pem

Using Firefox or Chrome on this computer add the admin certificate to the local browser trust and browse to this address to verify keystore and truststore configuration:
 
http://localhost:8443

Follow the instructions in the Installation section of the configuration guide to complete the setup process. 
EOF

chown root:root /opt/tak/db-utils/pg_hba.conf
chmod 600 /opt/tak/db-utils/pg_hba.conf

chmod 544 /opt/tak/db-utils/*.sh
chmod 500 /opt/tak/db-utils/clear-old-data.sh
chmod 500 /opt/tak/db-utils/clear-old-data.sql
chown postgres:postgres /opt/tak/db-utils/clear-old-data.sh
chown postgres:postgres /opt/tak/db-utils/clear-old-data.sql

# Set up a default DB password
sh /opt/tak/db-utils/setupDefaultPassword.sh

if [ -f /opt/tak/db-utils/clear-old-data.sql.bak ] ; then
    mv /opt/tak/db-utils/clear-old-data.sql /opt/tak/db-utils/clear-old-data.sql.dist.$tak_full_version
    mv /opt/tak/db-utils/clear-old-data.sql.bak /opt/tak/db-utils/clear-old-data.sql
fi

sudo /opt/tak/db-utils/takserver-setup-db.sh

;;
esac
EOL

# Make the postinst script executable
sudo chmod +x "${DEPACK_DIR}/DEBIAN/postinst"


######################

# Delete the init.d files since we dont need them

#####################

TAK_DEPACK_DIR="${DEPACK_DIR}/opt/tak"
sudo rm -rf "${TAK_DEPACK_DIR}/API" "${TAK_DEPACK_DIR}/config" "${TAK_DEPACK_DIR}/launcher" "${TAK_DEPACK_DIR}/messaging" "${TAK_DEPACK_DIR}/retention"


####################################

# Rebuild the .deb installer for use

cd /tmp/

dpkg-deb --build "$DEPACK_DIR" "${DEB_FILE_NAME}_systemd_mod.deb"

sudo chmod 664 "${DEPACK_DIR}/../${DEB_FILE_NAME}_systemd_mod.deb"

echo "Your custom .deb is now ready to use for install: "

# CLEANUP

sudo rm -rf /tmp/tak_deb_depacked/




