#!/usr/bin/env bash
# Copyright 2018 kjensenxz <kenneth@jensen.cf>, Anthony DeDominic <adedomin@gmail.com>
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

for arg; do
    case "$arg" in
        --message=*) q="${arg#*=}" ;;
        --command=*) command="${arg#*=}" ;;
    esac
done

declare -i COUNT
COUNT=1
while [[ -n "$q" ]]; do
    arg="${q%% *}"

    case "$arg" in
        -c|--count)
            LAST='c'
        ;;
        --count=*)
            [[ "${arg#*=}" =~ ^[1-3]$ ]] &&
                COUNT="${arg#*=}"
        ;;
        -h|--help)
            echo ":r usage: $command [[--count=#-to-ret] [query]]"
            echo ":r search for RFCs by title or number or get a random RFC."
        ;;
        '') ;;
        *)
            [ -z "$LAST" ] && break
            LAST=
            [[ "$arg" =~ ^[1-3]$ ]] &&
                COUNT="$arg"
        ;;
    esac

    if [[ "${q#"$arg" }" == "$q" ]]; then
        q=
    else
        q="${q#"$arg" }"
    fi
done

if [[ -z "$q" ]]; then
    EXAMPLE_RFCs=(
        439 527 748 968 1097 1149 1215 1216 1313
        1437 1438 1605 1606 1607 1776 1882 1924
        1925 1926 1927 2100 2321 2322 2323 2324
        2325 2410 2549 2550 2551 2795 3091 3092
        3093 3251 3252 3514 3751 4041 4824 5241
        5242 5513 5514 5841 5984 6214 6217 6592
        6919 6921 7168 7169 7511 7514 8135 8136
        8140
    )

    q="${EXAMPLE_RFCs[ $RANDOM % ${#EXAMPLE_RFCs[@]} ]}"
fi

p=rfc
case "$q" in *[!0-9]*) p="title" ;; esac

IETF="https://tools.ietf.org/html"
RFC_SEARCH="https://www.rfc-editor.org/search/rfc_search_detail.php?"

while read -r rfc; do
    if ! title="$(
        curl --silent \
             --fail \
            "$IETF$rfc" \
        | gawk -v IGNORECASE=1 \
               -v RS='</title' -- '
            RT {
                gsub(/.*<title[^>]*>/,"")
                print $0
                exit 0
            }' \
        | HTML_CHAR_ENT_TO_UTF8 \
        | tr '\r\n' ' '
    )"; then
        continue
    fi
    echo ":r "$'\002'"$title"$'\002'" :: $IETF$rfc"
done < <(
       curl --silent --fail \
           "${RFC_SEARCH}$p=$(URI_ENCODE "$q")" \
       | grep -o "<table class='gridtable'>.*</table>"      \
       | xmllint --recover --html --nocompact - 2>/dev/null \
       | grep -oE '/rfc[0-9]+.txt' | sed 's/.txt$//g'       \
       | sort | uniq | head -n "$COUNT"
)




