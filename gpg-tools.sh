#!/bin/bash
set -u

TEMP_DIR="/tmp/gpg"
ANSWER="${TEMP_DIR}/answer.$$"

MASTER_KEYS_DIR="${TEMP_DIR}/keys_master"
EXPORT_KEYS_DIR="${TEMP_DIR}/keys_export"

DEVICES_BASE_PATH="/dev/disk/by-id"
MASTER_KEY_PREFIX=${USER}

MASTER_KEY_PRIVATE="${MASTER_KEYS_DIR}/${MASTER_KEY_PREFIX}-private.key"
MASTER_KEY_PUBLIC="${MASTER_KEYS_DIR}/${MASTER_KEY_PREFIX}-public.key"
GPG_KEY_REALNAME=${GPG_KEY_REALNAME:-}
GPG_KEY_EMAIL=${GPG_KEY_EMAIL:-}
GPG_KEY_COMMENT=${GPG_KEY_COMMENT:-}
GPG_KEY_PASSWORD=${GPG_KEY_PASSWORD:-}
GPG_KEY_PASSWORD_RETYPE=${GPG_KEY_PASSWORD_RETYPE:-}

declare -A DEVICE_IDS

update_device_ids() {
  for device_link in $(find ${DEVICES_BASE_PATH} -name "usb-*"); do
    local device_id=$(basename ${device_link}) 
    device_id=${device_id:4}
    device=$(readlink -f ${device_link})
    DEVICE_IDS[${device}]=${device_id}
  done
}

get_devices_menuitems() {
  for device in "${!DEVICE_IDS[@]}"
  do
    echo "${device} ${DEVICE_IDS[${device}]}"
  done
}

is_mounted() {
  df | grep $1  2>&1 /dev/null
  echo $?
}

mount_target_device() {
    mount_path=$1

    if [ ${#DEVICE_IDS[@]} -eq 0 ] ; then
      dialog --msgbox "no usable devices found" 10 40
      return
    fi

    dialog --backtitle "Device selection" \
           --title "Select USB device to mount" \
           --cancel-label "Cancel" \
           --menu " " 17 60 10 \
           $(get_devices_menuitems) 2> $ANSWER
    opt=${?}
    if [ $opt != 0 ]; then rm $ANSWER; exit; fi
    device=$(cat $ANSWER)
    case $device in
        Quit) rm $ANSWER; exit;;
        *)
          if [ $(is_mounted ${device}) ] ; then
            if sudo umount ${device} ; then
              dialog --msgbox "failed to unmount ${device}" 10 78
              return
            fi
          fi

          if sudo mount ${device} ${mount_path} ; then
            dialog --msgbox "mounted ${device} at ${mount_path}" 10 78
          else
            dialog --msgbox "failed to mount ${device} at ${mount_path}" 10 78
          fi
          ;;
    esac
}

generate_master_key() {
cat >${TEMP_DIR}/master_key_script << EOF
     %echo Generating a basic OpenPGP key
     Key-Type: DSA
     Key-Length: 1024
     Subkey-Type: ELG-E
     Subkey-Length: 1024
     Name-Real: Joe Tester
     Name-Comment: with stupid passphrase
     Name-Email: joe@foo.bar
     Expire-Date: 0
     Passphrase: abc
     %commit
     %echo done"
EOF
gpg --homedir ${TEMP_DIR} --batch --gen-key ${TEMP_DIR}/master_key_script
	sleep 10
}

GPG_KEY_FORM_ERRORS=""
validate_gpg_key_form_data() {
  GPG_KEY_FORM_ERRORS="fdsfdsfds"
  echo 0
}
enter_master_key_data() {
  dialog --title "GPG key data" \
       --ok-label "Ok" \
       --insecure "$@" \
       --mixedform "Enter data needed by GPG to generate your key" \
    20 50 0 \
        "Realname        :" 1 1 "${GPG_KEY_REALNAME}" 1 20 20 0 0 \
        "E-Mail          :" 2 1 "${GPG_KEY_EMAIL}" 2 20 25 0 0 \
        "Comment         :" 3 1 "${GPG_KEY_COMMENT}" 3 20 20 0 0 \
        "Password        :" 4 1 "${GPG_KEY_PASSWORD}" 4 20  20 0 1 \
        "Retype Password :" 5 1 "${GPG_KEY_PASSWORD_RETYPE}" 5 20  20 0 1 2> ${TEMP_DIR}/gpg_form_data.$$
  if [ $? -eq 0 ] ; then
    form_data=( $(cat ${TEMP_DIR}/gpg_form_data.$$ | sed -e 's/^/=/') )
    GPG_KEY_REALNAME=${form_data[0]:1}
    GPG_KEY_EMAIL=${form_data[1]:1}
    GPG_KEY_COMMENT=${form_data[2]:1}
    GPG_KEY_PASSWORD=${form_data[3]:1}
    GPG_KEY_PASSWORD_RETYPE=${form_data[4]:1}
    if [ $(validate_gpg_key_form_data) -ne 0 ] ; then
      dialog --msgbox "${GPG_KEY_FORM_ERRORS}" 10 78
    fi
  fi
}

main_menu() {
    dialog --backtitle "GPG master key editor" \
           --title "Main Menu" \
           --cancel-label "Quit" \
           --menu "Move using [UP] [DOWN], [Enter] to select" 17 70 10\
        MasterKeyStorage "Mount USB drive for master key storage"\
        ExportKeyStorage "Mount USB drive for export key storage"\
        EnterMasterKeyData "Enter all data needed for key generation"\
        GenerateMasterKey "Generate a new master keypair"\
        Info "Show information"\
        Quit "Exit demo program" 2> $ANSWER
    opt=${?}
    if [ $opt != 0 ]; then rm $ANSWER; exit; fi
    menuitem=$(cat $ANSWER)
    case $menuitem in
        MasterKeyStorage) mount_target_device ${MASTER_KEYS_DIR};;
        KeyStorage) mount_target_device ${EXPORT_KEYS_DIR};;
        GenerateMasterKey) generate_master_key;;
        EnterMasterKeyData) enter_master_key_data;;
        Info) information;;
        Quit)
          exit;;
    esac
}

cleanup_environment() {
  sync
  sleep 1
  sync
  sleep 1
  if [ $(is_mounted ${MASTER_KEYS_DIR}) -eq 0 ] ; then
    sudo umount -f ${MASTER_KEYS_DIR}
  fi
  if [ $(is_mounted ${EXPORT_KEYS_DIR}) -eq 0 ] ; then
    sudo umount -f ${EXPORT_KEYS_DIR}
  fi
  sleep 1
  sudo umount -f ${TEMP_DIR}
  rm -rf ${TEMP_DIR}
}
trap cleanup_environment EXIT

if [ -d ${TEMP_DIR} ] ; then
  echo "temp dir '${TEMP_DIR} already exists, aborting"
  exit 1
else
  set -e
  mkdir -p ${TEMP_DIR}
  sudo mount -t tmpfs -o size=2M tmpfs ${TEMP_DIR}
  sudo chown $USER ${TEMP_DIR}
  mkdir -p ${MASTER_KEYS_DIR}
  mkdir -p ${EXPORT_KEYS_DIR}
  set +e
fi


while true; do
  update_device_ids
  main_menu
done

#gpg --homedir ${MASTER_KEY_DIR} --import  ${MASTER_KEY_PUBLIC} ${MASTER_KEY_PRIVATE}
#gpg --homedir ${MASTER_KEY_DIR} --edit-key ${KEY_ID} 
#gpg --homedir ${MASTER_KEY_DIR} ${KEY_ID} --export-secret-subkeys
#gpg --import subkeys
#rm -rf ${MASTER_KEY_DIR}
