#!/bin/bash

ENABLE_DEBUG_LOGS=true
ENABLE_ERROR_LOGS=true
ENABLE_DISCORD_LOGS=true
ENABLE_DISCORD_ERROR_LOGS=false
ENABLE_FILE_LOGS=true

# Source in user profile in case this is a non-interactive thingy; consider separating into a different thing
source "$HOME/.profile"

if [ -z "${script_locks_path}" ]; then
        echo "ERROR: script_locks_path undefined! You can define this in your user profile."
        exit
fi

if [ -z "${patches_root_path}" ]; then
        echo "ERROR: patches_root_path undefined! You can define this in your user profile."
        exit
fi

if [ -z "${patches_data_path}" ]; then
        echo "ERROR: patches_data_path undefined! You can define this in your user profile."
        exit
fi

if [ -z "$updaterepos_webhook_url" ]; then
        echo "WARNING: updaterepos_webhook_url undefined! Nothing will be logged to discord/webhook."
        ENABLE_DISCORD_LOGS=false
fi

if [ -z "$error_webhook_url" ]; then
        echo "WARNING: error_webhook_url undefined! LOGERR will not be logged to discord/webhook."
        ENABLE_DISCORD_ERROR_LOGS=false
fi

mkdir -p "${script_locks_path}"
lockfile="${script_locks_path}/updaterepos.lock"
{
  if ! flock -n 9
  then
    exit 1
  fi

#LOG_DIR="${script_logs_path}/updaterepos"
LOG_DIR="${patches_root_path%/}/logs"
LOG_FILE="${LOG_DIR%/}/updaterepos.log"
UPTODATE_FILE="${LOG_DIR}/UpToDate.txt"
UPDATED_FILE="${LOG_DIR}/Updated.txt"
UPDATEFAILED_FILE="${LOG_DIR}/UpdateFailed.txt"

# Ensure log and lock dirs exist
mkdir -p "$LOG_DIR"

# Cleanup previous runs
rm "$UPTODATE_FILE" "$UPDATED_FILE" "$UPDATEFAILED_FILE" "$LOG_FILE"

set -o pipefail

# Log a message to a webhook URL in Discord format
# @param $1 URL to log to
# @param $2 Username to log as
# @param $3 Message to log
DISCORD_LOG() {
        WEBHOOK_URL=$1
        USERNAME=$2
        shift
        shift

        curl -H "Content-Type: application/json" -X POST -d "{\"username\": \"${USERNAME}\", \"embeds\": [ { \"description\": \"${@}\"}]}" "${WEBHOOK_URL}"
}

# Log message to both console and Discord
# @param $1 Whether or not to log this message to discord
# @param $2 Whether or not to log this message to log file
# $param $3 Message to log
PRINT_LOG() {
        LOG_TO_DISCORD=$1
        LOG_TO_FILE=$2
        shift
        shift

        echo "${@}"

        if $LOG_TO_DISCORD; then
                DISCORD_LOG "$updaterepos_webhook_url" "Patch" "$@"
        fi

        if $LOG_TO_FILE; then
                echo "$@" >> ${LOG_FILE}
        fi
}

LOGMSG() {
        PRINT_LOG $ENABLE_DISCORD_LOGS $ENABLE_FILE_LOGS "$@"
}

LOGDBG() {
        if $ENABLE_DEBUG_LOGS; then
                PRINT_LOG false $ENABLE_FILE_LOGS "$@"
        fi
}

LOGERR() {
        if $ENABLE_ERROR_LOGS; then
                PRINT_LOG false $ENABLE_FILE_LOGS "$@"
        fi

        if $ENABLE_DISCORD_ERROR_LOGS; then
                DISCORD_LOG "${error_webhook_url}" "Patch" "$@"
        fi
}

# Syncs a single mirror
SYNCMIRRORTHREAD() {
        ADDRESS=$(echo "${2}" | awk -F@ '{print $2}' | awk -F: '{print $1}')
        LOG_FILE=${LOG_FILE}.${ADDRESS}.log
        rm "$LOG_FILE"

        RSYNC_OUT=$(rsync -rptDhiz --timeout=30 --delete --delete-excluded ${3} -e "ssh -p ${1}" "${patches_data_path}/" ${2} | tee -a ${LOG_FILE})
        RSYNC_STATUS=$?
        if [ ${RSYNC_STATUS} -eq 0 ]
        then
                # Success
                if [[ -z "${RSYNC_OUT}" ]]
                then
                        # Success and no updates
                        LOGDBG "${ADDRESS} is already up to date"
                        echo -n "${ADDRESS} " >> "$UPTODATE_FILE"
                else
                        # Success and updated
                        LOGMSG "Finished sync to: ${ADDRESS}"
                        echo -n "${ADDRESS} " >> "$UPDATED_FILE"
                fi

        else
                # Failed
                LOGERR "Failed to sync to: ${ADDRESS} (status code ${RSYNC_STATUS})"
                echo -n "${ADDRESS} " >> "$UPDATEFAILED_FILE"
        fi
}

# Kicks off a full sync to a background thread
SYNCMIRROR() {
        SYNCMIRRORTHREAD "$@" &
        let "++pidlen"
        pids[${pidlen}]=$!
}

# Read in and sync each mirror
mirror_list=$(grep -vE "[[:space:]]*#" "${patches_root_path}/updaterepos.targets")

while read -r line
do
        # File in format: 'PORT PATH'
        ssh_port=$(echo "$line" | awk '{ print $1 }')
        ssh_path=$(echo "$line" | awk '{ print $2 }')
        exclude_from=$(echo "$line" | awk '{ print $3 }')

        if [[ ! -z $exclude_from ]]; then
                exclude_from="--exclude-from=${patches_root_path}/${exclude_from}"
        fi

        SYNCMIRROR "$ssh_port" "$ssh_path" "$exclude_from"
done < <(echo "$mirror_list")

# wait for all pids
for pid in ${pids[*]}; do
        wait $pid
done

# Read in outputs
if [[ -f $UPTODATE_FILE ]]; then
        UPTODATE="$(cat ${UPTODATE_FILE})"
fi

if [[ -f $UPDATED_FILE ]]; then
        UPDATED="$(cat ${UPDATED_FILE})"
fi

if [[ -f $UPDATEFAILED_FILE ]]; then
        UPDATEFAILED="$(cat ${UPDATEFAILED_FILE})"
fi

# We're done syncing; log/notify
if [[ -z ${UPDATED} ]]; then
        LOGDBG "No patch repos successfully updated"

        if [[ ! -z ${UPDATEFAILED} ]]; then
                LOGERR "No patch repos updated; repos failed to update: ${UPDATEFAILED}"
        fi

elif [[ ! -z ${UPDATEFAILED} ]]; then
        LOGERR "The following repos are now up to date: ${UPDATED}; repos failed to update: ${UPDATEFAILED}; repos already up-to-date: ${UPTODATE}"
else
        LOGMSG "All patch repos are now up to date; repos already up-to-date: ${UPTODATE}"
fi

} 9>"$lockfile"
