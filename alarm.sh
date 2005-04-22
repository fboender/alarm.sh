#!/bin/bash
#
# alarm.sh
#
# Small shell script to inform you of events at certain times.
#
# Example uses:
#  $ alarm.sh -n -t "20:15" -m "Meet and greet with John in 15 minutes" 
#  $ alarm.sh -n -r -t "friday" -m "Friday beer-drinking competition tonight"
#  $ alarm.sh -c -i2 -t "thursday" -m "Thursday beer-drinking competition tonight"
#
# Start the script with --daemon under X to start the alarm service that will 
# warn you
#
#-----------------------------------------------------------------------------
#
# Copyright (C), 2005 Ferry Boender. Released under the General Public License
# For more information, see the COPYING file supplied with this program.                                                          
#
# Todo:
# - Error checking
#   - Input dates
#   - Availability of tools (xmessage, dialog, gdialog)
#   - Availability of X
# - Some recurring dates are not handled yet: "1 may 20:00" fails
# - GTK / dialog frontend.
# - Daemon kill mode
# - More
#

DEFAULT_A_FILE="$HOME/.alarms"
DEFAULT_ACT="help"

function help() {
	echo "alarm.sh - Alert service client and daemon                     "
	echo "                                                               "
	echo "Usage: alarm.sh [ACTION] [PARAMETERS]                          "
	echo "                                                               "
	echo "Actions:                                                       "
	echo "  -n, --new    (-t, -m)       Create a new alert at timespec   "
	echo "  -c, --change (-i, -t, -m)   Change the alert identified by id"
	echo "  -d, --delete (-i)           Delete the alert identified by id"
	echo "  -l, --list   ([-i])         List alert(s)                    "
	echo "      --daemon                Start the alert daemon           "
	echo "                                                               "
	echo "Parameters                                                     "
	echo "  -t, --timespec TIMESPEC     Date/time specification at which "
	echo "                              the alert should be triggered    "
	echo "  -m, --message MESSAGE       Message that should be displayed "
	echo "  -i, --id ID                 Alarm ID that should be changed, "
	echo "                              deleted or listed                "
	echo "  -f, --file FILE             Use FILE as alarm file instead of"
	echo "                              the default ~/.alarms            "
	echo "  -r, --repeat                Repetative alarm                 "
}

function error() {
	echo $1
}

function alarmNew() {
	if [ -z "$A_TIMESPEC" ]; then
		error "No timespec specified."
		return
	fi
	if [ -z "$A_MESSAGE" ]; then
		error "No message specified."
		return
	fi
	
	if [ -z "$A_REPEAT" ]; then
		A_TIMESTAMP=`date -d"$A_TIMESPEC" +"%Y-%m-%d %H:%M" 2>/dev/null`
		if [ "$?" -eq "1" ]; then
			echo "Invalid date/time specified";
		fi
		A_MODE='n'
	else
		A_TIMESTAMP="$A_TIMESPEC";
		A_MODE='r'
	fi

	# Get a new id if need be
	if [ -z "$A_ID" ]; then
		if [ -e "$A_FILE" ]; then
			MAXID=`sort -n "$A_FILE" 2>/dev/null | tail -n1 | cut -d"|" -f1`
			if [ -z "$MAXID" ]; then
				MAXID="0"
			fi
			A_NEWID=`expr $MAXID + 1`
		else
			A_NEWID="1"
		fi
	else
		A_NEWID="$A_ID"
	fi
	
	echo "$A_NEWID|$A_MODE|$A_TIMESTAMP|$A_MESSAGE" >> $A_FILE
	echo "New alert added (ID $A_NEWID)"

}

function alarmChange() {
	if [ -z "$A_ID" ]; then
		error "No alarm ID specified."
		return
	fi
	if [ -z "$A_TIMESPEC" ]; then
		error "No timespec specified."
		return
	fi
	if [ -z "$A_MESSAGE" ]; then
		error "No message specified."
		return
	fi
	
	alarmDelete
	alarmNew
}

function alarmDelete() {
	if [ -z "$A_ID" ]; then
		error "No alarm ID specified."
		return
	fi
	
	TMPFILE=`tempfile`
	
	grep -v "^$A_ID|" $A_FILE > $TMPFILE 2>/dev/null 
	mv $TMPFILE $A_FILE

	echo "Deleted alert (ID $A_ID)"
}

function alarmList() {
	echo " id | m |                 date | message"
	echo "----+---+----------------------+---------------------------------------------"
	
	cat $A_FILE 2>/dev/null | while read; do
		IFS_OLD=$IFS # Work around for non-working -d param on STUPID Bash read
		IFS="|"
		echo "$REPLY" | { read A_ID A_MODE A_TIMESTAMP A_MESSAGE; # Work around for sub-shell
			if [ "$A_MODE" == "n" ]; then
				A_TIME=`date -d"$A_TIMESTAMP" +"%d %b %Y %H:%M"`
				A_MODE=" "
			else 
				A_TIME="$A_TIMESTAMP"
			fi

			printf "%3s | $A_MODE | %20s | $A_MESSAGE\n" "$A_ID" "$A_TIMESTAMP"
		}
		IFS=$IFS_OLD
	done;
}

function daemon() {
	while true; do
		# Current time
		N_TIMESTAMP=`date +"%Y%m%d%H%M"`
		
		cat $A_FILE 2>/dev/null | while read; do
			IFS_OLD=$IFS # Work around for non-working -d param on STUPID Bash read
			IFS="|"
			echo "$REPLY" | { read A_ID A_MODE A_TIMESTAMP A_MESSAGE; # Work around for sub-shell
				A_TIMESTAMP=`date -d"$A_TIMESTAMP" +"%Y%m%d%H%M"`
				
				if [ "$A_MODE" == "n" ]; then
					# Non-repetitive alarm; alert when overdue
					if [ "$N_TIMESTAMP" -ge "$A_TIMESTAMP" ]; then
						xmessage "$A_MESSAGE"
						alarmDelete "$A_ID"
					fi
				else
					# Repetitive alarm; show only once at exact time
					if [ "$N_TIMESTAMP" -eq "$A_TIMESTAMP" ]; then
						xmessage "$A_MESSAGE"
					fi
				fi
			}
			IFS=$IFS_OLD
		done;
		sleep 60
	done
}


########################################################################
# Parse commandline options
########################################################################

TEMP=`getopt -o ncdlt:m:i:f:rh --long new,change,delete,list,timespec:,message:,id:,file:,repeat,daemon,help \
     -n 'alarm.sh' -- "$@"`

if [ $? != 0 ] ; then echo "Terminating..." >&2 ; exit 1 ; fi

eval set -- "$TEMP"

while true ; do
	case "$1" in
		-n|--new)      ACT="new";      shift 1 ;;
		-c|--change)   ACT="change";   shift 1 ;;
		-d|--delete)   ACT="delete";   shift 1 ;;
		-l|--list)     ACT="list";     shift 1 ;;
		   --daemon)   ACT="daemon";   shift 1 ;;
		-t|--timespec) A_TIMESPEC=$2;  shift 2 ;;
		-m|--message)  A_MESSAGE=$2;   shift 2 ;;
		-i|--id)       A_ID=$2;        shift 2 ;;
		-f|--file)     A_FILE=$2;      shift 2 ;;
		-r|--repeat)   A_REPEAT="r";   shift 1 ;;
		-h|--help)     FLAG_HELP=1;    shift 1 ;;
		--)                            shift 1; break ;;
		*)             echo "Internal error!" ; exit 1 ;;
	esac
done

# Default action
if [ -z "$ACT" ]; then
	ACT="$DEFAULT_ACT"
fi
# Default alarm file
if [ -z "$A_FILE" ]; then
	A_FILE="$DEFAULT_A_FILE"
fi

case "$ACT" in
	new)     alarmNew ;;
	change)  alarmChange ;;
	delete)  alarmDelete ;;
	list)    alarmList ;;
	help)    help ;;
	daemon)  daemon ;;
esac

exit

A_FILE=$1

ALARM=`date -d"+1 minute" +"%Y%m%d%H%M"`

while true; do
	# Current time
	N_TIMESTAMP=`date +"%Y%m%d%H%M"`
	
	# Alert times
	cat $A_FILE | while read; do
		A_TIME=`echo "$REPLY" | cut -d"|" -f1`
		A_MSG=`echo "$REPLY" | cut -d"|" -f2-`
		A_TIMESTAMP=`date -d"$A_TIME" +"%Y%m%d%H%M"`

		# DEBUGGING
		echo "$A_TIME - $A_MSG - $A_TIMESTAMP - $N_TIMESTAMP";

		# Trigger any alerts if need be
		if [ "$N_TIMESTAMP" -ge "$A_TIMESTAMP" ]; then
			A_NICETIME=`date -d"$A_TIME" +"%d %m %Y %H:%M"`
			TMPFILE=`tempfile`

			# Remove entry from file
			grep -v "$REPLY" $A_FILE > $TMPFILE
			mv $TMPFILE $A_FILE

			# Trigger alert
			xmessage "$A_NICETIME : $A_MSG"
		fi
	done;
	sleep 30
done
