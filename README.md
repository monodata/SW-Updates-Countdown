# SW-Updates-Countdown
SW Updates requiring a reboot will present the user with a prompt of how long to defer the reboot

Uses JamfHelper to display a message to users with options of how long to defer a reboot.
Uses either the jamf binary to carry out the reboot or creates a LaunchDaemon with a specified time to reboot.

If the option selected is 4 hours, a reminder with a countdown that cannot be dismissed is shown 1 hour before. If 10 hours is selected, then a reminder is displayed 4 hours before

