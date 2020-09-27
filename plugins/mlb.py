#!/usr/bin/env python3
# Copyright (C) 2020  Anthony DeDominic <adedomin@gmail.com>

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

from urllib.request import Request, urlopen
from html.parser import HTMLParser as HtmlParser
from json import load as json_parse

from time import strftime
from sys import stderr, argv

MLB_DEPRECATED_API = 'http://gd2.mlb.com/components/game/mlb'
API_DATEFMT = "year_%Y/month_%m/day_%d"
OUTGAME_STRING = '{} {} ({}{}) {} {}'


class LatestEventParser(HtmlParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.__largest_event = -1
        self.latest_event = ''

    def handle_starttag(self, tag, attr):
        if tag == 'event':
            num = '-999'
            ev = ''

            for attr_name, value in attr:
                if attr_name == 'number':
                    num = int(value)
                if attr_name == 'description':
                    ev = value

            if num >= self.__largest_event and ev != '':
                self.__largest_event = num
                self.latest_event = ev


def get_url(url, accept='application/json'):
    return urlopen(Request(url,
                           headers={'User-Agent':
                                    'neo8ball - '
                                    'https://github.com/'
                                    'adedomin/neo8ball-irc',
                                    'Accept': accept}))


def get_html(url):
    with get_url(url, 'text/html,application/xhtml+xml') as req:
        return req.read().decode('utf8', 'ignore')


def get_json(url):
    with get_url(url, 'application/json') as req:
        return json_parse(req)


def get_more_detail(api_path, gid):
    api_gid = 'gid_{}'.format(gid.replace('/', '_').replace('-', '_'))
    detail_linescore = '{}/{}/linescore.json'.format(api_path, api_gid)
    detail_eventlog = '{}/{}/eventLog.xml'.format(api_path, api_gid)

    linescore = get_json(detail_linescore)

    if not isinstance(linescore, dict):
        raise Exception('linescore is not an object')

    try:
        linescore = linescore['data']['game']
    except KeyError:
        raise Exception('linescore structure is unexpected')

    # count
    balls = linescore.get('balls', 'unkn')
    strikes = linescore.get('strikes', 'unkn')
    outs = linescore.get('outs', 'unkn')

    runners_onbase = linescore.get('runner_on_base_status', 'unkn')

    pitcher = linescore.get('current_pitcher', dict()).get('last_name', 'unkn')
    batter = linescore.get('current_batter', dict()).get('last_name', 'unkn')

    # bonus
    latest_event = ''

    try:
        events_xml = get_html(detail_eventlog)
        events = LatestEventParser()
        events.feed(events_xml)
        if events.latest_event != '':
            latest_event = events.latest_event
    except Exception as e:
        latest_event = e

    return {'balls':   balls,
            'strikes': strikes,
            'outs':    outs,
            'onbase':  runners_onbase,
            'pitcher': pitcher,
            'batter':  batter,
            'latest':  latest_event}


def mlb(inp):
    api_base = '{}/{}'.format(MLB_DEPRECATED_API,
                              strftime(API_DATEFMT))
    api_string = '{}/grid.json'.format(api_base)

    try:
        games_today = get_json(api_string)
    except Exception as e:
        print(e, file=stderr)
        return 'Failed to get games today (Note: gd2 API *is* deprecated).'

    if not isinstance(games_today, dict):
        return 'Failed to get games today: grid.json is not an object.'

    try:
        games = games_today['data']['games']['game']
    except KeyError:
        return 'No Games Today.'

    if not isinstance(games, list):
        games = [games]

    output = []
    for game in games:
        away_team = game.get('away_name_abbrev', '')
        away_score = game.get('away_score', '0')
        if away_score == '':
            away_score = 0

        home_team = game.get('home_name_abbrev', '')
        home_score = game.get('home_score', '0')
        if home_score == '':
            home_score = 0

        inning = game.get('top_inning', '-')
        if inning == 'Y':
            inning = '^'
        elif inning == 'N':
            inning = 'v'
        else:
            inning = '-'

        game_status = game.get('status', '')
        if 'Pre' == game_status[0:3]:
            game_status = game.get('event_time', 'P')
            inning = ''
        elif 'Final' == game_status:
            game_status = 'F'
            inning = ''
        else:
            game_status = game.get('inning', '0')

        outstring = OUTGAME_STRING.format(away_team, away_score,
                                          game_status, inning,
                                          home_team, home_score)

        if inp.lower() == away_team.lower() or \
           inp.lower() == home_team.lower():
            if inning != '':
                try:
                    details = get_more_detail(api_base, game.get('id', 'null'))
                except Exception as e:
                    print('WARNING: eventLog API may be broken: {}'.format(e),
                          file=stderr)
                    return outstring

                outstring += ' Count: {}-{}'.format(details['balls'],
                                                    details['strikes'])
                outstring += ' Outs: {}'.format(details['outs'])
                outstring += ' OnBase: {}'.format(details['onbase'])
                outstring += ' Pitcher: {}'.format(details['pitcher'])
                outstring += ' Batter: {}'.format(details['batter'])

                if isinstance(details['latest'], Exception):
                    print('WARNING: API For latest events is broken: {}'
                          .format(details['latest'], file=stderr))
                elif details['latest'] != "":
                    return '{}\nLatest: {}'.format(outstring,
                                                   details['latest'])
            return outstring
        else:
            output.append(outstring)

    if len(output) == 0:
        return 'No Games Today.'
    else:
        return 'Times in EST - ' + ' :: '.join(output)


if __name__ == '__main__':
    if len(argv) < 2:
        print('{}'.format(mlb('')))
    elif len(argv) < 5:
        print('{}'.format(mlb(argv[1])))
    else:
        for line in mlb(argv[4]).split('\n'):
            print(':m {} {}'.format(argv[1], line))