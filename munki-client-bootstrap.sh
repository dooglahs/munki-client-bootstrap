#!/bin/bash
# adding -x after "bash" above spits execution to log; useful for diagnosing problems.

# This script is used to bootstrap computers to be managed by an existing Munki instance.
#	Script is interactive so pay attention to questions. History at the end.

# ----------------------------------------------------------------------------------------
# ------------ MUNKI SETUP SCRIPT --------------------------------------------------------
# Initializes the script, pulls defaults from munki-setup-defaults.txt file and determines
# a few on its own. Creates logger function.
# ---------------------------------------------------------------------------------------- 

# Logfile Info. Set the date as you wish
DATE=$(date +%Y%m%d)
LOG="MunkiInstallScript-${DATE}.log"
# Note the logger function ~20 lines below

if [ -e /usr/sbin/resetpassword ]; then
	OS="RD" # You are booted from the Recovery Drive
else
	OS="OSX" # You are booted from a full OSX installation
fi

if [ ${OS} == OSX ]; then
	if [[ $EUID -ne 0 ]]; then
		echo "You must run this script as root. Try again with \"sudo\""
		echo ""
		exit 0
	fi

	# Disable Gatekeeper; MunkiTools unsigned.
	spctl --master-disable
fi

# Determines Installers Path
function INST_PATH() {
  [ ${1:0:1} == '/' ] && x=$1 || x=${PWD}/$1
  cd "${x%/*}"
  echo $( pwd -P )/${x##*/}
  cd "${OLDPWD}"
}
INSTALLERS=$( INST_PATH "${BASH_SOURCE[0]}" )
INSTALLERS=${INSTALLERS%/*}

# Script defaults file; mandatory for this script to work.
# NOTE: There are a few other variables to set in the post-run scripts.
if [[ -e "${INSTALLERS}"/munki-client-bootstrap-defaults.txt ]]; then
	source "${INSTALLERS}"/munki-client-bootstrap-defaults.txt
else
	echo "The munki-setup-defaults.txt file failed to load. Please check that the file exists and run this script again."
	echo ""
	exit 0
fi

logger(){
	echo "$1"
	echo "$1" >> "${INSTALLERS}"/${LOG}
}

logger ""
logger "------------ MUNKI SETUP SCRIPT: ${DATE} ------------"
logger ""
logger "This script will guide you through installing and configuring Munki on this computer."
logger ""

# Determining Target Paths
VOLUMES_BASE=$( ls /Volumes/ | grep "Macintosh HD" )
if [[ -n ${VOLUMES_BASE} ]]; then
	TARGET="/Volumes/Macintosh HD"
else
	unset VOLUMES_BASE
	declare -a VOLUMES_BASE
	i=1
	for v in /Volumes/*/private; do
		VOLUMES_BASE[i++]="${v%/*}"
	done
	logger "There are ${#VOLUMES_BASE[@]} configurable volumes."
	logger ""
	LOOP=true
	while [ ${LOOP} = true ]; do
		for((i=1;i<=${#VOLUMES_BASE[@]};i++)); do
		    logger "   [$i] ${VOLUMES_BASE[i]}"
		done
		logger ""
		read -p "Which volume do you want to install MunkiTools? " CHOICE;
		logger ""
		if [[ ${CHOICE} -le ${#VOLUMES_BASE[@]} ]] && [[ ${CHOICE} -gt 0 ]] && [[ ! -z "${CHOICE}" ]]; then
			TARGET=${VOLUMES_BASE[$CHOICE]}
			break
		else
			logger "Invalid selection. Please try again."
			sleep 1
		fi
		logger ""
	done
fi

logger "Target is: ${TARGET}"
logger ""

# The issue of sudo
if [ ${OS} == OSX ]; then
	SUDO=$( echo "/usr/bin/sudo -u root" )
else
	SUDO=""
fi

# Define which user repository to search
if [[ ${AUTH_NODE} == "" ]] || [[ ${AUTH_NODE} == "local" ]]; then
	NODE_SEARCH="${TARGET}/var/db/dslocal/nodes/Default/users"
fi

logger ""

# ----------------------------------------------------------------------------------------
# ------------ USER AND COMPUTER NAME ----------------------------------------------------
# Set the computer name based off of the user shortname. This is the one interactive
# portion of the script.
# ----------------------------------------------------------------------------------------

logger "------------ USER AND COMPUTER NAME ------------"
logger ""

COMPUTERNAME=$( scutil --get ComputerName );
HOSTENAME=$( scutil --get HostName );
LOCALHOSTNAME=$( scutil --get LocalHostName );
logger "ComputerName is: ${COMPUTERNAME}"
logger "HostName is: ${HOSTENAME}"
logger "LocalHostName is: ${LOCALHOSTNAME}"
logger ""
logger "We need the short username for the person getting this computer. For example: jdoe"
logger ""
logger "   NOTE: If you are simply preparing this computer for eventual deployment enter \"setup\""
logger ""
read -p "Enter the correct short username for the user and press [ENTER]: " USER;
logger ""
if [[ ${USER} != "setup" ]]; then
	read -p "What is the Real Name for ${USER}? Use Firstname Lastname format: " USER_REALNAME;
	logger ""
fi
if [[ ${USER_COMPUTER_SAME_NAME} == "yes" ]] || [[ ${USER} == "setup" ]]; then
	NAME=${USER}
else
	read -p "What should be the computer be named? " NAME;
	logger ""
fi

sleep 1

# ----------------------------------------------------------------------------------------
# ------------ CONFIRMING SETTINGS -------------------------------------------------------
# The admin confirms the paths and username they set, then applies the username to the
# computer. If setting not correct it exits, otherwise proceeds.
# ----------------------------------------------------------------------------------------

logger "------------ CONFIRM SETTINGS ------------"
logger ""

logger "               Target Path: ${TARGET}"
logger ""
logger "            Installer Path: ${INSTALLERS}"
logger ""

if [[ ${USER} == "setup" ]]; then
	logger "     Computer and Username: ${NAME}"
else
	logger "                 Real Name: ${USER_REALNAME}"
	logger "            Short Username: ${USER}"
	logger "             Computer Name: ${NAME}"
fi
logger ""
read -p "Do those settings look correct? Type yes or no and press [ENTER]: " CORRECT;
logger ""
if [[ ${CORRECT} =~ ^([nN][oO]|[nN])$ ]]; then
	logger "Settings are incorrect. Let's debug the script or run it again."
	logger ""
	exit 0
else
	logger "Settings are correct."
fi
logger ""

${SUDO} scutil --set ComputerName ${NAME}
${SUDO} scutil --set HostName ${NAME}
${SUDO} scutil --set LocalHostName ${NAME}
${SUDO} defaults write "${TARGET}"/Library/Preferences/SystemConfiguration/com.apple.smb.server NetBIOSName -string ${NAME}
logger "Computer is now called \"${NAME}\"."

logger ""
sleep 1

# ----------------------------------------------------------------------------------------
# ------------ MUNKI CLIENT INSTALLATION -------------------------------------------------
# Determine if MunkiTools already on this computer and install if necessary.
# ----------------------------------------------------------------------------------------

logger "------------ MUNKI CLIENT INSTALLATION ------------"
logger ""

if [ ! -d "${TARGET}"/usr/local/munki ] && [[ -e "${INSTALLERS}"/${MUNKITOOLS_INSTALLER} ]]; then
	logger "Installing Munki Client from local source..."
	installer -allowUntrusted -pkg "${INSTALLERS}"/${MUNKITOOLS_INSTALLER} -target "${TARGET}" 2> /dev/null
	logger "     ...installed"
	logger ""
elif [ ! -d "${TARGET}"/usr/local/munki ]; then
	OLDPWD="$( pwd )"
	echo "${OLDPWD}"
	cd "${INSTALLERS}"
	"${TARGET}"/usr/bin/curl -O https://munkibuilds.org/munkitools2-latest.pkg
	logger "Installing Munki Client from munkibuilds.org..."
	installer -allowUntrusted -pkg munkitools2-latest.pkg -target "${TARGET}" 2> /dev/null
	logger "     ...installed"
	logger ""
	rm munkitools2-latest.pkg
	cd "${OLDPWD}"
else
	logger "Munki Client already installed."
fi
logger ""
sleep 1

# ----------------------------------------------------------------------------------------
# ------------ CONFIGURING MUNKITOOLS ----------------------------------------------------
# Configure Munki and Munki Enroll. Our Munki Enroll is highly hacked so pay attention to
# that code if you change it out.
# ----------------------------------------------------------------------------------------

logger "------------ CONFIGURING MUNKITOOLS ------------"
logger ""

# Munki client configuration. Feel free to add or delete sudo defaults write items below.
${SUDO} defaults write "${TARGET}"/Library/Preferences/ManagedInstalls SoftwareRepoURL "${MUNKI_REPO_URL}"
${SUDO} defaults write "${TARGET}"/Library/Preferences/ManagedInstalls AdditionalHttpHeaders -array "${MUNKI_REPO_AUTH}"
${SUDO} defaults write "${TARGET}"/Library/Preferences/ManagedInstalls InstallAppleSoftwareUpdates -bool true
${SUDO} defaults write "${TARGET}"/Library/Preferences/ManagedInstalls DaysBetweenNotifications -int 1
if [[ -n ${MUNKI_CLIENTRESOURCE_FILE} ]]; then
	${SUDO} defaults write "${TARGET}"/Library/Preferences/ManagedInstalls ClientResourceURL -string "${MUNKI_CLIENTRESOURCE_URL}"
	${SUDO} defaults write "${TARGET}"/Library/Preferences/ManagedInstalls ClientResourceFileName -string "${MUNKI_CLIENTRESOURCE_FILE}"
fi
if [[ -n ${MUNKI_HELP_URL} ]]; then
	${SUDO} defaults write "${TARGET}"/Library/Preferences/ManagedInstalls HelpURL -string "${MUNKI_HELP_URL}"
fi
logger "Set base Munki Client Preferences."

# Doing Munki-Enroll...
if [[ -n ${MUNKIENROLL_SUBMITURL} ]]; then
	HTACCESS="${HTACCESS_USER}:${HTACCESS_PASS}"
	IDENTIFIER=${NAME};
	HOSTNAME=$( scutil --get ComputerName );
	"${TARGET}"/usr/bin/curl -u "${HTACCESS}" --max-time 10 --get --data hostname="${HOSTNAME}" --data identifier="${IDENTIFIER}" "${MUNKIENROLL_SUBMITURL}"
	IDENTIFIER_PATH=$( echo "$IDENTIFIER" | sed 's/\/[^/]*$//' );
	${SUDO} defaults write "${TARGET}"/Library/Preferences/ManagedInstalls ClientIdentifier "${MUNKIENROLL_PREFIX}${HOSTNAME}"
	logger ""
	logger "Client manifest called ${MUNKIENROLL_PREFIX}${HOSTNAME}."
fi
logger ""
sleep 1

# ----------------------------------------------------------------------------------------
# ------------ ADMIN CREATION ------------------------------------------------------------
# This section looks to see if you have defined an admin user in the script defaults. If
# you have it checks if the user already exists. If admin user is not present it flags for
# the admin user to be installed in post scripts.
# ----------------------------------------------------------------------------------------

if [[ -n ${ADMIN} ]]; then
	HAS_ADMIN=$( ls "${NODE_SEARCH}" | grep ${ADMIN} )
	if [[ -n ${HAS_ADMIN} ]]; then
		logger "\"${ADMIN}\" user exists."
		ADMIN_POST_FLAG="no"
	else
		logger "\"${ADMIN}\" user will be created."
		ADMIN_POST_FLAG="yes"
	fi
	logger ""
	sleep 1
else
	ADMIN_POST_FLAG="no"
fi

# ----------------------------------------------------------------------------------------
# ------------ User Creation -------------------------------------------------------------
# This section checks to see if a user already exists on the machine. If not it flags for
# the user to be installed in post scripts.
# ----------------------------------------------------------------------------------------

if [[ ${USER_CREATE} == "yes" ]] && [[ ${USER} != "setup" ]]; then
	HAS_USER=$( ls "${NODE_SEARCH}" | grep ${USER} )
	if [[ -n ${HAS_USER} ]]; then
		logger "\"${USER}\" user exists."
		USER_POST_FLAG="no"
	else
		logger "\"${USER}\" user will be created."
		USER_POST_FLAG="yes"
	fi
	logger ""
	sleep 1
else
	USER_POST_FLAG="no"
fi

# ----------------------------------------------------------------------------------------
# ------------ FileVaultMaster Key -------------------------------------------------------
# If you have a FileVaultMaster key and it is in a folder called "FileVaultMaster" in the
# same directory as this script, it will get installed but *not* activated until the
# second post script runs.
# ----------------------------------------------------------------------------------------

HAS_FILEVAULTKEY=$( ls "${TARGET}"/Library/Keychains/ | grep "FileVaultMaster" )
if [[ -z ${HAS_FILEVAULTKEY} ]] && [[ -e "${INSTALLERS}"/FileVaultMaster/FileVaultMaster.keychain ]]; then
	logger "------------ FILEVAULTMASTER KEY INSTALLATION ------------"
	logger ""
	logger "Installing Filevault Master Keychain..."
	cp "${INSTALLERS}"/FileVaultMaster/FileVaultMaster.keychain "${TARGET}"/Library/Keychains/
	${SUDO} chmod 644 "${TARGET}"/Library/Keychains/FileVaultMaster.keychain
	${SUDO} chown root:wheel "${TARGET}"/Library/Keychains/FileVaultMaster.keychain
	logger "     ...installed"
	logger ""
	logger "Remember to double check that any users not activated by this script are enabled in FileVault!"
	logger ""
	FV_POST_FLAG="yes"
	sleep 1
else
	FV_POST_FLAG="no"
fi

# ----------------------------------------------------------------------------------------
# ------------ Post Run Script Creation --------------------------------------------------
# Creates some scripts to run on reboot if needed.
# ----------------------------------------------------------------------------------------

logger "------------ POST RUN SCRIPT CREATION ------------"
logger ""

if [ -z ${TZ} ]; then
	TZ="GMT"
fi

# NOTE ABOUT THESE POST RUN SCRIPTS. Scripts are built into /var. If you would prefer
#  	another location search and replace /var with your selection, i.e. /etc/local/bin.

# This is the LaunchDaemon for first post-run script
cat >> "${TARGET}"/Library/LaunchDaemons/com.learningobjects.firstpost.plist <<FIRST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>com.learningobjects.firstpost</string>
	<key>ProgramArguments</key>
	<array>
		<string>/var/firstpost.sh</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
</dict>
</plist>
FIRST

# This is the first post-run script
cat >> "${TARGET}"/var/firstpost.sh <<FIRST
#!/bin/bash
# First post script for bootstrapping Munki.
logger(){
	echo "\$1" >> ${LOGLOC}/${NAME}-${LOG}
}
logger "First post script running."
FIRST

# Set the computer name if script run originally from Recovery Drive
if [ ${OS} == RD ]; then
	cat >> "${TARGET}"/var/firstpost.sh <<FIRST
# Name the computer
sudo scutil --set ComputerName ${NAME}
sudo scutil --set HostName ${NAME}
sudo scutil --set LocalHostName ${NAME}
sudo defaults write /Library/Preferences/SystemConfiguration/com.apple.smb.server NetBIOSName -string ${NAME}
logger "FP: computer name set to ${NAME}."
sudo systemsetup -settimezone "${TZ}"
sudo ntpdate -u time.apple.com
sleep 10
FIRST
fi

# Conditionally add computer to wifi network
if [[ -n ${WIFI_NETWORK} ]]; then
	cat >> "${TARGET}"/var/firstpost.sh <<FIRST
# Get wifi working
INTERFACE=\$( networksetup -listallhardwareports | grep -E '(Wi-Fi|AirPort)' -A 1 | grep en. | awk -F': ' '{print \$2}' )
networksetup -addpreferredwirelessnetworkatindex \${INTERFACE} ${WIFI_NETWORK} 0 ${WIFI_SEC} "${WIFI_PWD}"
logger "FP: wifi network ${WIFI_NETWORK} setup."
sleep 20
FIRST
fi
cat >> "${TARGET}"/var/firstpost.sh <<FIRST
cat >> /tmp/secondpost.sh <<SECOND
#!/bin/bash
# Second post script for bootstrapping Munki.
logger(){
	echo "\\\$1" >> ${LOGLOC}/${NAME}-${LOG}
}
logger "Second post script running."
if [ -n /Library/LaunchDaemons/com.learningobjects.firstpost.plist ]; then
	rm /Library/LaunchDaemons/com.learningobjects.firstpost.plist
fi
if [ -n /var/firstpost.sh ]; then
	rm /var/firstpost.sh
fi
SECOND
FIRST

# Conditionally append admin installation if needed
if [[ ${ADMIN_POST_FLAG} == "yes" ]]; then
	cat >> "${TARGET}"/var/firstpost.sh <<FIRST
	cat >> /tmp/secondpost.sh <<SECOND
. /etc/rc.common
sudo dscl . create /Users/${ADMIN}
sudo dscl . create /Users/${ADMIN} RealName "${ADMIN_NAME}"
sudo dscl . passwd /Users/${ADMIN} ${ADMIN_PWD}
sudo dscl . create /Users/${ADMIN} UniqueID 415
sudo dscl . create /Users/${ADMIN} PrimaryGroupID 20
sudo dscl . create /Users/${ADMIN} UserShell /bin/bash
sudo dscl . create /Users/${ADMIN} NFSHomeDirectory /Users/${ADMIN}
sudo dseditgroup -o edit -a ${ADMIN} -t user admin
sudo dscl . -create /Users/${ADMIN} picture "/Library/User Pictures/LO/de-icon.tif"
if [ ! -e /var/db/.AppleSetupDone ]; then
	sudo touch /var/db/.AppleSetupDone
fi
logger "SP: ${ADMIN} created."
SECOND
FIRST
fi

# Conditionally append user installation if needed
if [[ ${USER_POST_FLAG} == "yes" ]]; then
	cat >> "${TARGET}"/var/firstpost.sh <<FIRST
	cat >> /tmp/secondpost.sh <<SECOND
NUID=\\\$( dscl . -list /Users UniqueID | awk '{print \\\$2}' | sort -ug | tail -1 )
NUID=\\\$((NUID+1))
. /etc/rc.common
sudo dscl . create /Users/${USER}
sudo dscl . create /Users/${USER} RealName "${USER_REALNAME}"
sudo dscl . passwd /Users/${USER} "${USER_PWD}"
sudo dscl . create /Users/${USER} UniqueID \\\${NUID}
sudo dscl . create /Users/${USER} PrimaryGroupID 20
sudo dscl . create /Users/${USER} UserShell /bin/bash
sudo dscl . create /Users/${USER} NFSHomeDirectory /Users/${USER}
sudo dseditgroup -o edit -a ${USER} -t user admin
sudo dscl . -create /Users/${USER} picture "/Library/User Pictures/LO/de-icon.tif"
if [ ! -e /var/db/.AppleSetupDone ]; then
	sudo touch /var/db/.AppleSetupDone
fi
logger "SP: ${USER} created."
SECOND
FIRST
fi

# Conditionally use fdsetup to activate FileVault
# Creates user plist for fdsetup
if [[ ${FV_POST_FLAG} == "yes" ]]; then
	# Create second post-run LaunchDaemon to enable FileVault
	cat >> "${TARGET}"/var/firstpost.sh <<FIRST
	cat > /tmp/com.learningobjects.secondpost.plist <<SECOND
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>com.learningobjects.firstpost</string>
	<key>ProgramArguments</key>
	<array>
		<string>/var/secondpost.sh</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
</dict>
</plist>
SECOND
		cat >> /tmp/fvusers.plist <<SECOND
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
<key>Username</key>
<string>${ADMIN}</string>
<key>Password</key>
<string>${ADMIN_PWD}</string>
SECOND
FIRST
	HAS_USER=$( ls "${NODE_SEARCH}" | grep ${USER} )
	if [[ -z ${HAS_USER} ]] && [[ ${USER_CREATE} == "yes" ]] && [[ ${USER} != "setup" ]]; then
		cat >> "${TARGET}"/var/firstpost.sh <<FIRST
		cat >> /tmp/fvusers.plist <<SECOND
<key>AdditionalUsers</key>
<array>
    <dict>
        <key>Username</key>
        <string>${USER}</string>
        <key>Password</key>
        <string>${USER_PWD}</string>
    </dict>
</array>
SECOND
FIRST
	fi
	cat >> "${TARGET}"/var/firstpost.sh <<FIRST
	cat >> /tmp/fvusers.plist <<SECOND
</dict>
</plist>
SECOND
FIRST
	cat >> "${TARGET}"/var/firstpost.sh <<FIRST
	cat >> /tmp/secondpost.sh <<SECOND
fdesetup enable -keychain -inputplist < /var/fvusers.plist -norecoverykey
logger "SP: Encryption enabled."
sleep 10
# rm /var/fvusers.plist
mv /var/fvusers.plist /Users/Shared/
sleep 1
SECOND
FIRST
fi

	cat >> "${TARGET}"/var/firstpost.sh <<FIRST
	cat >> /tmp/secondpost.sh <<SECOND
# rm /Library/LaunchDaemons/com.learningobjects.secondpost.plist
mv /Library/LaunchDaemons/com.learningobjects.secondpost.plist /Users/Shared
sleep 1
logger "SP: deleted second post script files."
# rm /var/secondpost.sh
mv /var/secondpost.sh /Users/Shared
sleep 1
# Reboot!
reboot
SECOND
FIRST


# Last section of post-run script
cat >> "${TARGET}"/var/firstpost.sh <<FIRST
# Kick off Munki on next reboot
touch "${TARGET}/Users/Shared/.com.googlecode.munki.checkandinstallatstartup"
# Delay the script until Managed Software is done running
munki_run(){
	ps axg | grep -v grep | grep 'managedsoftwareupdate' > /dev/null
}
while munki_run
	do sleep 30
done
# Move second post files into place and set permissions
mv /tmp/com.learningobjects.secondpost.plist /Library/LaunchDaemons/
mv /tmp/secondpost.sh /var/
chmod 755 /var/secondpost.sh
chmod 644 /Library/LaunchDaemons/com.learningobjects.secondpost.plist
chown root:wheel /var/secondpost.sh /Library/LaunchDaemons/com.learningobjects.secondpost.plist
if [ -e /tmp/fvusers.plist ]; then
	mv /tmp/fvusers.plist /var/
	chmod 644 /var/fvusers.plist
	chown root:wheel /var/fvusers.plist
fi
sleep 1
# Remove first post scrip files
# rm /Library/LaunchDaemons/com.learningobjects.firstpost.plist
mv /Library/LaunchDaemons/com.learningobjects.firstpost.plist /Users/Shared/
logger "FP: deleted first post script files."
# rm /var/firstpost.sh
mv /var/firstpost.sh /Users/Shared
sleep 1
# Reboot!
reboot
FIRST

chmod 755 "${TARGET}"/var/firstpost.sh
chmod 644 "${TARGET}"/Library/LaunchDaemons/com.learningobjects.firstpost.plist
chown root:wheel "${TARGET}"/var/firstpost.sh "${TARGET}"/Library/LaunchDaemons/com.learningobjects.firstpost.plist
logger ""
logger "Follow up scripts and LaunchDaemons installed on \"${TARGET}\"; they will run first-thing on reboot."
logger ""
sleep 1

# ----------------------------------------------------------------------------------------
# ------------ Finishing Up --------------------------------------------------------------
# Renames and relocates the log and reboots the machine.
# ----------------------------------------------------------------------------------------

logger "------------ AND IN CLOSING ------------"
logger ""

logger "An installer log can be found at ${TARGET}/${LOGLOC}/ called ${NAME}-${LOG}"
logger ""
logger "This Munki Setup Script will now exit and reboot."
logger ""
cp "${INSTALLERS}"/${LOG} "${TARGET}"/${LOGLOC}/${NAME}-${LOG}
rm "${INSTALLERS}"/${LOG}
chown root:wheel "${TARGET}"/${LOGLOC}/${NAME}-${LOG}
chmod 644 "${TARGET}"/${LOGLOC}/${NAME}-${LOG}

# Re-enable GateKeeper tech; MunkiTools is not signed...
if [ ${OS} == OSX ]; then
	spctl --master-enable
fi

sleep 5
reboot

# Script cobbled together by Douglas Nerad. Any questions please contact him at
#					dnerad[a]learningobjects[p]com or douglas[a]nerad[p]org
# Script version:	1.0 (20150623). Only works on full OSX machine. Includes MunkiTools
#						installation and configuration, MunkiEnroll, admin and user
#						creation and FileVaultMaster key installation. Process includes
#						discovering the script path and renaming the computer. Includes
#						a base set of defaults.
#					1.1 (20150701). Works on Recovery Drive.
#					1.2 (20150710). Cleaned up variables. Creates post-run scripts on
#						target drive if needed.
#					1.3 (20150722). Creates post-run script if installed for both Recovery
#						Drive and/or native boot runs. Fixes machine time stamp in
#						post-run scripts. Default variables now stored in a separate file.
#						More variables are conditionally optional. Can pull MunkiTools
#						from munkibuilds.org if you don't have an installer in hand.
#					1.4 (20150805). Restructured post scripts so that user creation occurs
#						in second post script. Created a function to allow Munki to check,
#						download and install everything during first post script. Minor
#						fixes.
#					1.5 (20150915). Changed dscl -append group to dseditgroup (thanks
#						Thomas Larkin). Changed log location to target drive, but made
#						the location customizable. Fixed user installation logic. Changed
#						post-script section so there's only one set (previously two).
#						Changed user creation to happen after Munki run the first time so
#						global user settings can be applied.