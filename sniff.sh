LOCKID=$((1 + RANDOM % 100000))
INFILE=$1
OUTFILE=$2

function extractField() {
  # $1 should be input to extract from.
  # $2 should be the name of the value we're looking for
  FIELD="$(echo "$1" | grep -o '<input type="hidden" name="'"$2"'" value="[^"]*"/>' | head -n 1)"
  VALUE="$(echo "$FIELD" | grep -o 'value="[^"]*"' | grep -o '".*' | grep -o '[^"]*')"
  echo "$VALUE"
}

function saveLoginCookie() {
  # Get magic secret values
  LOGINPAGE=$(curl -s --cookie /tmp/$LOCKID.cookies.txt --cookie-jar /tmp/$LOCKID.cookies.txt https://cas.byu.edu/cas/login?service=https%3A%2F%2Fnit.byu.edu%2Fry%2Fwebapp%2Fnit%2Fvalidate%3Ftarget%3Dhttps%253A%252F%252Fnit.byu.edu%252Fry%252Fwebapp%252Fnit%252Fapp%253Fservice%253Dpage%252FJackLookup)
  HIDDEN_EXECUTION=$(extractField "$LOGINPAGE" "execution")
  HIDDEN_LT=$(extractField "$LOGINPAGE" "lt")
  HIDDEN_EVENTID=$(extractField "$LOGINPAGE" "_eventId")

  # Prompt for username and password
  read -p "  NetID to obtain login cookie: " NETID
  read -p "  Password for $NETID: " -s PASSWORD


  # Send request
  INDEXPAGE="$(curl --request POST "https://cas.byu.edu/cas/login?service=https%3A%2F%2Fnit.byu.edu%2Fry%2Fwebapp%2Fnit%2Fvalidate%3Ftarget%3Dhttps%253A%252F%252Fnit.byu.edu%252Fry%252Fwebapp%252Fnit%252Fapp%253Fservice%253Dpage%252FJackLookup" \
    --data-urlencode "username=$NETID" \
    --data-urlencode "password=$PASSWORD" \
    --data-urlencode "execution=$HIDDEN_EXECUTION" \
    --data-urlencode "lt=$HIDDEN_LT" \
    --data-urlencode "_eventId=$HIDDEN_EVENTID" \
    --cookie /tmp/$LOCKID.cookies.txt \
    --cookie-jar /tmp/$LOCKID.cookies.txt -s -L)"

  BROWNIE="$(extractField "$INDEXPAGE" "byu_brownie")"
  echo "$BROWNIE"
}

function displayStatus() {
  CONNECTED=$(cat $1 | grep -o '^[^,]*,[^,]*,connected' | uniq | wc -l)
  UNCONNECTED=$(cat $1 | grep ",unconnected" | wc -l)
  NONEXISTANT=$(cat $1 | grep ',nonexistant' | wc -l)
  ERROR=$(cat $1 | grep ',unknown' | wc -l)
  LINES=$(cat $1 | wc -l)
  TOTAL=$(( $CONNECTED+$UNCONNECTED+$NONEXISTANT+$ERROR ))

  tput cuu1
  tput cuu1
  tput cuu1
  tput cuu1
  tput cuu1
  tput cuu1

  echo "$CONNECTED connected (active) ports"
  echo "$UNCONNECTED disconnected (inactive) ports"
  echo "$NONEXISTANT ports that don't exist"
  echo "$ERROR errors encountered"
  echo "----"
  echo "$TOTAL scanned"
}



function createInfoTable() {
  RESULT="$1"
  LINES=$(echo "$RESULT" | tr -d '\n\r' | sed 's/tr/\n/g' | grep -E '<td align="right"( valign="top")?>');

  function getResultField() {
    SECTION=$(echo "$LINES" | grep -E '<td align="right"( valign="top")?>( <font color="green">)?(No )?'"$1"'(</font> )?(:)?</td>')
    RESULT=$(echo "$SECTION" | grep -oE '<td>(<a [^>]*>)?[^<]*' | grep -o '[^>]*$')

    #Remove whitespace
    RESULT="${RESULT#"${RESULT%%[![:space:]]*}"}"
    RESULT="${RESULT%"${RESULT##*[![:space:]]}"}"

    if [[ $RESULT == "" ]]; then
      echo "no$1"
    else
      echo "$RESULT"
    fi
  }

  STATUS="unknown"

  if [[ $RESULT == *"Error getting jack information"* ]]; then
    STATUS="unknown"
  elif [[ $RESULT == *"NetDoc reports that this jack exists, but is not connected to any switch"* ]]; then
    STATUS="unconnected"
  elif [[ $RESULT == *'<font color="green">Link</font>'* ]]; then
    STATUS="connected"
  elif [[ $RESULT == *'No jack was found'* ]]; then
    STATUS="nonexistant"
  else
    STATUS="unknown"
  fi

  DEVICES=$(echo "$LINES" | grep 'IP:' -A 2 | tr -d ' ' | while read IP; do read HOSTNAME; read MAC; echo \"$IP $HOSTNAME $MAC\" ; done )

  if [[ -z "$DEVICES" ]]; then
    echo "$BUILDING,$PORT,$STATUS,$(getResultField 'Room'),$(getResultField 'Link'),noDevice,noIp,$(getResultField 'Pair'),$(getResultField 'Department'),$(getResultField 'Power'),$(getResultField 'Config')"
  else
    echo "$DEVICES" | while read device; do
      IP=$(echo "$device" | grep -o 'IP:</td><td><ahref="[^"]*">[^<]*' | grep -o '[^>]*$')
      HOST=$(echo "$device" | grep -o 'Hostname:</td><td>[^<]*' | grep -o '[^>]*$')
      if [ -z "$IP" ]; then IP="noIp"; fi;
      if [ -z "$HOST" ]; then HOST="noDevice"; fi;
      echo "$BUILDING,$PORT,$STATUS,$(getResultField 'Room'),$(getResultField 'Link'),$HOST,$IP,$(getResultField 'Pair'),$(getResultField 'Department'),$(getResultField 'Power'),$(getResultField 'Config')"
    done
  fi
}


function checkPort() {
  # $1 Should be the building
  # $2 Should be the port
  # $3 Should be one time key ("brownie" as it's called on their page)
  BUILDING=$1
  PORT=$2
  KEY=$3
  RESULT=$(curl --request POST 'https://nit.byu.edu/ry/webapp/nit/app' \
    --cookie /tmp/$LOCKID.cookies.txt \
    -H 'Pragma: no-cache' \
    -H 'Origin: https://nit.byu.edu' \
    -H 'User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/56.0.2924.87 Safari/537.36' \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    -H 'Referer:https://nit.byu.edu/ry/webapp/nit/app?service=page/JackLookup' \
    --data 'service=direct%2F0%2FJackLookup%2FpageContent.%24BForm.form&sp=S1&Form1=byu_brownie%2C%24TextField%2C%24TextField%240%2C%24Submit&byu_brownie='"$KEY"'&%24TextField='"$BUILDING"'&%24TextField%240='"$PORT"'&%24Submit=Lookup+Jack' \
    -s)

  createInfoTable "$RESULT"
}

# Begin execution
KEY="$(saveLoginCookie)"

# Make sure child processes stop when we do
trap "trap - SIGTERM && kill -- -$$" SIGINT SIGTERM EXIT

# Run a bunch of ports in parallel
export -f checkPort
export -f createInfoTable
export LOCKID
(cat $INFILE | parallel --colsep " " "checkPort {1} {2} $KEY" > /tmp/parallel.$LOCKID.txt; rm /tmp/$LOCKID.cookies.txt ) &

echo; echo "Scanning:"
echo; echo; echo; echo; echo; echo;

# Display status while we wait
while [ -e /tmp/$LOCKID.cookies.txt ]; do
  displayStatus /tmp/parallel.$LOCKID.txt
  sleep .5
done

# Output it one last time once we've finished
wait
displayStatus /tmp/parallel.$LOCKID.txt

# Write final (sorted) file
echo;echo "Writing log to file $OUTFILE"
echo "BUILDING,JACKNUMBER,STATUS,ROOM,LINK,DEVICENAME,IPADDRESS,PAIR,DEPARTMENT,POWER,CONFIG" > $OUTFILE
cat /tmp/parallel.$LOCKID.txt | sort >> $OUTFILE
rm /tmp/parallel.$LOCKID.txt
