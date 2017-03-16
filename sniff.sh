MAXPORT=$1
LOCKID=$((1 + RANDOM % 100000))
OUTFILE=$2

function extractField(){
  # $1 should be input to extract from.
  # $2 should be the name of the value we're looking for
  FIELD="$(echo "$1" | grep -o '<input type="hidden" name="'"$2"'" value="[^"]*"/>' | head -n 1)"
  VALUE="$(echo "$FIELD" | grep -o 'value="[^"]*"' | grep -o '".*' | grep -o '[^"]*')"
  echo "$VALUE"
}

# Apparently this shouldn't have any dots in it
function extractKey(){
  KEY="$(echo $1 | cut -c 1-350)"
  echo "$KEY"
}

function saveLoginCookie(){
  # Get magic secret values
  LOGINPAGE=$(curl -s --cookie /tmp/$LOCKID.cookies.txt --cookie-jar /tmp/$LOCKID.cookies.txt https://cas.byu.edu/cas/login?service=https%3A%2F%2Fnit.byu.edu%2Fry%2Fwebapp%2Fnit%2Fvalidate%3Ftarget%3Dhttps%253A%252F%252Fnit.byu.edu%252Fry%252Fwebapp%252Fnit%252Fapp%253Fservice%253Dpage%252FJackLookup)
  HIDDEN_EXECUTION=$(extractField "$LOGINPAGE" "execution")
  HIDDEN_LT=$(extractField "$LOGINPAGE" "lt")
  HIDDEN_EVENTID=$(extractField "$LOGINPAGE" "_eventId")

  # Prompt for username and password
  read -p "  NetID to obtain login cookie: " NETID
  read -p "  Password for $NETID: " -s PASSWORD
  (>&2 echo "")


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

function displayStatus(){
  CONNECTED=$(cat $1 | grep " connected" | wc -l)
  UNCONNECTED=$(cat $1 | grep unconnected | wc -l)
  NONEXISTANT=$(cat $1 | grep exist | wc -l)
  ERROR=$(cat $1 | grep error | wc -l)
  LINES=$(cat $1 | wc -l)
  TOTAL=$(( $CONNECTED+$UNCONNECTED+$NONEXISTANT+$ERROR ))

  clear
  echo "$CONNECTED connected (active) ports"
  echo "$UNCONNECTED disconnected (inactive) ports"
  echo "$NONEXISTANT ports that don't exist"
  echo "$ERROR errors encountered"
  echo "----"
  echo "$TOTAL scanned"
}


function checkPort() {
  # $1 Should be the port
  # $2 Should be one time key ("brownie" as it's called on their page)
  BUILDING='ESC'
  PORT=$1
  KEY=$2
  RESULT=$(curl --request POST 'https://nit.byu.edu/ry/webapp/nit/app' \
    --cookie /tmp/$LOCKID.cookies.txt \
    -H 'Pragma: no-cache' \
    -H 'Origin: https://nit.byu.edu' \
    -H 'User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/56.0.2924.87 Safari/537.36' \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    -H 'Referer:https://nit.byu.edu/ry/webapp/nit/app?service=page/JackLookup' \
    --data 'service=direct%2F0%2FJackLookup%2FpageContent.%24BForm.form&sp=S1&Form1=byu_brownie%2C%24TextField%2C%24TextField%240%2C%24Submit&byu_brownie='"$KEY"'&%24TextField=ESC&%24TextField%240='"$PORT"'&%24Submit=Lookup+Jack' \
    -s)

  if [[ $RESULT == *"NetDoc reports that this jack exists, but is not connected to any switch"* ]]; then
  	echo "Port $PORT unconnected"
  elif [[ $RESULT == *'<table align="center">'* ]]; then
  	echo "Port $PORT connected"
  elif [[ $RESULT == *'No jack was found'* ]]; then
  	echo "Port $PORT doesn't seem to exist"
  else
    echo "Port $PORT gave some kind of error"
  fi
}

# Begin execution
ONETIME_KEY="$(saveLoginCookie)"
KEY="$(extractKey $ONETIME_KEY)"

# Make sure child processes stop when we do
trap "trap - SIGTERM && kill -- -$$" SIGINT SIGTERM EXIT

# Create lock file
echo "lock" > /tmp/parallel.$LOCKID.lock.txt

# Run a bunch of ports in parallel
export -f checkPort
export LOCKID
(seq -f "%04g" 0 $MAXPORT | parallel checkPort {} $KEY > /tmp/parallel.$LOCKID.txt; rm /tmp/parallel.$LOCKID.lock.txt ) &

# Display status while we wait
while [ -e /tmp/parallel.$LOCKID.lock.txt ]; do
  displayStatus /tmp/parallel.$LOCKID.txt
  sleep .5
done

# Output it one last time once we've finished
wait
displayStatus /tmp/parallel.$LOCKID.txt

# Write final (sorted) file
echo "Writing log to file $2"
cat /tmp/parallel.$LOCKID.txt | sort > $2

# Clean up
rm /tmp/parallel.$LOCKID.txt
rm /tmp/$LOCKID.cookies.txt
