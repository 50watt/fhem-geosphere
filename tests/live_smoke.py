#!/usr/bin/env python3
"""Exercise the complete Perl provider using a synchronous test-only HTTP bridge."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import urllib.error
import urllib.request

PERL = r'''
use strict; use warnings; use JSON::PP qw(encode_json decode_json); use Encode qw(decode_utf8 encode_utf8);
use FHEM::APIs::Weather::GeoSphereAPI;
our (%defs,%attr,%modules,@queue); $|=1;
sub AttrVal {return $attr{$_[0]}{$_[1]} // $_[2];}
$attr{test}{forecast}='hourly,daily';
sub ReadingsVal {return $_[2];}
sub setDevAttrList {$defs{$_[0]}{".AttrList"}=$_[1];}
$modules{Weather}{AttrList}="forecast alerts disable";
sub HttpUtils_NonblockingGet {push @queue,$_[0];}
sub FHEM::Core::Weather::RetrieveCallbackFn {}
$attr{global}={latitude=>$ARGV[0],longitude=>$ARGV[1]};
$attr{test}{alerts}=1;
$attr{test}{geoSphereNowcast}=$ARGV[4];
$attr{test}{geoSphereAltitude}=$ARGV[3] if length($ARGV[3] // "");
$defs{test}={NAME=>'test',TYPE=>'Weather',DEF=>'API=GeoSphereAPI'};
my $api=FHEM::APIs::Weather::GeoSphereAPI->new({devName=>'test',location=>"$ARGV[0],$ARGV[1]",apioptions=>"station:$ARGV[2]",language=>'de'});
$defs{test}{fhem}{api}=$api;
$api->setRetrieveData;
while (@queue) {
 my $p=shift @queue;print encode_json({request=>$p->{url}})."\n";
 my $line=<STDIN>;die 'transport ended' unless defined $line;
 my $response=decode_json($line);$p->{code}=$response->{code};
 my $body=$response->{body}//''; $body=encode_utf8($body) if utf8::is_utf8($body);
 $p->{callback}->($p,$response->{error}//'',$body);
}
my $w=$api->getWeather;
my $dropdown=$defs{test}{'.AttrList'}//'';
my $name=$w->{stationName}//'';
$name=decode_utf8($name) unless utf8::is_utf8($name);
my $area=$w->{warningsArea}//'';
$area=decode_utf8($area) unless utf8::is_utf8($area);
my $condition=$w->{forecast}{hourly}[0]{condition}//'';
$condition=decode_utf8($condition) unless utf8::is_utf8($condition);
my $summary=$w->{forecast}{daily}[0]{summaryCondition}//'';
$summary=decode_utf8($summary) unless utf8::is_utf8($summary);
print encode_json({result=>{status=>$w->{status},locationSource=>$w->{locationSource},
 station=>$w->{observationStation},stationName=>$name,stationDistanceKm=>$w->{stationDistanceKm},
 locationAltitude=>$w->{locationAltitude},locationAltitudeSource=>$w->{locationAltitudeSource},
 stationSelectionMethod=>$w->{stationSelectionMethod},stationAltitudeDifference_m=>$w->{stationAltitudeDifference_m},
 temperature=>$w->{current}{temperature},measurementTime=>$w->{current}{measurementTime},
 dewPoint=>$w->{current}{dewPoint},globalRadiation=>$w->{current}{globalRadiation},
 sunshineDuration_s=>$w->{current}{sunshineDuration_s},
 sunshinePeriodStart=>$w->{current}{sunshinePeriodStart},sunshinePeriodEnd=>$w->{current}{sunshinePeriodEnd},
 hourlySteps=>$w->{forecastHoursAvailable},firstForecastCondition=>$condition,
 firstForecastPrecipitation=>$w->{forecast}{hourly}[0]{precipitation},
 firstForecastRain1h=>$w->{forecast}{hourly}[0]{rain1h},
 firstForecastPrecipitationPeriodStart=>$w->{forecast}{hourly}[0]{precipitationPeriodStart},
 firstForecastPrecipitationPeriodEnd=>$w->{forecast}{hourly}[0]{precipitationPeriodEnd},
 firstForecastDewPoint=>$w->{forecast}{hourly}[0]{dewPoint},
 firstForecastGlobalRadiation=>$w->{forecast}{hourly}[0]{globalRadiation},
 firstForecastSunshineDuration_s=>$w->{forecast}{hourly}[0]{sunshineDuration_s},
 todayPrecipitation=>$w->{forecast}{daily}[0]{precipitation},
 todayPrecipitationCoverage=>$w->{forecast}{daily}[0]{precipitationCoverage},
 todayRainTotal_mm=>$w->{forecast}{daily}[0]{rainTotal_mm},
 todaySunshineDuration_s=>$w->{forecast}{daily}[0]{sunshineDuration_s},
 todaySunshineCoverage=>$w->{forecast}{daily}[0]{sunshineCoverage},
 todaySummaryCondition=>$summary,
 forecastStatus=>$w->{forecastStatus},forecastValidity=>$w->{forecastValidity},
 forecastLastError=>$w->{forecastLastError},forecastReferenceTime=>$w->{forecastReferenceTime},
 warningsStatus=>$w->{warningsStatus},warningsCount=>$w->{warningsCount},warningsArea=>$area,
 warningsLatitude=>$w->{warningsLatitude},warningsLongitude=>$w->{warningsLongitude},
 nowcastStatus=>$w->{nowcastStatus},nowcastLastError=>$w->{nowcastLastError},nowcastPoints=>$w->{nowcastPoints},
 rainNextHour=>$w->{rainNextHour},rainNextHour_mm=>$w->{rainNextHour_mm},
 rainNextHourFrom=>$w->{rainNextHourFrom},rainNextHourTo=>$w->{rainNextHourTo},
 dropdownGenerated=>($dropdown =~ /geoSphereStation:auto,/ ? JSON::PP::true : JSON::PP::false)}})."\n";
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--location', default='48.2486,16.3564')
    parser.add_argument('--station', default='auto')
    parser.add_argument('--altitude', default='')
    parser.add_argument('--nowcast', action='store_true')
    args = parser.parse_args()
    lat, lon = args.location.split(',')
    root = Path(__file__).resolve().parents[1]
    child = subprocess.Popen(
        ['perl', '-I', str(root/'lib'), '-e', PERL, lat, lon, args.station, args.altitude, str(int(args.nowcast))],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True,
        env=dict(os.environ, TZ='Europe/Vienna'),
    )
    result = None
    count = 0
    try:
        for line in child.stdout:
            event = json.loads(line)
            if 'request' in event:
                count += 1
                if count > 8:
                    raise RuntimeError('unexpected request loop')
                url = event['request']
                if not url.startswith(('https://dataset.api.hub.geosphere.at/v1/',
                                       'https://warnungen.zamg.at/wsapp/api/')):
                    raise RuntimeError('unexpected API host')
                try:
                    request = urllib.request.Request(url, headers={'Accept': 'application/json'})
                    with urllib.request.urlopen(request, timeout=30) as response:
                        body = response.read(2_000_001)
                        if len(body) > 2_000_000:
                            raise ValueError('API response unexpectedly large')
                        reply = dict(code=response.status, body=body.decode('utf-8'))
                except urllib.error.HTTPError as error:
                    reply = dict(code=error.code, error=f'HTTP {error.code}')
                except Exception as error:
                    reply = dict(code=0, error=str(error))
                child.stdin.write(json.dumps(reply)+'\n')
                child.stdin.flush()
            else:
                result = event['result']
        code = child.wait(timeout=10)
        if code or not result:
            raise RuntimeError(f'Perl test failed ({code})')
    finally:
        child.stdin.close()
        if child.poll() is None:
            child.kill()
            child.wait()
    print(json.dumps(dict(requests=count, **result), ensure_ascii=False, indent=2))
    if result['status'] != 'ok' or result['warningsStatus'] != 'ok':
        raise SystemExit('Live-Test fehlgeschlagen; Status auswerten.')
    print('Messwerte und Warnungsabruf erfolgreich; Prognosestatus: '+str(result.get('forecastStatus'))+'. Keine FHEM-Geräte oder Konfigurationen verändert.')


if __name__ == '__main__':
    main()
