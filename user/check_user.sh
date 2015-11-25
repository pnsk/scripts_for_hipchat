#!/bin/bash
###################################
# check HipChat account
# author: okuda_junko
###################################

HOME='/usr/local/sh/hipchat/user'
FILE_NAME=`basename $0 .sh`

DATEFORMAT=+%Y-%m-%d-%H-%M
DATE=`date ${DATEFORMAT}`

LOG_FILE="/tmp/${FILE_NAME}_${DATE}.log"
ERROR_LOG_FILE="/tmp/error-${FILE_NAME}_${DATE}.log"
LOG_MESSAGE=''
LOCKFILE="${HOME}/${FILE_NAME}.pid"

# notification mail address
MAILADDRESS='hogehoge@mail'

LDAP_IP='ldapip'
LDAPSEARCH='/usr/bin/ldapsearch'
LDAP_BASEDN='dc=dummy'
LDAP_DESCRIPTION='dummy-description'

HIPCHAT_URL='https://api.hipchat.com/v1'
HIPCHAT_TOKEN='dummy-token'
HIPCAHT_USER_DELETED='null' #true or null
DELETE_FLAG=0

USER_LIST="${HOME}/user_list-${DATE}.cvs"
USER_WHITE_LIST="${HOME}/white_list.cvs"
VALID_USER="${HOME}/valid_${DATE}.csv"
INVALID_USER="${HOME}/invalid_${DATE}.csv"

#----------------------------------
#    functions
#----------------------------------
function sendMail() {
	MAIL_SUBJECT=$1
	MAIL_BODY=$2
	mail -s "${MAIL_SUBJECT}" ${MAILADDRESS} < ${MAIL_BODY}
}

function executionLog() {
        LOG_MESSAGE=$1
        echo '-----------------------------------------------------------------------------------' | tee -a ${LOG_FILE}
        echo  `date +'%Y-%m-%d %H:%M:%S'` ${LOG_MESSAGE}                                           | tee -a ${LOG_FILE}
        echo '-----------------------------------------------------------------------------------' | tee -a ${LOG_FILE}
}

function simpleLog() {
        LOG_MESSAGE=$1
	echo  "${LOG_MESSAGE}"                                           | tee -a ${LOG_FILE}
}

function errorLog() {
	LOG_MESSAGE=$1
echo '-----------------------------------------------------------------------------------' | tee -a ${LOG_FILE} ${ERROR_LOG_FILE}
cat << 'EOF' | tee -a ${LOG_FILE} ${ERROR_LOG_FILE}
 _______ .______      .______        ______   .______
|   ____||   _  \     |   _  \      /  __  \  |   _  \
  __  |  |_)  |    |  |_)  |    |  |  |  | |  |_)  |
|   __|  |      /     |      /     |  |  |  | |      /
|  |____ |  |\  \----.|  |\  \----.|  `--'  | |  |\  \----.
|_______|| _| `._____|| _| `._____| \______/  | _| `._____|

EOF

echo '-----------------------------------------------------------------------------------' | tee -a ${LOG_FILE} ${ERROR_LOG_FILE}
echo "error message :  ${LOG_MESSAGE}"                                                     | tee -a ${LOG_FILE} ${ERROR_LOG_FILE}
echo '-----------------------------------------------------------------------------------' | tee -a ${LOG_FILE} ${ERROR_LOG_FILE}
}

#----------------------------------
#    main
#----------------------------------
executionLog 'sart to check hipchat accounts'

simpleLog 'start to check and create lock file'
if [ -f ${LOCKFILE} ];then
        errorLog 'a lock file already exists.' 
        errorLog 'stop checking hipchat accounts'
	sendMail 'ERROR: hipchat user check.' "${ERROR_LOG_FILE}"
        exit 1
else
        touch ${LOCKFILE}
fi

executionLog 'start to get valid hipchat users from API'
curl -Ss "${HIPCHAT_URL}/users/list?auth_token=${HIPCHAT_TOKEN}&include_deleted=1" | jq -r '.users[] | [.email , .is_deleted] | @csv' | sed -e 's/\"//g' > ${USER_LIST}
executionLog 'finished to get valid hipchat users from API'

executionLog 'start to check accounts by LDAP'
while 
	read USER_INFO
do
	USER_EMAIL=`echo "${USER_INFO}" | awk -F, '{print $1}'`
	DELETE_FLAG=`echo "${USER_INFO}" | awk -F, '{print $2}'`

	if [ USER_EMAIL = '' ];then continue;  fi #HipChat API rarely returns null as email. maybe bug....?

	${LDAPSEARCH} -LLL -x -h ${LDAP_IP} -b "${LDAP_BASEDN}" "(&(email=${USER_EMAIL})(description=${LDAP_DESCRIPTION}))" | grep email | grep "${USER_EMAIL}" > /dev/null
        if [ `echo $?` -eq 0 ]; then
		if [ ${DELETE_FLAG} = 1 ]
		then
			HIPCAHT_USER_UNDELETED=`curl -Ss -X POST "${HIPCHAT_URL}/users/undelete?auth_token=${HIPCHAT_TOKEN}&user_id=${USER_EMAIL}" | jq -r '.undeleted'`
			if [ ${HIPCAHT_USER_UNDELETED} = true ]
			then
				simpleLog "finished undelete-> ${USER_EMAIL}"
                		echo "${USER_EMAIL}" | tee -a  ${VALID_USER}
			else
				errorLog  "failed to udelete-> ${USER_EMAIL}"
			fi
		fi
        else
		grep "${USER_EMAIL}" ${USER_WHITE_LIST} > /dev/null
        	if [ `echo $?` -eq 0 ]
        	then
                	simpleLog "skip checking not invalid user:  ${USER_EMAIL}" 
                	continue
        	fi

                if [ ${DELETE_FLAG} = 0 ]
                then
			simpleLog "start delete-> ${USER_EMAIL}"
			HIPCAHT_USER_DELETED=`curl -Ss -X POST "${HIPCHAT_URL}/users/delete?auth_token=${HIPCHAT_TOKEN}&user_id=${USER_EMAIL}" | jq -r '.deleted'`
			if [ ${HIPCAHT_USER_DELETED} = true ]
			then
				simpleLog "finished delete-> ${USER_EMAIL}"
                		echo "${USER_EMAIL}" | tee -a  ${INVALID_USER}
			else
				errorLog  "failed to delete-> ${USER_EMAIL}"
			fi
                fi
        fi
done < ${USER_LIST}

if [ -f ${VALID_USER} ]
then
	simpleLog 'send email about valid users list.'
	sendMail "undeleted valid users. ${DATE}" "${VALID_USER}"
	simpleLog "delete hipchat user list ${VALID_USER}"
	rm ${VALID_USER}
fi

if [ -f ${INVALID_USER} ]
then
	simpleLog 'send email about invalid users list.'
	sendMail "deleted invalid users. ${DATE}" "${INVALID_USER}"
	simpleLog "delete hipchat user list ${INVALID_USER}"
	rm ${INVALID_USER}
fi

executionLog 'finihed to check accounts by LDAP'

simpleLog "delete hipchat user list ${USER_LIST}"
rm ${USER_LIST} 

if [ -f ${ERROR_LOG_FILE} ]
then
	simpleLog 'send email about ERROR'
	sendMail 'ERROR: hipchat user check.' "${ERROR_LOG_FILE}"
fi

simpleLog 'delete lock file.'
rm ${LOCKFILE}

executionLog 'compleated!!!'
exit 0
