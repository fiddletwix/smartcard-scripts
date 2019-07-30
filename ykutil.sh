#!/bin/bash

# Bash strict mode. Stolen from multiple locations

#---------------------------------------------------------------------------------------
# Best practices
#---------------------------------------------------------------------------------------
set -euo pipefail # Strict mode
IFS=$'\n\t'       # more strict mode
PS4='+|${LINENO}${FUNCNAME[0]:+ ${FUNCNAME[0]}}|  ' # Improved debugging with -x

# Executables
PIV_TOOL="$(which ykman)"

#---------------------------------------------------------------------------------------
# Debugging and logging defaults
#---------------------------------------------------------------------------------------
DEBUG="false"
LOGFILE=/dev/null

#---------------------------------------------------------------------------------------
# Defaultss for fresh or reset yubikeys
#---------------------------------------------------------------------------------------
DEFAULT_PUK=12345678
DEFAULT_PIN=123456
DEFAULT_MGMT_KEY=010203040506070801020304050607080102030405060708

#---------------------------------------------------------------------------------------
# General defaults for PIV usage
#---------------------------------------------------------------------------------------
ALG=RSA2048
PIV_SLOT=9a

#---------------------------------------------------------------------------------------
# Our PIN and PUK policies
#---------------------------------------------------------------------------------------
MIN_PIN_SIZE=6
MAX_PIN_SIZE=8
MAX_PIN_RETRIES=5
MAX_PUK_RETRIES=1

REPEAT_CHARACTER_CHECK=3 # Max number of repeating character in a PIN
#---------------------------------------------------------------------------------------
# Whether we are going to check to make sure a PIN conforms to any optional policies.
# For examples see functions 'check_repeating_characters' and 'check_char_sequences'
#---------------------------------------------------------------------------------------
PIN_POLICY=1

#---------------------------------------------------------------------------------------
# Our traps
#---------------------------------------------------------------------------------------
trap cleanup EXIT ERR

#---------------------------------------------------------------------------------------
# Start of functions
#---------------------------------------------------------------------------------------
function logit() {
    #===  FUNCTION  ================================================================
    #        NAME:  logit
    # DESCRIPTION: for send parameters only to the globally defined logfile
    #  PARAMETERS: information to be sent to logfile
    #===============================================================================
    echo "$@" >> "$LOGFILE" 2>&1
}

function output() {
    #===  FUNCTION  ================================================================
    #        NAME:  output
    # DESCRIPTION: send parameters to console and globally defined log file
    #  PARAMETERS: information to be sent to console and log file
    #===============================================================================
    echo -e -n "$@" 2>> "$LOGFILE" | tee -a "$LOGFILE"
}

# Simple debugging function.
function debugit() {
    #===  FUNCTION  ================================================================
    #        NAME:  debugit
    # DESCRIPTION: send parameters to console and globally log file if in debug mode
    #  PARAMETERS: information to be sent to console and log file
    #===============================================================================

    if [[ $DEBUG == "true" ]]; then
	echo "$@" 2>> "$LOGFILE" | tee -a "$LOGFILE"
    fi
}

function cleanup() {
    #===  FUNCTION  ================================================================
    #        NAME:  cleanup
    # DESCRIPTION: function called by trap when erroring out or exiting. Removes
    #              temp files
    #  PARAMETERS: ---
    #===============================================================================

    logit "Cleaning up"

    declare -a TEMPFILES
    TEMPFILES=( \
		${PUBKEY:-} \
	      )


    [[ ${#TEMPFILES[@]} -gt 0 ]] && for cleanup_file in ${TEMPFILES[@]}; do
	debugit "processing $cleanup_file"
	if [[ -f ${cleanup_file} ]]; then
	    debugit "Removing $cleanup_file"
	    /bin/rm $cleanup_file
	fi
    done
}

function check_repeating_characters() {
    #===  FUNCTION  ================================================================
    #        NAME:  check_repeating_characters
    # DESCRIPTION: checks for any character repeated 3 or more times ####
    # PARAMETER 1: string to check
    # PARAMETER 2: the max number of times a character can be repeated consecutively
    #              defaults to a global if not passed
    #===============================================================================

    local INPUT="${1}"
    local REPEAT="${2:-$REPEAT_CHARACTER_CHECK}"

    #-------------------------------------------------------------------------------
    # We create a new string based on using sed to replace any character
    # repeated $REPEAT times with a blank string. We then compare this new string
    # with the original.
    #
    # Note: You'll notice the bash arithmetic $((REPEAT - 1)). This is because
    # we are using extended regexes and matching the backref REPEAT-1 times but the
    # original character is already matched once.
    #
    # Here's an Explanation with REPEAT=3 and REPEAT-1=2
    # The expression .\1{$((REPEAT-1)),} is interpolated in bash as .\1{2,} where
    # the \1 matches the wildcard character. Thus the wildcard is matched once so far
    # the {2,} means \1 is matched 2 or more times. Thus if the wildcard '.' is
    # matched once and the \1 is matched twice or more we have the wildcard '.'
    # matched at least 3 times.
    #-------------------------------------------------------------------------------


    #-------------------------------------------------------------------------------
    # downcase the input string and then perform the sed to compare before and after
    #-------------------------------------------------------------------------------
    local string_check=$(echo "$INPUT" | tr '[[:upper:]]' '[[:lower:]]' \
			 | sed -E "s/.\1{$((REPEAT-1)),}//")

    #-------------------------------------------------------------------------------
    # Unexpected error
    #-------------------------------------------------------------------------------
    if [[ $? != "0" ]]; then
	exit 1
    fi

    #-------------------------------------------------------------------------------
    # if the string has been modified a 3 character sequence was detected and removed
    #-------------------------------------------------------------------------------
    if [[ "$string_check" != "$INPUT" ]]; then
	FAIL=1
	return 1
    fi

    return 0
}

function check_char_sequences() {
    #===  FUNCTION  ================================================================
    #        NAME: check_char_sequences
    # DESCRIPTION: Test to see if we have 3 or more consecutive characters in a
    #              given set of sequences
    #  PARAMETERS: ---
    #===============================================================================

    #-------------------------------------------------------------------------------
    # These are the sequences we want to check.  The PIN should not contain
    # 3 consecutive characters from these strings. By default we are using
    # the standard US keyboard (both reading Left to Right as well as Right
    # to Left) to determine our sequences.
    #-------------------------------------------------------------------------------

    local INPUT="${1}"

    declare -a SEQUENCES
    SEQUENCES=( \
		'1234567890-=' \
		'=-0987654321' \
		'qwertyuiop[]' \
		'asdfghjkl;'"'" \
		'zxcvbnm,./' \
		'/.,mnbvcxz' \
		';lkjhgfdsa' \
		'][poiuytrewq' \
    )

    for sequence in ${SEQUENCES[@]}; do

	#-------------------------------------------------------------------------------
	# Get the string length and then calculate the index of the character 3
	# characters from the end to avoid matching the last 1 or 2 characters
	#-------------------------------------------------------------------------------
	local seq_length=${#sequence}
	length_check=$((seq_length - 3))

	#-------------------------------------------------------------------------------
	# Now loop from the start of the string to $length_check to find
	# consecutive characters
	#-------------------------------------------------------------------------------
	for x in $(seq 0 $length_check); do

	    sequence_check="${sequence:$x:3}"
	    logit "Checking sequence ${sequence_check}"

	    #---------------------------------------------------------------------------
	    # Checking if the INPUT contains the three character sequence in a
	    # case insensitive manner.
	    #---------------------------------------------------------------------------
	    shopt -s nocasematch
	    if [[ "$INPUT" =~ "${sequence_check}" ]]; then
	        shopt -u nocasematch
		return 1
	    fi
	    shopt -u nocasematch
	done
    done

    return 0
}

function check_pin_policy() {
    #===  FUNCTION  ================================================================
    #        NAME: check_pin_policy
    # DESCRIPTION: compares the supplied parameter against a series of PIN policies
    # PARAMETER 1: the PIN to check
    #===============================================================================
    ### Ensure a PIN meets our requirements

    local PIN="${1}"

    #-------------------------------------------------------------------------------
    # We verify that we are checking the optional pin policies.
    #-------------------------------------------------------------------------------
    if [[ "$PIN_POLICY" == "0" ]]; then
	return 0
    fi


    #-------------------------------------------------------------------------------
    # Check the pin complies with our various policies
    #-------------------------------------------------------------------------------
    if  ! check_repeating_characters "$PIN"; then
	output "The chosen PIN (${PIN}) contains a character repeated ${REPEAT_CHARACTER_CHECK} or more times (test is case insensitive)\n"
    	return 1
    fi

    if ! check_char_sequences "$PIN"; then
	output "Chosen PIN (${PIN}) contains at least 3 case insensitive consecutive keyboard characters\n"
    	return 1
    fi

    return 0
}


function get_pin() {
    #===  FUNCTION  ================================================================
    #        NAME:  get_pin
    # DESCRIPTION: asks user for a new pin and then checks if the PIN meets our
    #              criteria
    # PARAMETER 1: a string that is evaulated as variable passed by reference.
    #              passes the value of the PIN the user supplied
    #===============================================================================

    local PIN=''
    output "You need to set a new PIN for your yubikey.  The PIN must be ${MIN_PIN_SIZE}-${MAX_PIN_SIZE} characters long.\n"

    #-------------------------------------------------------------------------------
    # Only state the optional PIN policies if we are enforcing them.
    #-------------------------------------------------------------------------------
    if [[ "$PIN_POLICY" == "1" ]]; then
	output "Your PIN choices have the following requirements:"
	output "Cannot have any character repeat ${REPEAT_CHARACTER_CHECK} or more times consecituvely\n"
	output "Cannot have any 3 characters that are in sequence on the keyboard (either forward or backward) Ex: dfg or mnb\n"
	output "All requirement checks are done case insensitive\n"
    fi

    #-------------------------------------------------------------------------------
    # Perform a while loop to get a PIN from the user and confirm the PIN. We loop
    # until a valid PIN is entered and confirmed
    #-------------------------------------------------------------------------------
    while true; do
	output "Choose new pin: "
	read -s PIN
	output "\n"

	output "Confirm pin: "
	read -s CONFIRM_PIN
	output "\n"

	if [[ "$PIN" != "$CONFIRM_PIN" ]]; then
	    output "PINs do not match\n"
	elif [[ ${#PIN} -lt $MIN_PIN_SIZE ]] || [[ ${#PIN} -gt $MAX_PIN_SIZE ]]; then
	    output "PIN must be 6-8 numbers in length\n"
	elif check_pin_policy $PIN; then
	    debugit "New PIN: ${PIN}"
	    debugit "Confirmed PIN: ${CONFIRM_PIN}"
	    break
	else
	    continue
	fi
    done

    eval "$1='$PIN'"
}

function set_pin() {
    #===  FUNCTION  ================================================================
    #        NAME:  set_pin
    # DESCRIPTION: sets the PIN on the yubikey
    # PARAMETER 1: the new PIN the set
    # PARAMETER 2: the current PIN. Defaults to the yubikey default
    #===============================================================================

    local NEW_PIN="${1}"
    local OLD_PIN="${2:-$DEFAULT_PIN}"

    $PIV_TOOL piv change-pin --pin $OLD_PIN --new-pin $NEW_PIN >> "$LOGFILE" 2>&1
}


function get_random_puk() {
    #===  FUNCTION  ================================================================
    #        NAME: get_random_puk
    # DESCRIPTION: generates a random 8 character string to set as the PUK
    # PARAMETER 1: a string that is evaulated as variable passed by reference.
    #              passes the 8 character PUK that was generated
    #===============================================================================

    local RANDOM_HEX=""
    local PUK=""

    #-------------------------------------------------------------------------------
    # We use openssl to generate a random hex number, convert it to decimal and
    # makee sure it is at least 8 characters. If not, we repeat until we have at
    # least 8 characters
    #-------------------------------------------------------------------------------
    while [[ ${#PUK} -lt 8 ]]; do
	RANDOM_HEX=$(openssl rand -hex 4)
	PUK=$(printf "%d" $((16#$RANDOM_HEX)))
    done

    # Return just the first 8 characters
    eval "$1='${PUK:0:8}'"
}

function set_puk() {
    #===  FUNCTION  ================================================================
    #        NAME: set_puk
    # DESCRIPTION: sets the PUK to a random 8 digit number. This is random because
    #              the PUK is a security risk and it is better to just reset the
    #              yubikey rather than perform any action requiring the PUK
    # PARAMETER 1: the current PUK. Defaults to the yubikey default PUK
    #===============================================================================

    local OLD_PUK="${1:-$DEFAULT_PUK}"

    get_random_puk NEW_PUK

    debugit "Setting new PUK to ${NEW_PUK}"
    $PIV_TOOL piv change-puk --puk $OLD_PUK --new-puk $NEW_PUK >> "$LOGFILE" 2>&1
}


function reset_yubikey() {
    #===  FUNCTION  ================================================================
    #        NAME: reset_yubikey
    # DESCRIPTION: resets the CCID identity of the yubikey
    #===============================================================================

    output "Attempting to reset the Yubikey\n"
    $PIV_TOOL piv reset -f >> "$LOGFILE" 2>&1
}

function randomize_mgmt_key() {
    #===  FUNCTION  ================================================================
    #        NAME: randomize_mgmt_key
    # DESCRIPTION: sets the management key to a random 24 hex character string. This
    #              is random because the key is a security risk and it is better to
    #              reset the yubikey rather than perform any action requiring the
    #              management key
    #===============================================================================

    local NEW_MGMT_KEY=$(openssl rand -hex 24 | tr '[[:lower:]]' '[[:upper:]]')

    debugit "Setting management key to $NEW_MGMT_KEY"
    $PIV_TOOL piv change-management-key \
	      --management-key "$DEFAULT_MGMT_KEY"  \
	      --new-management-key "$NEW_MGMT_KEY" \
	      >> "$LOGFILE" 2>&1
}

function generate_key() {
    #===  FUNCTION  ================================================================
    #        NAME: generate_key
    # DESCRIPTION: generates a new crypto key.
    # PARAMETER 1: the name of the file to output the public key
    #===============================================================================

    local KEYFILE="${1}"

    output "Generating new key (this may take up to 15 seconds)....\n"
    $PIV_TOOL piv generate-key -a ${ALG:-RSA2048} "$PIV_SLOT" "${KEYFILE}" \
	      --management-key "${DEFAULT_MGMT_KEY}" >> "$LOGFILE" 2>&1
}

function selfsign() {
    #===  FUNCTION  ================================================================
    #        NAME: selfsign
    # DESCRIPTION: generates a self-signed certificate stored on the yubikey based
    #              on user input and the public key.  The certificate is valid
    #              for two years
    # PARAMETER 1: The file containing the public key
    #===============================================================================

    local PUB_KEY="${1}"

    local cn=''

    # Simple while loop that prompts the user for information and has the user
    # confirm the entered information. If not confirmed, starts the questionnaire
    # again.

    # When testing the y/n answer we want it to be case insensitive
    # this turns off case sensitivity
    shopt -s nocasematch

    # questionnaire loop
    while true; do
	# Ask the user for the common name
	output "Common Name: "
	read cn

	output "Supplied Common Name: $cn\n"
	output "Is this correct? [y/n] "
	read -n1 answer
	output "\n"
	[[ "${answer}" == "Y" ]] && break
    done

    # Turn case sensitivity back on
    shopt -u nocasematch

    #-------------------------------------------------------------------------------
    # Create the self-signed certificate. We need to know the management key and
    # assume it is the default management key at this point.
    #-------------------------------------------------------------------------------
    debugit "Creating self signed certificate"
    $PIV_TOOL piv generate-certificate "$PIV_SLOT" "$PUB_KEY" \
	      --pin "$USER_PIN" \
	      --subject "${cn}" \
      	      --valid-days "${EXPIRE_DAYS:-730}" \
	      --management-key "${DEFAULT_MGMT_KEY}" \
	      >> "$LOGFILE" 2>&1
}

function set_retries() {
    #===  FUNCTION  ================================================================
    #        NAME: set_retries
    # DESCRIPTION: Sets the max number of failed inputs for the PIN and PUK before
    #              they are locked out. We use the globally defined values. For these
    #              settings.
    #===============================================================================

    #-------------------------------------------------------------------------------
    # Set the max number of retries for the PIN and PUK. We need to know the
    # management key and assume it is the default management key at this point.
    #-------------------------------------------------------------------------------
    $PIV_TOOL piv set-pin-retries \
	      -f --pin "${DEFAULT_PIN}" \
	      --management-key "${DEFAULT_MGMT_KEY}" \
	      "$MAX_PIN_RETRIES" \
	      "$MAX_PUK_RETRIES" \
	      >> "$LOGFILE" 2>&1
}

function setup_yubikey() {
    #===  FUNCTION  ================================================================
    #        NAME: setup_yubikey
    # DESCRIPTION: perform all the steps needed to setup a fresh or reset yubikey
    #===============================================================================

    # set max number of retries to input PIN and PUK before they are locked out
    set_retries

    # gets a user supplied pin and sets USER_PIN variable
    get_pin USER_PIN

    # updates the PIN
    set_pin $USER_PIN

    # set the puk aka the "Admin PIN". The admin PIN can reset the normal PIN
    set_puk

    # Create our temp files
    PUBKEY=$(mktemp)

    # generate a key and selfsign it
    generate_key "$PUBKEY"
    selfsign "$PUBKEY"

    # This is a best practice to set the management key
    randomize_mgmt_key
}

function get_ssh_key() {
    #===  FUNCTION  ================================================================
    #        NAME: get_ssh_key
    # DESCRIPTION: uses ssh-keygen to get the ssh publickey
    # PARAMETER 1: a string that is evaulated as variable passed by reference.
    #              passes the ssh public key to the variable
    #===============================================================================

    local SSH_KEY="$(ssh-keygen -i -m pkcs8 -f <($PIV_TOOL piv export-certificate 9a - | openssl x509 -pubkey))"

    eval "$1='$SSH_KEY'"
}

function get_certificate() {
    #===  FUNCTION  ================================================================
    #        NAME: get_certificate
    # DESCRIPTION: retrieves the public certificate from the yubikey
    # PARAMETER 1: a string that is evaulated as variable passed by reference.
    #              passes the certificate and x509 to the variable
    #===============================================================================

    local CERT=$($PIV_TOOL piv export-certificate "$PIV_SLOT"  - | openssl x509 -text)

    eval "$1='$CERT'"
}

function get_yubikey_info() {
    #===  FUNCTION  ================================================================
    #        NAME: get_yubikey_info
    # DESCRIPTION: uses ykman to get details about the current state of the yubikey
    # PARAMETER 1: a string that is evaulated as variable passed by reference.
    #              passes the output of "ykman piv info" to the variable
    #===============================================================================

    local INFO=$($PIV_TOOL info; $PIV_TOOL piv info)

    eval "$1='$INFO'"
}

function yubikey_display() {
    #===  FUNCTION  ================================================================
    #        NAME: yubikey_display
    # DESCRIPTION: Displays all known information about a yubikey
    #===============================================================================

    get_certificate PUB_CERT
    output "$PUB_CERT\n\n"

    get_yubikey_info YUBIKEY_INFO
    output "$YUBIKEY_INFO\n\n"

    # get the CN from the info. We'll append this as the "Comment" for the ssh key
    CN=$($PIV_TOOL piv info | grep Subject | awk '{print $NF}' | awk -F= '{print $2}')

    get_ssh_key SSH_PUB_KEY
    output "${SSH_PUB_KEY} ${CN:-}\n\n"
}

function change_pin() {
    #===  FUNCTION  ================================================================
    #        NAME: change_ping
    # DESCRIPTION: prompts user to change his/her pin
    #===============================================================================

    $PIV_TOOL piv change-pin
}

function confirm_destructive() {
    #===  FUNCTION  ================================================================
    #        NAME: confirm_destructive
    # DESCRIPTION: confirms the user is ok to proceed with destructive actions
    #===============================================================================

    local CONFIRM="NO"
    output "If you proceed all data on your Yubikey will be destroyed.\n"
    output "Are you sure you want to continue? [YES/NO] "
    read CONFIRM

    if [[ "$CONFIRM" != "YES" ]]; then
	output "Exiting\n"
	exit
    fi
}

function usage() {
    #===  FUNCTION  ================================================================
    #        NAME: usage
    # DESCRIPTION: shows command usage and then exits
    #===============================================================================


cat <<EOF >&2
usage: $0 [OPTIONS] COMMAND [SUBCOMMANDS]

This script will help setup a yubikey as well as extract information from it.

OPTIONS:
    -d             Enables debug mode
    -l             Specifies a log file. Note: This logfile will contain
                   sensitive information and needs to handled with care.
COMMANDS:
    reset          Resets the yubikey. THIS DESTROYS ALL PIV DATA
    setup          Resets the yubikey and configures a new PIV certificate
    change-pin     changes pin
    show           Displays information about the yubikey

EOF
    exit
}

function usage_show() {

cat <<EOF >&2
usage: $0 [OPTIONS] show [SUBCOMMANDS]

SUBCOMMANDS:
    cert           outputs the x509 certificate information
    ssh            outputs the ssh key
    info           outputs general information about the yubikey
    all            outputs all of the above

EOF
    exit
}

function main() {
    #===  FUNCTION  ================================================================
    #        NAME: main
    # DESCRIPTION: primary entry point for script. Parses args and determines what
    #              functions to call
    #===============================================================================

    while getopts ":dl:" opt; do
	case "$opt" in
	    d)
		DEBUG="true"
		;;
	    l)
		LOGFILE="${OPTARG}"
		;;
	   \?)
		usage
		;;
	    :)
		usage
		;;
	esac
    done

    shift $((OPTIND - 1))
    subcommand="${1:-}"
    case "$subcommand" in
	setup)
	    shift
	    SETUP=1
	    ;;
	change-pin)
	    shift
	    CHANGE_PIN=1
	    ;;
	reset)
	    shift
	    RESET=1
	    ;;
	show)
	    shift
	    show_opt="${1:-}"
	    case "$show_opt" in
		cert*)
		    shift
		    SHOW_CERT=1
		    ;;
		ssh*)
		    shift
		    SHOW_SSH=1
		    ;;
		info)
		    shift
		    SHOW_INFO=1
		    ;;
		all)
		    shift
		    SHOW_ALL=1
		    ;;
		*)
		    usage_show
		    ;;
	    esac
	    ;;
	*)
	    usage
	    ;;
    esac

    > "$LOGFILE"   # empties specified logfile

    if [[ "${RESET:-}" == "1" ]]; then
	confirm_destructive
	reset_yubikey
	get_yubikey_info YUBIKEY_INFO
	output "$YUBIKEY_INFO\n\n"
	return
    fi

    if [[ "${SETUP:-}" == "1" ]]; then
	confirm_destructive
	reset_yubikey
	setup_yubikey
	yubikey_display
	return
    fi

    if [[ "${CHANGE_PIN:-}" == "1" ]]; then
	change_pin
	return
    fi

    if [[ "${SHOW_CERT:-}" == "1" ]]; then
	get_certificate PUB_CERT
	output "$PUB_CERT\n\n"
	return
    fi

    if [[ "${SHOW_SSH:-}" == "1" ]]; then
	# get the CN from the info. We'll append this as the "Comment" for the ssh key
	CN=$($PIV_TOOL piv info | grep Subject | awk '{print $NF}' | awk -F= '{print $2}')

	get_ssh_key SSH_PUB_KEY
	output "${SSH_PUB_KEY} ${CN:-}\n\n"
	return
    fi

    if [[ "${SHOW_INFO:-}" == "1" ]]; then
	get_yubikey_info YUBIKEY_INFO
	output "$YUBIKEY_INFO\n\n"
	return
    fi

    if [[ "${SHOW_ALL:-}" == "1" ]]; then
	yubikey_display
	return
    fi

}

main "$@"
