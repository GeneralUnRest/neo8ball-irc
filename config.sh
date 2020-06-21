# shellcheck disable=2034
# nickname, also username
NICK="neo8ball"
# NickServ password
# blank for unreg
NICKSERV=
# irc server
SERVER="irc.rizon.net"
# channels to join
CHANNELS=("#prussian")
# TODO: not implemented
# CHANNEL_BLACKLIST=("#badchan")
# set to non-empty to disable automatic invite handling
DISABLE_INVITES=
# supplimentary channels to join from file
INVITE_FILE="/tmp/invite-channel-list"
# delay joining on invite to prevent potential flood kicks (rizon)
# number is in seconds, can be fractional.
INVITE_DELAY=3

# port number
PORT="6697"
# use tls
# set to blank to disable
TLS=yes
# verify trust using system trust store
VERIFY_TLS=yes
# verify trust using given cert(s)
# VERIFY_TLS_FILE=/path/to/cert/bundle

# IPC related files will use this root
temp_dir=/tmp

# LOGGING
# log levels
# 1 - DEBUG
# 2 - INFO
# 3 - WARN
# 4 - ERR/CRIT
LOG_LEVEL=1
# leave blank to not write messages to stdout
LOG_STDOUT=y

## DECLARE IRC events here ##

LIB_PATH="${BASH_SOURCE[0]%/*}/lib/"
# let other programs know where plugins are.
export LIB_PATH

# allows you to set a global useragent for curl using a .curlrc
# as the same dir the config is in
export CURL_HOME="${BASH_SOURCE[0]%/*}"

# on highlight, call the following script/s
HIGHLIGHT="8ball.sh"
# default command to execute if no valid command matches
# in a private message context
PRIVMSG_DEFAULT_CMD='help'

# prefix that commands should start with
CMD_PREFIX=".,!"
declare -gA COMMANDS
# command names should be what to test for
# avoid adding prefixes like .help
# use as follows:
#  ['one-word-command-string']='the command to execute'
COMMANDS=(
["8"]="8ball.sh" 
["8ball"]="8ball.sh" 
["define"]="define.sh"
["decide"]="8ball.sh" 
["duck"]="search.sh" 
["ddg"]="search.sh" 
["g"]="search.sh"
["help"]="help.sh"
["bots"]="bots.sh"
["source"]="bots.sh"
#["w"]="weather.sh"
["owm"]="weather.sh"
["weather"]="weather.sh"
["nws"]="nws.sh"
["npm"]="npm.sh"
["mdn"]="mdn.sh"
["wiki"]="wikipedia.sh"
["yt"]="youtube.sh"
["you"]="youtube.sh"
["youtube"]="youtube.sh"
["u"]="urbandict.sh"
["urb"]="urbandict.sh"
["urban"]="urbandict.sh"
["bible"]="bible.sh"
["quran"]="bible.sh"
["fap"]="fap.sh"
["gay"]="fap.sh"
["straight"]="fap.sh"
["moose"]="moose.sh"
["vote"]="vote.sh"
["yes"]="vote.sh"
["no"]="vote.sh"
["standings"]="vote.sh"
["mlb"]="mlb.sh"
["twit"]="twitter.sh"
["twitter"]="twitter.sh"
["r"]="rfc.sh"
["rfc"]="rfc.sh"
)

declare -gA REGEX
# regex patterns
# if you need more fine grained control
# uses bash regexp language
# use as follows:
#  ['YOUR REGEXP HERE']='the command to execute'
REGEX=(
['https?://twitter.com/[^/]+/status/[0-9]+|t.co/[a-zA-Z0-9]+']='twitter.sh'
['youtube.com|youtu.be']='youtube.sh'
# literally anything can be a url nowadays
['(https?)://[^ ]+']='pagetitle.sh'
['^moose']='moose.sh'
)

# list of nicks to ignore from, such as other bots
IGNORE=(
)

# list of nicks considered to be trusted gateways
# gateways are shared nicknames that prepend user info
# to the front of the message in the format like <gateway> <user> msg
# for an example of a gateway, see teleirc on npm which is a 
# telegram <-> IRC gateway bot
GATEWAY=(
)

# anti spam feature
# prevent users from abusing your bot
# set to blank to disable
ANTISPAM=yes
# a new command allowance is given every x amount of seconds
# time in seconds to grant an allowance
ANTISPAM_TIMEOUT=10
# max number of commands a user gets in a time period
ANTISPAM_COUNT=3

# time in seconds check for closed connection
TIMEOUT_CHECK=300 # 5m

## variables for plugins ##

# comment out if you don't want
# to use OpenWeatherMap plugin
export OWM_KEY="your owm key"

# your persistant storage here,
# comment out to disabable weatherdb.sh
export PERSIST_LOC="/tmp"

# for youtube.sh
#export YOUTUBE_KEY="your youtube api key"

# you have to generate bible_db yourself, see create-db.sh in ./static
#export BIBLE_DB="$(dirname "$0")/static/kjbible-quran.db"
export BIBLE_SOURCE="$(dirname "$0")/static/king-james.txt"
export QURAN_SOURCE="$(dirname "$0")/static/quran-allah-ver.txt"

# newline separated channels to disable pagetitle plugin in
# RESTRICTIONS:
# be careful to remove trailing/leading spaces from channels
# has to be a string due to bash EXPORT restrictions
export PAGETITLE_IGNORE='
#nopagetitle
'

# newline separated channels to disable the
# youtube regexp match mode
# same issues as with PAGETITLE_IGNORE
export YOUTUBE_IGNORE='
#noyoutuberegexp
'

# list of channels to not print moose in
# some channels may insta ban if multiple lines are written rapidly
# same issues as with PAGETITLE_IGNORE
export MOOSE_IGNORE="
#nomoose
"
# sleep timeout to prevent moose spam
export MOOSE_SLEEP_TIMER='10s'
# delay in seconds (supports decimal assuming gnu sleep)
export MOOSE_OUTPUT_DELAY='0.3s'

# MS Cognitive Services Computer Vision API (describe)
# for enhanced insight on images in lib/pagetitle.sh
export MS_COG_SERV='https://westcentralus.api.cognitive.microsoft.com/vision/v1.0/describe'
# keep this commented out if you want to disable this feature
#export MS_COG_KEY='api key here'

# Uncomment to disable pagetitle.sh "File" reports.
#export PAGETITLE_DISABLE_FILE=1

# rate to poll following MLB games
# in seconds or whatever timespec that the sleep command takes
export MLB_POLL_RATE=90

# the following are twitter consumer key and secret for the twitter plugin
#export TWITTER_KEY=your-key-here
#export TWITTER_SECRET=your-key-here

# moved common functions in the lib path.
# you can store them here or add your own below as before
. "$LIB_PATH/common-functions.sh"

# DO NOT ENABLE THIS UNLESS YOU'RE TESTING
#MOCK_CONN_TEST=yes
