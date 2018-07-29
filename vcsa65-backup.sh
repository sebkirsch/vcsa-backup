#!/bin/bash
#######################################################
#
#      vCenter 6.5 Appliance Backup Script
#
#      Author:   Sebastian Kirsch
#      Date:     10.02.2018
#
#      Description:
#      Creates a scp backup job via the REST api of the
#      VCSA
#
#      Script based on:
#      https://pubs.vmware.com/vsphere-6-5/index.jsp?topic=%2Fcom.vmware.vsphere.vcsapg-rest.doc%2FGUID-222400F3-678E-4028-874F-1F83036D2E85.html
#
#######################################################
#
# BKP_HOST_USER    must exists on the backup server
# BKP_HOST_FOLDER  must exists on the backup server
#
#######################################################
#
####################  C O N F I G  ####################
#
# vCenter settings
VC_ADDRESS="vcenter.domain.tld"
VC_USER="administrator@vsphere.local"
VC_PASSWORD="ADMIN-PASSWORD"
#
# Backup settings
BKP_HOST="backupserver.domain.tld"
BKP_HOST_USER="vcenter"
BKP_HOST_PASS="USER-PASSWORD"
BKP_HOST_FOLDER="/backups/vcsa"
BKP_ENCRYPTION_PASS="YOUR-HIGH-SECURE-FILE-ENCRYPTION-PASSWORD"
#
# Path settings
#BACKUP_PATH="/backups"
LOG_PATH="/var/log/backups"
TMP="/tmp"
#
#######################################################
#
#
######################  M A I N  ######################
JOBID=0
STATE="INPROGRESS"
STARTTIME=$(date +'%d.%m.%Y - %H:%M:%S')
TIMESTAMP=$(date +%Y%m%d%H%M%S)
BACKUP_LOG="$LOG_PATH/backup_vcsa_$TIMESTAMP.log"

echo -e "Starting backup job - $TIMESTAMP\n-----" >> $BACKUP_LOG

# Create temp files
COOKIEFILE="$TMP/cookie-$TIMESTAMP.txt"
REQUESTFILE="$TMP/request-$TIMESTAMP.json"
RESPONSEFILE="$TMP/response-$TIMESTAMP.txt"
touch $COOKIEFILE $REQUESTFILE $RESPONSEFILE
chmod 640 $COOKIEFILE $REQUESTFILE $RESPONSEFILE

# Create json request body
cat << EOF >$REQUESTFILE
{ "piece":
   {
        "backup_password":"$BKP_ENCRYPTION_PASS",
        "location_type":"SCP",
        "comment":"Automatic daily backup - $TIMESTAMP",
        "parts":["seat"],
        "location":"scp://$BKP_HOST$BKP_HOST_FOLDER/$TIMESTAMP",
        "location_user":"$BKP_HOST_USER",
        "location_password":"$BKP_HOST_PASS"
    }
}
EOF

# Output script header
echo ""
echo "***********************************************************"
echo "*           vCenter 6.5 Appliance Backup Script           *"
echo "***********************************************************"
echo ""

# Authenticate and save cookie
echo -n " * Requesting authentication token..."
TOKEN=$(curl -s -S -k -u "$VC_USER:$VC_PASSWORD" --cookie-jar $COOKIEFILE -X POST "https://$VC_ADDRESS/rest/com/vmware/cis/session" 2>> $BACKUP_LOG)
echo -e "Token Request:\n$TOKEN\n" >> $BACKUP_LOG
if [[ "$TOKEN" =~ ^\{\"value\"\:\"([a-z0-9]+)\"\}$ ]]; then
	echo -e "DONE"
else
	echo "FAILED"
	echo -e "\n   See log file for more information:\n   $BACKUP_LOG\n\n   Aborting...\n"
	rm -f $COOKIEFILE $REQUESTFILE $RESPONSEFILE
	exit 1
fi

# Start the backup job
echo -n " * Starting backup job..."
curl -s -S -k --cookie $COOKIEFILE -H 'Accept:application/json' -H 'Content-Type:application/json' -X POST --data @$REQUESTFILE "https://$VC_ADDRESS/rest/appliance/recovery/backup/job" &>> $RESPONSEFILE
echo -e "Backup job request:\n$(cat $REQUESTFILE)\n" >> $BACKUP_LOG
echo -e "Backup job response:\n$(cat $RESPONSEFILE)\n" >> $BACKUP_LOG

# Get backup job id from response
JOBID=$(awk '{if (match($0,/"id":"\w+-\w+-\w+"/)) print substr($0, RSTART+6, RLENGTH-7);}' $RESPONSEFILE)
if [[ "$JOBID" =~ ^([0-9]+)\-([0-9]+)\-([0-9]+)$ ]]; then
	echo "DONE"
	echo -e "\n Backup job ID: $JOBID\n"
else
	echo "FAILED"
	echo -e "\n   See log file for more information:\n   $BACKUP_LOG\n\n   Aborting...\n"
	rm -f $COOKIEFILE $REQUESTFILE $RESPONSEFILE
	exit 2
fi

# Check progress of backup job
echo -e " -----------------------------------------------------------"
echo -e "  Backup job is running now. This may take a while. Please\n  be patient."
echo -e " -----------------------------------------------------------\n"
echo -e "Backup job progress:\n\n" >> $BACKUP_LOG
until [ "$STATE" != "INPROGRESS" ]; do
	sleep 10s
	curl -s -S -k --cookie $COOKIEFILE -H 'Accept:application/json' --globoff "https://$VC_ADDRESS/rest/appliance/recovery/backup/job/$JOBID" &> $RESPONSEFILE
	echo -e "$(cat $RESPONSEFILE)\n" >> $BACKUP_LOG
	STATE=$(awk '{if (match($0,/"state":"\w+"/)) print substr($0, RSTART+9, RLENGTH-10);}' $RESPONSEFILE)
        echo -n "."
done
echo ""
STOPTIME=$(date +'%d.%m.%Y - %H:%M:%S')

# Show job details
echo ""
echo "***********************************************************"
echo "  Backup job finish state: $STATE"
echo ""
echo "  Start time: $STARTTIME"
echo "  Stop time: $STOPTIME"
echo ""
echo "  Backup folder: /$BKP_HOST_FOLDER/$TIMESTAMP"
echo "  Backup log: $BACKUP_LOG"
echo "***********************************************************"
echo ""

######################   E N D   ######################
echo -e "\nBackup job finished.\n" >> $BACKUP_LOG
echo -e "-----\n\n" >> $BACKUP_LOG
rm -f $COOKIEFILE $REQUESTFILE $RESPONSEFILE
chmod 640 $BACKUP_LOG
exit 0


#EOF
