# munki-client-bootstrap.sh
On a Mac computer with an existing Munki Server, this bash script installs MunkiTools client and its base settings, then optionally munki-enroll, the local admin and user, FileVault and a few other items.

## Specifically...
# munki-client-bootstrap.sh follows this workflow:

1: If figures out if you are on a locally booted Mac or the Recovery Drive.

2: It figures out some default paths (specifically to the script and to the Target Drive)

3: It asks you a couple questions to sort out the local user.

4: It then uses settings to:
- Install the MunkiTools client and set default preferences so it works.
- Optionally does munki-enroll.
- Optionally creates a local admin (if not extant).
- Optionally creates the user (if not extant).
- Optionally installs FileVault Masterkey and encrypts with local admin and user enabled.

Some of these actions occur in embedded postscripts.

This is an early version (but not the earliest!) but works well in house. See Caveats below.

## Use Cases

- With fresh out-of-the-box Macs I boot up on the Recovery Drive, run the script and can have the computer ready to go with all apps (with Munki), updates, user and local admin, encryption and many base settings in <20 minutes.
- With an existing computer I can enroll it with Munki, insure there's a local admin, update all software and updates and have it encrypted in <15 minutes.
- If I need to wipe a computer and reinstall it I can boot from a Install OS X Yosemite partition, wipe the drive, reinstall and run the first bullet point once done; this process takes <30 minutes.
- If I need to transfer ownership of a computer the script does that, too, by changing the computer name, updating the ClientIdentifier (and creating a manifest if needed), installing and updating the software and creating the new user.

## Usage

Create a drive storage with a folder that contains the following:
- this script; make sure it is executable!
- the script defaults file, *filled out with your settings*
- (optional) a MunkiTools installer
- (optional) a folder called FileVaultMaster containing your FileVaultMaster.keychain
- (optional) your local admin installer package

I use a USB stick that has two partitions:
- /Volumes/Install OS X Yosemite (which I keep up to date with the latest Yosemite installer)
- /Volumes/Munki (where I keep the above listed files and folders)

On the Recover Drive fire up Terminal, `cd` to the folder with the script and then

`./munki-client-bootstrap.sh`

On an existing booted up OSX computer fire up Terminal, `cd` to the folder with the script and then

`sudo ./munki-client-bootstrap.sh`

*On computers that are being staged, create a manifest with base software called "setup" and run the script with the user being called "setup".*

## Why This Script

In my environment it didn't make sense to use Deploy Studio, Imagr or NetBoot; all of our infrastructure is in the cloud (not a single local server!) and I didn't want to create a drive with some of those tools nor maintain a stack of images. Munki is a great packaging system and could handle most of the work if only I could get it bootstrapped properly. I wanted, at base, some of the following:

- I know bash so that's the language I needed to use. Also, python does not run on the Recovery Drive.
- The ability to run it from the Recovery Drive. The meant a rather pared down bash environment as the recovery drive is missing some key binaries that would have made things simpler.
- The ability to run it from a computer that had already been set up (partially or completely).
- The ability to install MunkiTools, enroll the computer with our appropriate munki-enroll environment, encrypt the drive and add the local admin and local user, many of which may or may not already exist on the drive.
- The ability to have the managedsoftwareupdate binary run *before* users were installed so Munki could install some user template preferences.
- Name the computer appropriately to our environment.
- If the computer was being transfered to a new user, to do the work (changing manifest, rename the computer, add the user, install/delete appropriate software).

## Caveats

- Obviously you must be running a Munki server somewhere. If not check out [Munki-In-a Box](https://github.com/tbridge/munki-in-a-box) to get you started.
- You MUST have a network connection to connect to your Munki server (unless you're using [this trick](http://www.jaharmi.com/2015/07/21/munki_trials_with_a_local_repository). The script has optional Wifi settings but a cable is still best.
- If you use Munki-Enroll you should double check the included code as I have made some changes from the default code. You may need to change a few things there.
- I have tried like hell to get the correct AdditionalHttpHeaders into the bash script, but all of the tools available to bash create a hash that is *slightly* different than what Python generates (which is what Munki uses), so you'll have to sort that using Python; see [this](https://github.com/munki/munki/wiki/Using-Basic-Authentication).
- Script currently only checks admin and users in the local node.

## TO DO

- After reboots, find a way to hide the login screen until it's needed.
- Include checks for the admin and user in bound domains (currently only uses local node).
- Locate the primary scripts on a server (so script is centrally maintained) and have a simple local script pull it (either "hdiutil attach URL/script.dmg" or a curl | exec). Idea from [Armin Briegel](http://scriptingosx.com/2015/08/mount-a-dmg-off-a-web-server/).

## Thanks!

Thanks to the OSX-Server IRC for answering questions, especially Greg Neagle and Elliott Jordan. Thanks to Rich Trouton for his FileVault mastery and the logging funcion, to Cody Eding for Munki Enroll (which I seriously hacked apart), to Tim Sutton for MunkBuilds.org. Finally a solo thank you to Greg Neagle for Munki, without which there wouldn't be a point to this script.