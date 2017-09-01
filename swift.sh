#!/bin/bash

APP=$0

## auth info
OS_AUTH_URL="http://api.test.com:35357/v3"
OS_USERNAME="userName"
OS_PASSWORD="userPassowrd"
OS_PROJECT_NAME="projectName"
OS_PROJECT_DOMAIN_ID="projectDomainId"
OS_USER_DOMAIN_ID="userDomainId"
publicURL="http://swift.test.com:8080/v1/AUTH_projectId"

getToken() {
    token=$(curl -i -s -X POST $OS_AUTH_URL/auth/tokens?nocatalog -H "Content-Type: application/json" -d \
    '{ "auth":
        { "identity":
	    { "methods": ["password"],"password": {"user": {"domain": {"id": "'"$OS_USER_DOMAIN_ID"'"},"name": "'"$OS_USERNAME"'", "password": "'"$OS_PASSWORD"'"} } },
	  "scope": { "project": { "domain": { "id": "'"$OS_PROJECT_DOMAIN_ID"'" }, "name":  "'"$OS_PROJECT_NAME"'" } }
        }
     }' | grep X-Subject-Token | awk '{print $NF}')
     expireTimestamp=$(echo "$(date +"%s") + 3600" | bc)
}

displayEx() {
    case "${1}" in
	list)
	    echo ""
	    echo " # Lists the containers for the account or the objects for a container."
	    echo " Usage: ${APP} list [--lh] [container]"
	    ;;
	upload)
	    echo ""
	    echo " # Uploads specified files and directories to the given container."
	    echo " Usage: ${APP} upload <container> <file_or_directory> [<file_or_directory>] [...]"
	    ;;
	download)
	    echo ""
	    echo " # Download objects from containers."
	    echo " Usage: ${APP} download <container> [<object>]"
	    ;;
	delete)
	    echo ""
	    echo " # Delete a container or objects within a container."
	    echo " Usage: ${APP} delete <container> [<object>]"
	    ;;
	stat)
	    echo ""
	    echo " #  Displays information for the account, container,or object."
	    echo " Usage: ${APP} stat [<container>] [<object>]"
	    ;;
	post)
	    echo ""
	    echo " "
	    echo " "
    esac

}

jsonValue() {
    KEY=${1}
    num=${2}
    awk -F"[,:}]" '{for(i=1;i<=NF;i++){if($i~/'$KEY'\042/){print $(i+1)}}}' | tr -d '"' | sed -n ${num}p
}

calcSize() {
    size=${1}
    if [ $size -ge 1073741824 ]; then
	size=$(echo "scale=2;$size/1073741824"| bc)G
    elif [ $size -ge 1048576 ]; then
	size=$(echo "scale=2;$size/1048576"| bc)M
    elif [ $size -ge 1024 ]; then
	size=$(echo "scale=2;$size/1024" | bc)K
    fi
    echo $size
}

post() {
    if [ $# -eq 2 ]; then
        curl -s $publicURL/${2} -X PUT -H "X-Auth-Token: $token"
        exit 0
    else
	displayEx ${1}
    fi
}



list() {
    if [ $# -eq 1 ]; then
        curl -s $publicURL?format=text -X GET -H "X-Auth-Token: $token"
    elif [ ${2} = "--lh" ]; then
	if [ $# -eq 2 ]; then
	    result=$(curl -s $publicURL?format=json -X GET -H "X-Auth-Token: $token")
	    read -r -a names <<< $(echo $result | jsonValue name)
	    read -r -a counts <<< $(echo $result | jsonValue count)
	    read -r -a bytes <<< $(echo $result | jsonValue bytes)
	    for i in "${!names[@]}"
	    do
		size=$(calcSize "${bytes[i]}")
		printf "%-10s %-10s %s\n" "${counts[i]}" "${size}" "${names[i]}"
	    done
	elif [ $# -eq 3 ]; then
            result=$(curl -s $publicURL/${3}?format=json -X GET -H "X-Auth-Token: $token")
            read -r -a names <<< $(echo $result | jsonValue name)
            read -r -a bytes <<< $(echo $result | jsonValue bytes)
            for i in "${!names[@]}"
            do
                size=$(calcSize "${bytes[i]}")
                printf "%-10s %s\n" "${size}" "${names[i]}"
            done
        else
            displayEx ${1}
            exit 1
        fi
    elif [ $# -eq 2 ] && [ ${2} != "--lh" ]; then
	curl -s $publicURL/${2}?format=text -X GET -H "X-Auth-Token: $token"
    else
	displayEx ${1}
	exit 1
    fi
}

upload() {
    if [ $# -eq 3 ]; then
        if [ -d ${3} ]; then
            files=$(find ${3} -type f -print0|xargs -0 -n 1 echo )
            for object in ${files}
            do
                currentTimestamp=$(date +"%s")
                timeDiff=$(echo "${expireTimestamp} - ${currentTimestamp}" | bc)
                if [ ${timeDiff} -lt 300 ]; then
                    getToken
                else
                    curl -s $publicURL/${2}/${object} -X PUT -T ${object} -H "X-Auth-Token: $token"
                    printf "%s\n" "${object}"
                fi
            done
            exit 0
        fi
        object=$(echo ${3} | sed 's/^\.\///')
        curl -s $publicURL/${2}/${object} -X PUT -T ${3} -H "X-Auth-Token: $token"
	exit 0
    else
        displayEx ${1}
    fi
}

download() {
    checkContainer=$(curl -I -s $publicURL/${2} --head -H "X-Auth-Token: $token" | head -n 1 | awk '{print $2}')
    if ! [[ ${checkContainer} =~ 2.. ]]; then
        echo "Container '${2}' not found"
        exit 1
    fi

    if [ $# -eq 3 ]; then
        curl -s $publicURL/${2}/${3} -X GET -H "X-Auth-Token: $token" -o ${3}
        exit 0
    elif [ $# -eq 2 ]; then
        objects=$(curl -s $publicURL/${2}?format=text -X GET -H "X-Auth-Token: $token")
        for object in ${objects}
        do
            prefix=$(dirname ${object})
            if [ ! -d ${prefix} ]; then
        	mkdir -p ${prefix}
            fi
            curl -s $publicURL/${2}/${object} -X GET -H "X-Auth-Token: $token" -o ${object}
            printf "%s\n" "${object}"
        done
        exit 0
    else
	displayEx ${1}
    fi
}

delete() {
    checkContainer=$(curl -I -s $publicURL/${2} --head -H "X-Auth-Token: $token" | head -n 1 | awk '{print $2}')
    if ! [[ ${checkContainer} =~ 2.. ]]; then
        echo "Container '${2}' not found"
        exit 1
    fi
    if [ $# -eq 3 ]; then
        checkObject=$(curl -s $publicURL/${2}/${3} --head -H "X-Auth-Token: $token" | head -n 1 | awk '{print $2}')
        if ! [[ ${checkObject} =~ 2.. ]]; then
             echo "Error Deleting: ${3}: "Object \'${3}\' not found" container: ${2}"
             exit 1
        fi
        curl -s $publicURL/${2}/${3} -X DELETE -H "X-Auth-Token: $token"
        printf "%s\n" "${3}"
        exit 0
    elif [ $# -eq 2 ]; then
        objects=$(curl -s $publicURL/${2}?format=text -X GET -H "X-Auth-Token: $token")
        for object in ${objects}
        do
             curl -s $publicURL/${2}/${object} -X DELETE -H "X-Auth-Token: $token"
             printf "%s\n" "${object}"
        done
             objects=$(curl -s $publicURL/${2}?format=text -X GET -H "X-Auth-Token: $token")
             if [ -z ${objects} ]; then
                curl -s $publicURL/${2} -X DELETE -H "X-Auth-Token: $token"
             else
                echo "Error Deleting: ${2}: "Container \'${2}\' not empty""
             fi
        exit 0
    else
        displayEx ${1}
    fi
}

stat() {
    if [ $# -eq 3 ]; then
        checkObject=$(curl -s $publicURL/${2}/${3} --head -H "X-Auth-Token: $token" | head -n 1 | awk '{print $2}')
        if ! [[ ${checkObject} =~ 2.. ]]; then
             echo "Object HEAD failed:"Object \'${3}\' not found." container: ${2}"
             exit 1
        fi
        curl -I -s $publicURL/${2}/${3} --head -H "X-Auth-Token: $token" | grep -v "HTTP/1.1"
        exit 0
    elif [ $# -eq 2 ]; then
	checkContainer=$(curl -I -s $publicURL/${2} --head -H "X-Auth-Token: $token" | head -n 1 | awk '{print $2}')
	if ! [[ ${checkContainer} =~ 2.. ]]; then
	    echo "Container '${2}' not found"
	    exit 1
	fi
	curl -I -s $publicURL/${2} --head -H "X-Auth-Token: $token" | grep -v "HTTP/1.1"
        exit 0
    else
        curl -I -s $publicURL --head -H "X-Auth-Token: $token" | grep -v "HTTP/1.1"
    fi
}





case "${1}" in

# container create
post) post $@
    ;;
# obejct list
list) list $@
    ;;
# file upload
upload) upload $@
    ;;
# object download
download) download $@
    ;;
# container and object delete
delete) delete $@
    ;;
# container and object stat
stat) stat $@
    ;;
-h|--help|*) echo "Invalid option! Usage : ./swift.sh <option> [container_name] [file_name]"
   echo ""
   echo " ## Option Description ## "
   option="list upload download delete stat"
   for op in ${option}; do
        displayEx ${op}
   done
   ;;
esac
