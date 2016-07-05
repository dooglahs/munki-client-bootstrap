#!/bin/bash
# adding -x after "bash" above spits execution to log; useful for diagnosing problems.

# This script is used to bootstrap computers to be managed by an existing Munki instance.
# It also supports installing and configuring FileVault and JumpCloud.

# Script is interactive so pay attention to questions. History at the end.

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
function installPath() {
	[ ${1:0:1} == '/' ] && x=$1 || x=${PWD}/$1
	cd "${x%/*}"
	echo $( pwd -P )/${x##*/}
	cd "${OLDPWD}"
}
INSTALLERS=$( installPath "${BASH_SOURCE[0]}" )
INSTALLERS=${INSTALLERS%/*}

# Script defaults file; mandatory for this script to work.
# NOTE: There are a few other variables to set in the post-run scripts.
if [[ -e "${INSTALLERS}"/munki-client-bootstrap-defaults.txt ]]; then
	source "${INSTALLERS}"/munki-client-bootstrap-defaults.txt
else
	echo "The munki-client-bootstrap-defaults.txt file failed to load. Please check that the file exists and run this script again."
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

# Post file handling, as defined in the defaults file
if [ ${POSTFILE_HANDLING} == "mv" ]; then
	POSTFILE_HANDLING=$( echo "mv" )
else
	POSTFILE_HANDLING=$( echo "rm" )
fi

if [ ${POSTFILE_HANDLING} == "rm" ]; then
	POSTFILE_MV=$( echo "" )
elif [ ${POSTFILE_MV} != "/Users/Shared" ]; then
	POSTFILE_MV=$( echo "${POSTFILE_MV}" )
else
	POSTFILE_MV="/Users/Shared"
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
else
	USER_REALNAME="Setup"
fi
if [[ ${USER_COMPUTER_SAME_NAME} == "yes" ]] || [[ ${USER} == "setup" ]]; then
	COMP_NAME=${USER}
else
	read -p "What should be the computer be named? " COMP_NAME;
	logger ""
fi
if [[ ${JC} == "yes" ]]; then
	read -p "If the computer has an asset tag number please enter now: " TAG_ID;
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

DATE_TIME=$( date )
logger "             Date and Time: ${DATE_TIME}"
logger ""
logger "               Target Path: ${TARGET}"
logger ""
logger "            Installer Path: ${INSTALLERS}"
logger ""

if [[ ${USER} == "setup" ]]; then
	logger "     Computer and Username: ${COMP_NAME}"
	if [[ -n ${TAG_ID} ]]; then
		logger "                 Asset Tag: ${TAG_ID}"
	fi
else
	logger "                 Real Name: ${USER_REALNAME}"
	logger "            Short Username: ${USER}"
	logger "             Computer Name: ${COMP_NAME}"
	if [[ ${JC} == "yes" ]]; then
		logger "                 Asset Tag: ${TAG_ID}"
	fi
fi
logger ""
read -p "Do those settings look correct? Type yes or no and press [ENTER]: " CORRECT;
logger ""
if [[ ${CORRECT} =~ ^([nN][oO]|[nN])$ ]]; then
	read -p "Is the date or time correct? Type yes or no and press [ENTER]: " TIME_CORRECT;
	logger ""
	if [[ ${TIME_CORRECT} =~ ^([nN][oO]|[nN])$ ]]; then
		logger "Please enter the correct date and time using the following format"
		logger "   (month)(day)(hour)(minute)(year)"
		logger ""
		logger "Example: September 11th, 2015 at 4:33PM would be: 0911143315"
		logger ""
		read -p "What is the correct date and time? " DATE_TIME;
		${SUDO} date ${DATE_TIME}
	else
		logger "Let's debug the script or run it again."
		logger ""
		exit 0
	fi
else
	logger "Settings are correct."
fi
logger ""

${SUDO} scutil --set ComputerName "${COMP_NAME}"
${SUDO} scutil --set HostName "${COMP_NAME}"
${SUDO} scutil --set LocalHostName "${COMP_NAME}"
${SUDO} defaults write "${TARGET}"/Library/Preferences/SystemConfiguration/com.apple.smb.server NetBIOSName -string "${COMP_NAME}"
logger "Computer is now called \"${COMP_NAME}\"."
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
	logger ""
	rm munkitools2-latest.pkg
	cd "${OLDPWD}"
else
	logger "Munki Client already installed."
fi
# Kick off Munki on next reboot
touch "${TARGET}/Users/Shared/.com.googlecode.munki.checkandinstallatstartup"
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
	IDENTIFIER="${COMP_NAME}";
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
		ADMIN_POST_FLAG="yes"
#		if [ -e "${TARGET}"/var/db/.AppleSetupUser ]; then
#			rm "${TARGET}"/var/db/.AppleSetupUser
#		fi
		touch "${TARGET}"/var/db/.AppleSetupDone
		logger "\"${ADMIN}\" user will be created."
	fi
	logger ""
	sleep 1
else
	ADMIN_POST_FLAG="no"
fi

# ----------------------------------------------------------------------------------------
# ------------ USER CREATION -------------------------------------------------------------
# This section checks to see if a user already exists on the machine. If not it flags for
# the user to be installed in post scripts.
# ----------------------------------------------------------------------------------------

if [[ ${USER_CREATE} == "yes" ]] && [[ ${USER} != "setup" ]]; then
	HAS_USER=$( ls "${NODE_SEARCH}" | grep ${USER} )
	if [[ -n ${HAS_USER} ]]; then
		logger "\"${USER}\" user exists."
		USER_POST_FLAG="no"
	else
		USER_POST_FLAG="yes"
#		if [ -e "${TARGET}"/var/db/.AppleSetupUser ]; then
#			rm "${TARGET}"/var/db/.AppleSetupUser
#		fi
		touch "${TARGET}"/var/db/.AppleSetupDone
		logger "\"${USER}\" user will be created."
	fi
	logger ""
	sleep 1
else
	USER_POST_FLAG="no"
fi

# ----------------------------------------------------------------------------------------
# ------------ FILEVAULTMASTER KEY -------------------------------------------------------
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
	FV_AUTH_RESTART="yes"
	sleep 1
elif [[ -e "${TARGET}"/Library/Keychains/FileVaultMaster.keychain ]]; then
	FV_AUTH_RESTART="yes"
else
	FV_POST_FLAG="no"
	FV_AUTH_RESTART="no"
fi

# ----------------------------------------------------------------------------------------
# ------------ POST RUN SCRIPT CREATION --------------------------------------------------
# Creates some scripts to run on reboot if needed.
# NOTE ABOUT THIS POST RUN SCRIPT. Script is built into /usr/local. If you would prefer
#  	another location search and replace /usr/local with your selection, i.e. /etc/local/bin.
# ----------------------------------------------------------------------------------------

logger "------------ POST RUN SCRIPT CREATION ------------"
logger ""

if [ -z ${TZ} ]; then
	TZ="GMT"
fi

# ----------------------------------------------------------------------------------------
# ------------ FileVault AuthRestart plist -----------------------------------------------

# This conditional section in the event that FileVault is already enabled on the machine
if [[ ${FV_AUTH_RESTART} == "yes" ]]; then
	cat > "${TARGET}"/usr/local/fvauthrestart.plist <<AUTHRESTART
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Password</key>
	<string>${ADMIN_PWD}</string>
</dict>
</plist>
AUTHRESTART

chmod 644 "${TARGET}"/usr/local/fvauthrestart.plist
chown root:wheel "${TARGET}"/usr/local/fvauthrestart.plist
fi

# ----------------------------------------------------------------------------------------
# ------------ Post LaunchDaemon ---------------------------------------------------------

cat > "${TARGET}"/Library/LaunchDaemons/com.learningobjects.pstscrpt.plist <<FIRSTLD
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>com.learningobjects.pstscrpt</string>
	<key>ProgramArguments</key>
	<array>
		<string>/usr/local/pstscrpt.sh</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
</dict>
</plist>
FIRSTLD

chmod 644 "${TARGET}"/Library/LaunchDaemons/com.learningobjects.pstscrpt.plist
chown root:wheel "${TARGET}"/Library/LaunchDaemons/com.learningobjects.pstscrpt.plist

# ----------------------------------------------------------------------------------------
# ------------ Post Script ---------------------------------------------------------------

cat > "${TARGET}"/usr/local/pstscrpt.sh <<PSTSCRPT
#!/bin/bash
# Post script, run as a second stage of the munki-client-bootstrap script.
logger(){
	echo "\$1" >> "${LOGLOC}/${COMP_NAME}-${LOG}"
}
logger "------------ PSTSCRPT: Post script running ------------"
sudo languagesetup -langspec en
sleep 2
sudo defaults write /Library/Preferences/.GlobalPreferences AppleLanguages "(en, ja, fr, de, es, it, nl, sv, nb, da, fi, pt, zh-Hans, zh-Hant, ko)"
sudo defaults write /Library/Preferences/.GlobalPreferences AppleLocale "en_US"
sudo defaults write /Library/Preferences/.GlobalPreferences Country "en_US"
PSTSCRPT

# Set the computer name if script run originally from Recovery Drive
if [ ${OS} == RD ]; then
	cat >> "${TARGET}"/usr/local/pstscrpt.sh <<PSTSCRPT
# Name the computer
sudo scutil --set ComputerName "${COMP_NAME}"
sudo scutil --set HostName "${COMP_NAME}"
sudo scutil --set LocalHostName "${COMP_NAME}"
sudo defaults write /Library/Preferences/SystemConfiguration/com.apple.smb.server NetBIOSName -string "${COMP_NAME}"
logger "Computer name set to \"${COMP_NAME}\"."
sudo systemsetup -settimezone "${TZ}"
sudo ntpdate -u time.apple.com
sleep 10
PSTSCRPT
fi

# Conditionally add computer to wifi network
if [[ -n ${WIFI_NETWORK} ]]; then
	cat >> "${TARGET}"/usr/local/pstscrpt.sh <<PSTSCRPT
# Get wifi working
INTERFACE=\$( networksetup -listallhardwareports | grep -E '(Wi-Fi|AirPort)' -A 1 | grep en. | awk -F': ' '{print \$2}' )
networksetup -addpreferredwirelessnetworkatindex \${INTERFACE} ${WIFI_NETWORK} 0 ${WIFI_SEC} "${WIFI_PWD}"
logger "Wifi network ${WIFI_NETWORK} setup."
sleep 20
PSTSCRPT
fi

# Let Munki run till it is done
cat >> "${TARGET}"/usr/local/pstscrpt.sh <<PSTSCRPT
# Delay the script until Managed Software is done running
logger "Munki is installing packages..."
munkiRun(){
	ps axg | grep -v grep | grep 'MunkiStatus' > /dev/null
}
MUNKI_RUN_TRY=0
while munkiRun; do
	sleep 20
	MUNKI_RUN_TRY=\$((MUNKI_RUN_TRY+20))
	logger "...Munki ran for \${MUNKI_RUN_TRY} seconds."
done
PSTSCRPT

# Conditionally append admin installation if needed
if [[ ${ADMIN_POST_FLAG} == "yes" ]]; then
	cat >> "${TARGET}"/usr/local/pstscrpt.sh <<PSTSCRPT
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
logger "Admin user -${ADMIN}- created."
if [ ! -e /var/db/.AppleSetupDone ]; then
	sudo touch /var/db/.AppleSetupDone
fi
PSTSCRPT
fi

# Conditionally append user installation if needed
if [[ ${USER_POST_FLAG} == "yes" ]]; then
	cat >> "${TARGET}"/usr/local/pstscrpt.sh <<PSTSCRPT
NUID=\$( dscl . -list /Users UniqueID | awk '{print \$2}' | sort -ug | tail -1 )
NUID=\$((NUID+1))
. /etc/rc.common
sudo dscl . create /Users/${USER}
sudo dscl . create /Users/${USER} RealName "${USER_REALNAME}"
sudo dscl . passwd /Users/${USER} "${USER_PWD}"
sudo dscl . create /Users/${USER} UniqueID \${NUID}
sudo dscl . create /Users/${USER} PrimaryGroupID 20
sudo dscl . create /Users/${USER} UserShell /bin/bash
sudo dscl . create /Users/${USER} NFSHomeDirectory /Users/${USER}
sudo dseditgroup -o edit -a ${USER} -t user admin
sudo dscl . -create /Users/${USER} picture "/Library/User Pictures/LO/de-icon.tif"
logger "User -${USER}- created."
if [ ! -e /var/db/.AppleSetupDone ]; then
	sudo touch /var/db/.AppleSetupDone
fi
PSTSCRPT
fi

# JumpCloud installation and machine configuration
if [[ ${JC} == "yes" ]]; then
cat >> "${TARGET}"/usr/local/pstscrpt.sh <<PSTSCRPT
logger "JumpCloud configuration..."
# Install the JumpCloud Client if it isn't installed already
if [ ! -f /opt/jc/jcagent.conf ]; then
	OLDPWD="\$( pwd )"
	logger "...OLDPWD is \${OLDPWD}"
	sudo mkdir -p /opt/jc
	logger "...Made /opt/jc directory."
	sudo chmod -R 755 /opt
	sudo chown root:wheel /opt
	sudo chown root:admin /opt/jc
	logger "...Fixed permissions for /opt/jc."
	sudo cat > /opt/jc/agentBootstrap.json <<JCBOOTSTRAP
	{
		"publicKickstartUrl": "https://kickstart.jumpcloud.com:443",
		"privateKickstartUrl": "https://private-kickstart.jumpcloud.com:443",
		"connectKey": "${CONNECT_KEY}"
	}
JCBOOTSTRAP
	sudo chown root:admin /opt/jc/agentBootstrap.json
	sudo chmod 644 /opt/jc/agentBootstrap.json
	logger "...Made the agentBootstrap.json file and fixed its permissions."
	sleep 1
	cd /tmp
	sudo curl -O "https://s3.amazonaws.com/jumpcloud-windows-agent/production/jumpcloud-agent.pkg"
	logger "...Downloaded the jumpcloud-agent.pkg installer."
	sudo installer -allowUntrusted -pkg jumpcloud-agent.pkg -target "${TARGET}" 2> /dev/null
	JC_TRY=0
	until [ -f /opt/jc/jcagent.conf ]; do
		sleep 5
		JC_TRY=\$((JC_TRY+5))
		logger "......Waited \${JC_TRY} seconds for JumpCloud to install."
	done
	logger "...Installed the JumpCloud client."
	sudo ${POSTFILE_HANDLING} jumpcloud-agent.pkg "${POSTFILE_MV}"
	sleep 1
	cd "\${OLDPWD}"
fi
# System-specific JC API calls
SYSTEM_KEY=\$( sudo cat /opt/jc/jcagent.conf | awk -F":" -v RS="," '\$1~/"systemKey"/ {print \$2}' | sed 's/^"//' | sed 's/".*//' );
logger "...This computer's systemKey is: \${SYSTEM_KEY}"
# Set the system name in JC
curl -iq -d "{ \"displayName\" : \"COMP: ${TAG_ID} ${USER_REALNAME}\"}" -X 'PUT' -H 'Content-Type: application/json' -H 'Accept: application/json' -H "x-api-key: ${API_KEY}" "https://console.jumpcloud.com/api/systems/\${SYSTEM_KEY}"
logger "...Set the system name in JC to COMP: ${TAG_ID} ${USER_REALNAME}."
sleep 3
# Add the system to the OSX tag
curl -iq -d "{ \"tags\" : [\"${JC_TAG}\"]}" -X 'PUT' -H 'Content-Type: application/json' -H 'Accept: application/json' -H "x-api-key: ${API_KEY}" "https://console.jumpcloud.com/api/systems/\${SYSTEM_KEY}"
logger "...Added the computer to the ${JC_TAG} JC tag."
sleep 3
# User-and-name-specific JC API calls
if [[ ${USER_POST_FLAG} == "yes" ]]; then
			#Currently the user must already exist in JumpCloud. Eventually I want it to create the
			#	user if they are not in JumpCloud but the API does not allow the setting of a password
			#	so I'll leave the code for now.
			#USER_FOUND=\$( sudo curl --silent -d "{\"filter\": [{\"username\" : \"${USER}\"}]}" -H 'Content-Type: application/json' -H "x-api-key: ${API_KEY}" "https://console.jumpcloud.com/api/search/systemusers" --stderr - | sed 's/{.*totalCount":"*\([0-9a-zA-Z]*\)"*,*.*}/\1/' );
			#if [[ \${USER_FOUND} == 1 ]]; then
			#	logger "...${USER_REALNAME} exists in JumpCloud."
			#else
			#	logger "...We will now add ${USER_REALNAME} to JumpCloud."
			#	curl -d "{\"email\" : \"${USER}${EMAIL_DOMAIN}\", \"username\" : \"${USER}\", \"password\" : \"${USER_PWD}\" }" -X 'POST' -H 'Content-Type: application/json' -H 'Accept: application/json' -H "x-api-key: ${API_KEY}" "https://console.jumpcloud.com/api/systemusers"
			#	sleep 3
			#fi
			#logger ""
	USER_KEY=\$( curl -v --silent -d "{\"filter\": [{\"username\" : \"${USER}\"}]}" -H 'Content-Type: application/json' -H "x-api-key: ${API_KEY}" "https://console.jumpcloud.com/api/search/systemusers" --stderr - | awk -F":" -v RS="," '\$1~/"_id"/ {print \$2}' | sed 's/^"//' | sed 's/".*//' | awk -F"\n" -v RS="" '{print \$NF}' );
	logger "...${USER_REALNAME}'s userKey is: \${USER_KEY}"
	# In JumpCloud add the user to the machine
	curl -d "{ \"add\" : [\"\${SYSTEM_KEY}\"], \"remove\" : [] }" -X 'PUT' -H 'Content-Type: application/json' -H 'Accept: application/json' -H "x-api-key: ${API_KEY}" "https://console.jumpcloud.com/api/systemusers/\${USER_KEY}/systems"
	logger "...Added ${USER_REALNAME} as a user of this machine in JC."
	sleep 3
	# In JumpCloud make the user admin on the machine
	curl -d "{ \"\${SYSTEM_KEY}\": { \"_id\": \"sudoerID\", \"sudoEnabled\": true, \"sudoWithoutPassword\": false }}" -X 'PUT' -H 'Content-Type: application/json' -H 'Accept: application/json' -H "x-api-key: ${API_KEY}" "https://console.jumpcloud.com/api/systemusers/\${USER_KEY}/systems/sudoers"
	logger "...Made ${USER_REALNAME} admin on their own machine via JC."
	sleep 3
fi
PSTSCRPT
fi

# Conditionally use fdesetup to activate FileVault
# Creates user plist for fdesetup
if [[ ${FV_POST_FLAG} == "yes" ]]; then
	cat > "${TARGET}"/usr/local/fvusers.plist <<PSTSCRPTFVU
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
<key>Username</key>
<string>${ADMIN}</string>
<key>Password</key>
<string>${ADMIN_PWD}</string>
PSTSCRPTFVU
	HAS_USER=$( ls "${NODE_SEARCH}" | grep ${USER} )
	if [[ -z ${HAS_USER} ]] && [[ ${USER_CREATE} == "yes" ]] && [[ ${USER} != "setup" ]]; then
		cat >> "${TARGET}"/usr/local/fvusers.plist <<PSTSCRPTFVU
<key>AdditionalUsers</key>
<array>
    <dict>
        <key>Username</key>
        <string>${USER}</string>
        <key>Password</key>
        <string>${USER_PWD}</string>
    </dict>
</array>
PSTSCRPTFVU
	fi
	cat >> "${TARGET}"/usr/local/fvusers.plist <<PSTSCRPTFVU
</dict>
</plist>
PSTSCRPTFVU
	cat >> "${TARGET}"/usr/local/pstscrpt.sh <<PSTSCRPT
chmod 644 /usr/local/fvusers.plist
chown root:wheel /usr/local/fvusers.plist
fdesetup enable -keychain -inputplist < /usr/local/fvusers.plist -norecoverykey
logger "Encryption has been enabled."
sleep 10
${POSTFILE_HANDLING} /usr/local/fvusers.plist "${POSTFILE_MV}"
sleep 1
PSTSCRPT
fi

cat >> "${TARGET}"/usr/local/pstscrpt.sh <<PSTSCRPT
# Remove first post script files
${POSTFILE_HANDLING} /Library/LaunchDaemons/com.learningobjects.pstscrpt.plist "${POSTFILE_MV}"
sleep 1
${POSTFILE_HANDLING} /usr/local/pstscrpt.sh "${POSTFILE_MV}"
sleep 1
logger "These post script files have been ${POSTFILE_HANDLING}-ed."
PSTSCRPT


if [[ ${FV_AUTH_RESTART} == "yes" ]]; then
	cat >> "${TARGET}"/usr/local/pstscrpt.sh <<PSTSCRPT
# Allow fdesetup authrestart
fdesetup authrestart -inputplist < /usr/local/fvauthrestart.plist
${POSTFILE_HANDLING} /usr/local/fvauthrestart.plist "${POSTFILE_MV}"
logger "fdesetup authrestart"
PSTSCRPT
else
	cat >> "${TARGET}"/usr/local/pstscrpt.sh <<PSTSCRPT
# Reboot!
reboot
logger "Standard reboot."
PSTSCRPT
fi

chmod 755 "${TARGET}"/usr/local/pstscrpt.sh
chown root:wheel "${TARGET}"/usr/local/pstscrpt.sh

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

logger "An installer log can be found at ${TARGET}/${LOGLOC}/ called ${COMP_NAME}-${LOG}"
logger ""
logger "This Munki Setup Script will now exit and reboot."
logger ""
cp "${INSTALLERS}"/${LOG} "${TARGET}/${LOGLOC}/${COMP_NAME}-${LOG}"
rm "${INSTALLERS}"/${LOG}
chown root:wheel "${TARGET}/${LOGLOC}/${COMP_NAME}-${LOG}"
chmod 644 "${TARGET}/${LOGLOC}/${COMP_NAME}-${LOG}"

# Re-enable GateKeeper tech; MunkiTools is not signed...
if [ ${OS} == OSX ]; then
	spctl --master-enable
fi

sleep 5
if [[ ${FV_AUTH_RESTART} == "yes" ]] && [ ${OS} == OSX ]; then
	# Allow fdesetup authrestart
	fdesetup authrestart -inputplist < /usr/local/fvauthrestart.plist
else
	reboot
fi

# Script cobbled together by Douglas Nerad. Any questions please contact him at
#						dnerad[a]learningobjects[p]com or douglas[a]nerad[p]org
# Script versions:	1.0 (20150623). Only works on full OSX machine. Includes MunkiTools
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
#					1.6 (20160606). Fixed issue where Filevault might already be enabled
#						on the machine preventing smooth reboots of post-run scripts.
#						Fixed an issue where if date was off by too much the we couldn't
#						curl the latest Munki build (SSL fail). Changed post script
#						default directory from /var to /usr/local to avoid OS 10.11 SIP
#						problems. Added variables on how to handle post script files.
#					1.7 (20160613). Refactored post scripts creation to a single stage.
#						Added JumpCloud support; to create the user in JC (needs work!),
#						install the client, add the machine, add to a default tag, add the
#						user to the machine, and make the user admin of their machine.
#					1.8 (2016xxxx). Need to readdress the munki-enroll process.