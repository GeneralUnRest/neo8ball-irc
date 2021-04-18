#!/usr/bin/env bash
# Copyright 2018 Anthony DeDominic <adedomin@gmail.com>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

WEATHER="api.openweathermap.org/data/2.5/weather?APPID=${OWM_KEY}&q="


for arg; do
    case "$arg" in
        --nick=*)    nick="${arg#*=}" ;;
        --message=*) q="${arg#*=}" ;;
        --command=*) command="${arg#*=}" ;;
    esac
done

# parse args
while [[ -n "$q" ]]; do
    key="${q%% *}"

    case "$key" in
        -S|--save)
            SAVE=1
        ;;
        -h|--help)
            echo ":r usage: $command [--save] [query]"
            echo ":r This service uses https://openweathermap.org"
            exit 0
        ;;
        '') ;;
        *)
            break
        ;;
    esac

    if [[ "${q#"$key" }" == "$q" ]]; then
        q=
    else
        q="${q#"$key" }"
    fi
done

if [[ -z "$q" ]]; then
    if ! q="$(GET_LOC "$nick")"; then
        echo ":mn $nick you must set a default location first"
        echo ":mn $nick use --save location"
        exit 0
    fi
fi

WEATHER+="$(URI_ENCODE "$q")"
RES=$(curl "${WEATHER}" 2>/dev/null)

if [[ -z "$RES" ]]; then
    echo ":r no weather information"
    exit 0
fi

if [[ "$(jq -r '.cod' <<< "$RES")" != '200' ]]; then
    echo ":r $(jq -r '.message' <<< "$RES")"
    exit 0
fi

KELV="$(jq -r '.main.temp' <<< "$RES")"
CURR_FAHR="$(printf "%.2f" "$(bc <<< "scale=2;$KELV * 9 / 5 - 459.67")")"
CURR_CELS="$(printf "%.2f" "$(bc <<< "scale=2;$KELV - 273.15")")"
COND=$(jq -r '.weather[0].description' <<< "$RES")
HUMIDITY=$(jq -r '.main.humidity' <<< "$RES")
loc=$(jq -r '. | .name + ", " + .sys.country' <<< "$RES")
city_id=$(jq -r '.id' <<< "$RES")

# add color to temps!!!
if [[ "$(bc -l <<< "$CURR_FAHR >= 80.00")" -eq 1 ]]; then
    CURR_FAHR=$'\003'"04$CURR_FAHR"$'\003'
    CURR_CELS=$'\003'"04$CURR_CELS"$'\003'
elif [[ "$(bc -l <<< "$CURR_FAHR < 50.00")" -eq 1 ]]; then
    CURR_FAHR=$'\003'"02$CURR_FAHR"$'\003'
    CURR_CELS=$'\003'"02$CURR_CELS"$'\003'
else
    CURR_FAHR=$'\003'"03$CURR_FAHR"$'\003'
    CURR_CELS=$'\003'"03$CURR_CELS"$'\003'
fi

echo -e ":r "$'\002'"${loc}\\002 ::" \
    "\\002Conditions\\002 $COND ::" \
    "\\002Temp\\002 $CURR_CELS °C | $CURR_FAHR °F ::" \
    "\\002Humidity\\002 $HUMIDITY% ::" \
    "\\002More\\002 http://openweathermap.org/city/$city_id"

# valid station... so save it
if [[ -n "$SAVE" ]]; then
    if ! SAVE_LOC "$nick" "$q"; then
        echo ":mn $nick there was a problem saving your defaults"
        echo ":logw $command -> failed to save $q for $nick"
    fi
fi
