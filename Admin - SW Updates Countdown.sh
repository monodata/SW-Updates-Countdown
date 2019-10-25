#!/usr/bin/env bash
#
# set -x
#################################################
: <<'END_COMMENT'

Name:         Admin - SW Updates Countdown.sh
Description:  Software updates requiring a reboot will present user with a prompt 
              to choose when to reboot.
              This writes either a `jamf reboot` command or a LaunchDaemon, depending on 
              the length of deferral.
              Also writes LD to invoke a jamfhelper 1 hour before if delay is 4 & 10 hours

Author:       Chris Jarvis
Date:         28th August 2019
Vers History: 29/08/2019 - 1.0 - Initial
              02/09/2019 - 1.1 - Added utility countdown @ 4 hours
              09/09/2019 - 1.2 - Refactored code 
              13/09/2019 - 1.3 - Added if clause to check for & install updates

END_COMMENT
#################################################
#     PATHS
#################################################
jamfbinary="/usr/local/bin/jamf"
jamfhelperPath="/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper"
mgmtPath="/Library/Application Support/Management"
iconpath="/Library/Application Support/Pashua/icons/config.png"
reboot_ld="/Library/LaunchDaemons/com.jamfhelper.reboot.plist"
rebootfile="/Library/Application Support/Management/restart.sh"
delay1=60
delay2=3600
delay3=14400
delay4=36000

#################################################
#     FUNCTIONS
#################################################

# check if a LaunchDaemon & reboot script already exist. 
# unloads & deletes if they do
check_LD() {
  # if so, unload and delete
  if [[ -f $reboot_ld ]]; then
      /bin/launchctl unload "$reboot_ld"
      /bin/rm -rf "$reboot_ld"
  fi
  if [[ -e "$rebootfile" ]]; then
    /bin/rm -rf "$rebootfile"
  fi
}

# calculates the day/month/hour/minute from delayint
cal_reboot_time() {
  delay=$1
  # Set up time struct for LD
  defercal=$(($(/bin/date +%s) + $delay))
  month=$(/bin/date -j -f "%s" "$defercal" "+%m")
  day=$(/bin/date -j -f "%s" "$defercal" "+%e")
  hour=$(/bin/date -j -f "%s" "$defercal" "+%H")
  minute=$(/bin/date -j -f "%s" "$defercal" "+%M")
}

# jamfhelper to display initial deferal options
initialHUD(){
    message="This machine needs to install security updates which require a reboot:

Choose when to reboot in the options below."
    "$jamfhelperPath" \
    -windowType hud \
    -title "Reboot" \
    -heading "Software Updates" \
    -description "$message" \
    -icon "$iconpath" \
    -button1 "ok" \
    -showDelayOptions "$delay1, $delay2, $delay3, $delay4" # 1 minute, 1 hour, 4 hours, 10 hours
}

# HUD with snooze button & countdown
counterHUD() {
  "$jamfhelperPath" \
  -windowType hud \
  -windowPosition lr \
  -title "$2" \
  -heading "" \
  -description "$3" \
  -icon "$iconpath" \
  -timeout $1 -countdown \
  -countdownPrompt "This machine will reboot in:" \
  -alignCountdown center \
  -lockHUD \
  -button1 "OK" \
  -button2 "Reboot Now"
}

# Displays counterHUD immediately after deferral is chosen
rebootHUD() {

  # Get the reminder time
  remindhour=$(($delayint - $delayhour))

  # convert: seconds -> hours
  remindhour=$(($remindhour / 60 / 60))

  # message = 1 or more hour(s)
  if [[ $remindhour -gt 1 ]]; then
    countHourMSG="$remindhour hours"
  else
    countHourMSG="$remindhour hour"
  fi

  # Display countdown using HUD
  snooze=$(counterHUD $delayint "Software Updates" "Click ok to close. A reminder will appear ${countHourMSG} before automatically rebooting or you can reboot now")

  # if reboot now is clicked
  if [[ $snooze -eq 2 ]]; then
    "$jamfbinary" reboot -minutes 1 -message "This machine will now reboot. Please immediately save your work" -background
  fi
}

# reboot script with settings for shutdown time & jamfhelper countdown
rebootScript() {

  # checks to see if folders/scripts exist & chmod perms
  if [[ ! -d "$mgmtPath" ]]; then
      mkdir "$mgmtPath"
      touch "$mgmtPath/restart.sh"
    /usr/sbin/chown -R root:wheel "$mgmtPath"
    /bin/chmod -r 644 "$mgmtPath"
  fi

# writes heredoc 
/bin/cat <<EOF > "${rebootfile}"
#!/usr/bin/env bash
# set a reboot timer with countdown

while getopts t: option
do
  case \${option}
    in
    t) timer=\${OPTARG};;
  esac
done

timemins=\$((\$timer / 60 ))

"$jamfhelperPath" \
-windowType hud -windowPosition lr \
-title "Software Updates" \
-heading "" -description "" \
-icon "$iconpath" -iconSize 56 \
-timeout \$timer -countdown -countdownPrompt "This machine will reboot in:" -alignCountdown center \
-lockHUD &

shutdown -r +\$timemins
launchctl unload $reboot_ld
/bin/rm $reboot_ld

exit $?
EOF
}

# Launchdaemon for the reboot script
write_LD() {

  # get the calc dates from delayint
  cal_reboot_time $1

# heredoc for launchdaemon
/bin/cat <<EOF > "$reboot_ld"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.jamfhelper.reboot</string>
    <key>LaunchOnlyOnce</key>
    <true/>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>-c</string>
        <string>/Library/Application Support/Management/restart.sh</string>
        <string>-t</string>
        <string>$2</string>
    </array>
    <key>StartCalendarInterval</key>
    <array>
        <dict>
            <key>Month</key>
            <integer>$month</integer>
            <key>Day</key>
            <integer>$day</integer>
            <key>Hour</key>
            <integer>$hour</integer>
            <key>Minute</key>
            <integer>$minute</integer>
        </dict>
    </array>
</dict>
</plist>
EOF
}

# set the permissions of the reboot launchdaemon
reboot_ld_perms() {
    /bin/chmod 644 "$reboot_ld"
    /usr/sbin/chown root:wheel "$reboot_ld"
    /bin/launchctl load "$reboot_ld"
    chmod +x "/Library/Application Support/Management/restart.sh"
}

# check for swu that require reboot
swu_reboot() {
  swu_check=$(softwareupdate -l)
  sw_reboot="$(echo $swu_check | grep restart | grep -v '\*' | cut -d , -f )"
  sw_recom="$(echo $swu_check | grep -v restart)"
}

swu_install() {
  softwareupdate -ia &
}

#################################################
#   OPERATIONS
#################################################
# check if swu need reboot
if [[ $sw_reboot != "" ]]; then
  #display reboot HUD

  # check for previous launchdaemons
  check_LD

  # put the reboot script in place
  rebootScript

  # initialise the HUD prompt
  result=$(initialHUD)

  # create a loop if cancel is clicked
  while [[ $result == *239 ]]; do
      # initialise the prompt
      result=$(initialHUD)
  done

  # get the deferral time
  delayint=$(echo "$result" | /usr/bin/sed 's/.$//')

  # case struct based on time selected
  case $delayint in
        # immediate reboot
        $delay1 )
          counterUT 60 "Software Updates" "" &
          shutdown -r +1
          ;;
        # 1 hour: countdown notification 
        $delay2 )
          counterUT 3600 "Software Updates" "" &
          shutdown -r +60
          ;;
        # 4 hours / 1 hour reminder
        $delay3 )
          # calculate reminder
          delayhour=$(($delayint - 3600))
          # write launchdaemon & perms
          write_LD $delayhour "3600"
          reboot_ld_perms
          # countdown message with immediate reboot option
          rebootHUD $delayint 
          ;;
        # 10 hours / 4 hour reminder
        $delay4 )
          # calculate reminder
          delayhour=$(($delayint - 14400))
          # write launchdaemon & perms
          write_LD "$delayhour" "14400"
          reboot_ld_perms
          # countdown message with immediate reboot option
          rebootHUD $delayint 
          ;;
  esac

  # Install the updates ready for reboot
  softwareupdate -ia

elif [[ $sw_reboot == "" && $sw_recom != "" ]]; then
  #install the recommended updates
  softwareupdate -ia

fi

exit $?
